"""Anki card-creation HTTP service.

Manages per-user Anki collections on disk and syncs them to ankiweb.net.
The openclaw skill posts here; cards land on users' phones via AnkiWeb.

API (REST-shaped, generic):
    GET    /health
    POST   /cards           Add a card. Optional `auto:` block has the bot
                            generate the image / audio from prompts.
    GET    /cards           Search via Anki query syntax. ?user=&query=&limit=
    GET    /cards/{nid}     One note by ID.
    PATCH  /cards/{nid}     Edit fields / tags.
    DELETE /cards/{nid}     Delete one note by ID.
    DELETE /cards           Bulk delete by query.
    GET    /curriculum      ?user= [&next=N] — next-N words, or current progress.
    PATCH  /curriculum      Advance cursor / mark taught.
    DELETE /curriculum      Reset progress to 0.
    GET    /media/{user}/{filename}
    DELETE /media/{user}    Wipe a user's media directory.
"""
from __future__ import annotations

import asyncio
import base64
import json
import logging
import os
import re
import shutil
import struct
import time
import unicodedata
import urllib.error
import urllib.request
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from anki.collection import Collection
from anki.errors import NetworkError, SyncError
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, Response
from pydantic import BaseModel, Field

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("anki-bot")

DATA_DIR = Path(os.environ.get("ANKI_DATA_DIR", "/data"))
MEDIA_DIR = Path(os.environ.get("ANKI_MEDIA_DIR", "/data/media"))
MEDIA_BASE_URL = os.environ.get("ANKI_MEDIA_BASE_URL", "").rstrip("/")
CURRICULUM_DIR = Path(os.environ.get("ANKI_CURRICULUM_DIR", "/app/curricula"))
FIELDS = ["Word", "Audio", "IPA", "Translation", "Example", "ExampleTranslation", "Image"]


def _deck_for(prefs: dict) -> str:
    """Deck and note-type name = the user's target language. Falls back if unset."""
    return prefs.get("target_language") or "Vocabulary"

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_IMAGE_MODEL = os.environ.get("GEMINI_IMAGE_MODEL", "gemini-3.1-flash-image-preview")
GEMINI_TTS_MODEL = os.environ.get("GEMINI_TTS_MODEL", "gemini-3.1-flash-tts-preview")
TTS_VOICE = os.environ.get("TTS_VOICE", "Kore")
GEMINI_BACKEND = os.environ.get("GEMINI_BACKEND", "vertex")


def _load_curriculum_for(lang_code: str) -> dict:
    """Load a curriculum for a given language code. Returns empty if missing.

    Looks for /app/curricula/{code}.json (e.g. /app/curricula/pl.json) and
    falls back to /data/curricula/{code}.json for user-supplied curricula.
    """
    if not lang_code:
        return {"version": "0", "words": []}
    for base in (CURRICULUM_DIR, DATA_DIR / "curricula"):
        path = base / f"{lang_code}.json"
        if path.is_file():
            return json.loads(path.read_text(encoding="utf-8"))
    return {"version": "0", "words": []}


def _curriculum_for_user(user: str) -> dict:
    prefs = _load_user_prefs(user)
    return _load_curriculum_for(prefs.get("target_language_code", ""))


RESERVED_USERNAMES = {"media", "curricula", "public", "system", "admin", "user", "users"}
USERNAME_RE = re.compile(r"^[a-z][a-z0-9_-]{2,31}$")


def _user_secrets_path(user: str) -> Path:
    return DATA_DIR / user / "secrets.json"


def _load_user_secrets(user: str) -> Optional[dict]:
    p = _user_secrets_path(user)
    if not p.is_file():
        return None
    return json.loads(p.read_text(encoding="utf-8"))


def _save_user_secrets(user: str, secrets: dict) -> None:
    p = _user_secrets_path(user)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(secrets, ensure_ascii=False, indent=2), encoding="utf-8")
    try:
        p.chmod(0o600)
    except OSError:
        pass


def _user_creds() -> dict[str, dict[str, str]]:
    """Discover users from env vars AND from /data/{user}/secrets.json.

    Env vars (ANKI_<NAME>_USER + ANKI_<NAME>_PASS) provide ops-managed users
    (e.g. the homelab operator's own profile). Disk-backed users (created via
    POST /users at runtime) are how friends register through the wizard.

    Disk overrides env if the same username appears in both.
    """
    reserved_env = {"DATA", "MEDIA", "CURRICULUM", "BACKEND"}
    out: dict[str, dict[str, str]] = {}

    # 1. Env-var users
    pat = re.compile(r"^ANKI_([A-Z][A-Z0-9_]*)_USER$")
    for key in os.environ:
        m = pat.match(key)
        if not m:
            continue
        stem = m.group(1)
        if stem in reserved_env or any(stem.startswith(r + "_") for r in reserved_env):
            continue
        username = os.environ.get(key)
        password = os.environ.get(f"ANKI_{stem}_PASS")
        if username and password:
            out[stem.lower()] = {"username": username, "password": password}

    # 2. Disk-backed users (registered at runtime)
    if DATA_DIR.is_dir():
        for d in DATA_DIR.iterdir():
            if not d.is_dir() or d.name in RESERVED_USERNAMES:
                continue
            secrets = _load_user_secrets(d.name)
            if secrets and secrets.get("ankiweb_username") and secrets.get("ankiweb_password"):
                out[d.name] = {
                    "username": secrets["ankiweb_username"],
                    "password": secrets["ankiweb_password"],
                }
    return out


USERS: dict[str, dict[str, str]] = _user_creds()
_locks: dict[str, asyncio.Lock] = {u: asyncio.Lock() for u in USERS}
_auth_cache: dict[str, object] = {}


def _ensure_user_lock(user: str) -> asyncio.Lock:
    if user not in _locks:
        _locks[user] = asyncio.Lock()
    return _locks[user]


# -- Filename / ASCII helpers -----------------------------------------------

_PRECOMPOSED_TRANSLITERATIONS = str.maketrans({
    "ł": "l", "Ł": "L",
    "ø": "o", "Ø": "O",
    "æ": "ae", "Æ": "AE",
    "œ": "oe", "Œ": "OE",
    "ß": "ss",
    "đ": "d", "Đ": "D",
})


def _safe_filename(name: str) -> str:
    pre = name.translate(_PRECOMPOSED_TRANSLITERATIONS)
    normalized = unicodedata.normalize("NFKD", pre)
    ascii_only = normalized.encode("ascii", "ignore").decode("ascii")
    cleaned = re.sub(r"[^A-Za-z0-9._-]", "_", ascii_only)
    return cleaned or "card"


# -- Gemini wrappers --------------------------------------------------------

def _gemini_url(model: str) -> str:
    if GEMINI_BACKEND == "studio":
        return (
            f"https://generativelanguage.googleapis.com/v1beta/"
            f"models/{model}:generateContent?key={GEMINI_API_KEY}"
        )
    return (
        f"https://aiplatform.googleapis.com/v1/"
        f"publishers/google/models/{model}:generateContent?key={GEMINI_API_KEY}"
    )


def _http_post_json(url: str, payload: dict, timeout: float = 60.0) -> dict:
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        url, data=body, headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {e.code} from {url}: {err_body}") from e


def _gen_with_retries(fn, *args, kind: str = "media", attempts: int = 3) -> bytes:
    """Call a generation function, retrying on any failure with exponential backoff.

    Backoff: 1s, 2s, 4s before attempts 2, 3, (4 — n/a). Returns bytes on
    success. Raises the final exception if all attempts fail.
    """
    last_err: Optional[Exception] = None
    for i in range(attempts):
        try:
            return fn(*args)
        except Exception as e:
            last_err = e
            log.warning("%s gen attempt %d/%d failed: %s", kind, i + 1, attempts, e)
            if i < attempts - 1:
                time.sleep(2 ** i)
    raise RuntimeError(
        f"{kind} generation failed after {attempts} attempts: {last_err}"
    ) from last_err


def generate_image(prompt: str) -> bytes:
    if not GEMINI_API_KEY:
        raise RuntimeError("GEMINI_API_KEY not set")
    url = _gemini_url(GEMINI_IMAGE_MODEL)
    full_prompt = (
        f"{prompt}. Simple flat illustration. White background. No text. "
        f"Single subject, centered. Minimal style, like a vocabulary flashcard."
    )
    payload = {"contents": [{"role": "user", "parts": [{"text": full_prompt}]}]}
    resp = _http_post_json(url, payload, timeout=90)
    parts = resp.get("candidates", [{}])[0].get("content", {}).get("parts", [])
    for part in parts:
        inline = part.get("inlineData") or part.get("inline_data")
        if inline and inline.get("data"):
            return base64.b64decode(inline["data"])
    raise RuntimeError(f"no image in Gemini response: {json.dumps(resp)[:500]}")


def _pcm_to_wav(pcm: bytes, sample_rate: int = 24000, channels: int = 1, sample_width: int = 2) -> bytes:
    byte_rate = sample_rate * channels * sample_width
    block_align = channels * sample_width
    header = (
        b"RIFF"
        + struct.pack("<I", 36 + len(pcm))
        + b"WAVEfmt "
        + struct.pack("<I", 16)
        + struct.pack("<H", 1)
        + struct.pack("<H", channels)
        + struct.pack("<I", sample_rate)
        + struct.pack("<I", byte_rate)
        + struct.pack("<H", block_align)
        + struct.pack("<H", sample_width * 8)
        + b"data"
        + struct.pack("<I", len(pcm))
    )
    return header + pcm


def generate_audio(text: str, language_code: str = "pl-PL") -> bytes:
    if not GEMINI_API_KEY:
        raise RuntimeError("GEMINI_API_KEY not set")
    url = _gemini_url(GEMINI_TTS_MODEL)
    # languageCode tells the safety filter the input is Polish, preventing
    # false-positive PROHIBITED_CONTENT blocks on short tokens like "tak"/"nie"
    # that collide with denylisted strings in other languages.
    payload = {
        "contents": [{"role": "user", "parts": [{"text": text}]}],
        "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {
                "languageCode": language_code,
                "voiceConfig": {"prebuiltVoiceConfig": {"voiceName": TTS_VOICE}},
            },
        },
        "safetySettings": [
            {"category": c, "threshold": "BLOCK_NONE"}
            for c in (
                "HARM_CATEGORY_HARASSMENT",
                "HARM_CATEGORY_HATE_SPEECH",
                "HARM_CATEGORY_SEXUALLY_EXPLICIT",
                "HARM_CATEGORY_DANGEROUS_CONTENT",
            )
        ],
    }
    resp = _http_post_json(url, payload, timeout=60)
    parts = resp.get("candidates", [{}])[0].get("content", {}).get("parts", [])
    for part in parts:
        inline = part.get("inlineData") or part.get("inline_data")
        if inline and inline.get("data"):
            pcm = base64.b64decode(inline["data"])
            mime = inline.get("mimeType", "")
            if pcm.startswith(b"RIFF"):
                return pcm
            sample_rate = 24000
            if "rate=" in mime:
                try:
                    sample_rate = int(mime.split("rate=")[1].split(";")[0])
                except Exception:
                    pass
            return _pcm_to_wav(pcm, sample_rate=sample_rate)
    raise RuntimeError(f"no audio in Gemini TTS response: {json.dumps(resp)[:500]}")


# -- Anki collection helpers ------------------------------------------------

def _open_collection(user: str) -> Collection:
    user_dir = DATA_DIR / user
    user_dir.mkdir(parents=True, exist_ok=True)
    col_path = user_dir / "collection.anki2"
    return Collection(str(col_path))


# Card template + CSS. Edited in code so it can be re-applied at startup.

_QFMT = (
    '<div class="word">{{Word}}</div>\n'
    '<div class="audio">{{Audio}}</div>\n'
    '<div class="ipa">{{IPA}}</div>\n'
)

# Order on the back: translation FIRST (so it's visible without scrolling),
# then example, then image at the bottom as a memory aid.
_AFMT = (
    "{{FrontSide}}\n"
    '<hr id="answer">\n'
    '<div class="translation">{{Translation}}</div>\n'
    '<div class="example">{{Example}}</div>\n'
    '<div class="example-translation">{{ExampleTranslation}}</div>\n'
    '<div class="image">{{Image}}</div>\n'
)

# Image is capped at ~25% of viewport height so the translation below stays
# visible on a phone without scrolling.
_CSS = (
    ".card{font-family:-apple-system,system-ui,sans-serif;"
    "text-align:center;color:#222;background:#fafafa;padding:0 .5em}\n"
    ".word{font-size:2.4em;font-weight:600;margin-bottom:.3em}\n"
    ".ipa{color:#888;font-size:1.1em;font-style:italic}\n"
    ".translation{font-size:1.6em;margin:.4em 0;font-weight:500}\n"
    ".example{margin-top:.6em;font-size:1.1em}\n"
    ".example-translation{color:#666;font-size:1em}\n"
    ".image{margin-top:.6em}\n"
    ".image img{"
    "max-width:50vw;max-height:22vh;width:auto;height:auto;"
    "object-fit:contain;border-radius:8px"
    "}\n"
)


def _ensure_note_type(col: Collection, prefs: dict):
    """Create or refresh the note type for this user's target language.

    The note type and deck are named after the user's `target_language` (e.g.
    "Polish", "Korean"). Template + CSS are re-applied on every call so styling
    changes propagate to existing cards after a bot restart.
    """
    name = _deck_for(prefs)
    nt = col.models.by_name(name)
    template_name = f"{name} \u2192 {prefs.get('native_language') or 'translation'}"
    if nt is None:
        nt = col.models.new(name)
        for f in FIELDS:
            col.models.add_field(nt, col.models.new_field(f))
        tmpl = col.models.new_template(template_name)
        tmpl["qfmt"] = _QFMT
        tmpl["afmt"] = _AFMT
        col.models.add_template(nt, tmpl)
        nt["css"] = _CSS
        col.models.add(nt)
        return col.models.by_name(name)

    changed = False
    if nt.get("css") != _CSS:
        nt["css"] = _CSS
        changed = True
    for tmpl in nt.get("tmpls", []):
        if tmpl.get("qfmt") != _QFMT:
            tmpl["qfmt"] = _QFMT
            changed = True
        if tmpl.get("afmt") != _AFMT:
            tmpl["afmt"] = _AFMT
            changed = True
    if changed:
        log.info("refreshing note type %r template/css", name)
        col.models.update_dict(nt)
    return nt


def _ensure_deck(col: Collection, prefs: dict) -> int:
    name = _deck_for(prefs)
    deck = col.decks.by_name(name)
    if deck:
        return deck["id"]
    return col.decks.add_normal_deck_with_name(name).id


def _sync(col: Collection, user: str) -> Optional[Collection]:
    """Sync to ankiweb.net. Returns the (possibly new) Collection, or None
    if a full sync consumed the local collection (caller must not close it again)."""
    from anki.sync_pb2 import (
        SyncAuth as PbSyncAuth,
        SyncCollectionResponse,
    )
    NO_CHANGES = SyncCollectionResponse.NO_CHANGES
    NORMAL_SYNC = SyncCollectionResponse.NORMAL_SYNC
    FULL_DOWNLOAD = SyncCollectionResponse.FULL_DOWNLOAD

    creds = USERS[user]

    def _login():
        a = col.sync_login(creds["username"], creds["password"], None)
        log.info("sync_login for %s", user)
        return a

    auth = _auth_cache.get(user) or _login()

    def _do(a):
        return col.sync_collection(a, True)

    try:
        out = _do(auth)
    except (SyncError, NetworkError) as e:
        log.warning("sync failed (%s), re-authing", e)
        auth = _login()
        out = _do(auth)

    if getattr(out, "new_endpoint", None):
        log.info("sync redirect for %s -> %s", user, out.new_endpoint)
        auth = PbSyncAuth(hkey=auth.hkey, endpoint=out.new_endpoint, io_timeout_secs=60)
        try:
            out = _do(auth)
        except (SyncError, NetworkError) as e:
            log.warning("post-redirect sync failed (%s), re-authing", e)
            fresh = _login()
            auth = PbSyncAuth(hkey=fresh.hkey, endpoint=out.new_endpoint, io_timeout_secs=60)
            out = _do(auth)
    _auth_cache[user] = auth

    log.info("sync result for %s: required=%d", user, out.required)

    if out.required in (NO_CHANGES, NORMAL_SYNC):
        return col

    upload = out.required != FULL_DOWNLOAD
    log.info("full_upload_or_download for %s upload=%s", user, upload)
    col.close_for_full_sync()
    col.full_upload_or_download(
        auth=auth, server_usn=out.server_media_usn, upload=upload
    )
    return None


# -- Per-user preferences ---------------------------------------------------
# Defaults targeted at English speakers. Each user can override via
# PATCH /users/{user}. Stored at /data/{user}/preferences.json.

DEFAULT_USER_PREFS = {
    # Set by the wizard on first interaction.
    "wizard_completed": False,

    # Language / culture
    "target_language": "",            # e.g. "Polish", "Korean"
    "target_language_code": "",       # ISO 639-1, e.g. "pl", "ko"
    "native_language": "English",
    "native_language_code": "en",

    # How the user wants pronunciation written on cards. Defaults to IPA.
    "pronunciation_style": "IPA enclosed in [brackets]",
    "pronunciation_example": "[pjɛs] for 'pies'",

    # Self-rated proficiency. zero | tourist | a1 | a2 | b1 | b2 | c1
    "proficiency_level": "zero",

    # Free-form list of topics the user is into. Drives daily conversation.
    "interests": [],

    # Telegram routing — agent uses this to map an inbound TG user to this user.
    "telegram_user_id": None,
}


def _user_prefs_path(user: str) -> Path:
    return DATA_DIR / user / "preferences.json"


def _load_user_prefs(user: str) -> dict:
    p = _user_prefs_path(user)
    custom = {}
    if p.is_file():
        custom = json.loads(p.read_text(encoding="utf-8"))
    return {**DEFAULT_USER_PREFS, **custom}


def _save_user_prefs(user: str, prefs: dict) -> None:
    p = _user_prefs_path(user)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(prefs, ensure_ascii=False, indent=2), encoding="utf-8")


# -- Curriculum / progress helpers ------------------------------------------

def _progress_path(user: str) -> Path:
    return DATA_DIR / user / "progress.json"


def _load_progress(user: str) -> dict:
    p = _progress_path(user)
    if p.is_file():
        return json.loads(p.read_text(encoding="utf-8"))
    cur = _curriculum_for_user(user)
    return {
        "curriculum_version": cur.get("version", "0"),
        "current_index": 0,
        "taught": [],
    }


def _save_progress(user: str, progress: dict) -> None:
    p = _progress_path(user)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(progress, ensure_ascii=False, indent=2), encoding="utf-8")


# -- Lifespan ---------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    for user in USERS:
        log.info("bootstrap %s", user)
        prefs = _load_user_prefs(user)
        col = _open_collection(user)
        try:
            _ensure_note_type(col, prefs)
            _ensure_deck(col, prefs)
            col = _sync(col, user)
        finally:
            if col is not None:
                col.close()
    yield


app = FastAPI(lifespan=lifespan, title="anki-bot")


# -- Request / response models ----------------------------------------------

class Media(BaseModel):
    filename: str
    data_b64: str


class CardAuto(BaseModel):
    """If present on POST /cards, the bot generates fields + media for the card.

    Strict by design: every field below is required when using `auto`. The bot
    ALWAYS generates audio (word + example sentence) AND an image, retrying on
    transient failures. If either media call ultimately fails, the card is not
    created (atomic) — the request returns 503.

    Why everything is required:
    - `example` is needed for the audio (TTS receives "{word}. {example}", which
      gives pronunciation in context AND defuses Gemini's safety filter on
      short ambiguous tokens like "tak"/"nie").
    - `image_prompt` is needed because we always render an image.
    - `translation` and `ipa` go on the card front/back.
    """
    word: str = Field(min_length=1)
    translation: str = Field(min_length=1)
    ipa: str = Field(min_length=1)
    example: str = Field(min_length=1)
    example_translation: str = Field(min_length=1)
    image_prompt: str = Field(min_length=1)


class CardCreate(BaseModel):
    user: str
    fields: dict[str, str] = Field(default_factory=dict)
    audio: Optional[Media] = None
    image: Optional[Media] = None
    tags: list[str] = Field(default_factory=lambda: ["telegram"])
    auto: Optional[CardAuto] = None


class CardResponse(BaseModel):
    success: bool
    note_id: int
    synced: bool
    image_generated: bool = False
    audio_generated: bool = False


class CardPatch(BaseModel):
    user: str
    fields: dict[str, str] = Field(default_factory=dict)
    add_tags: list[str] = Field(default_factory=list)
    remove_tags: list[str] = Field(default_factory=list)


class CurriculumPatch(BaseModel):
    user: str
    mark_taught: list[str] = Field(default_factory=list)
    note_ids: list[int] = Field(default_factory=list)


class UserCreate(BaseModel):
    """Register a new user via the wizard. AnkiWeb credentials are validated
    against sync.ankiweb.net before the user is persisted; a 400 with the
    server's error message is returned on failure.

    `username` is a slug (a-z, 0-9, _ -, 3-32 chars). If omitted, the agent
    should generate one from the user's Telegram handle.
    """
    username: str = Field(min_length=3, max_length=32)
    ankiweb_username: str = Field(min_length=3)
    ankiweb_password: str = Field(min_length=1)
    # Wizard-collected preferences applied immediately:
    target_language: str = Field(min_length=1)
    target_language_code: str = Field(min_length=2, max_length=10)
    native_language: str = Field(min_length=1)
    native_language_code: str = Field(min_length=2, max_length=10)
    proficiency_level: str = Field(min_length=1)
    pronunciation_style: str = Field(min_length=1)
    pronunciation_example: str = Field(min_length=1)
    interests: list[str] = Field(default_factory=list)
    telegram_user_id: int


class UserPrefsPatch(BaseModel):
    """Partial update for user preferences. Any field set here overwrites; the
    rest are preserved. Set `wizard_completed=true` once the wizard is done."""
    wizard_completed: Optional[bool] = None
    target_language: Optional[str] = None
    target_language_code: Optional[str] = None
    native_language: Optional[str] = None
    native_language_code: Optional[str] = None
    pronunciation_style: Optional[str] = None
    pronunciation_example: Optional[str] = None
    proficiency_level: Optional[str] = None
    interests: Optional[list[str]] = None
    telegram_user_id: Optional[int] = None


# -- Generic helpers --------------------------------------------------------

def _check_user(user: str) -> None:
    if user not in USERS:
        raise HTTPException(400, f"unknown user: {user}")


def _store_media(user: str, filename: str, data_b64: str) -> str:
    if not MEDIA_BASE_URL:
        raise RuntimeError("ANKI_MEDIA_BASE_URL not configured")
    fname = _safe_filename(filename)
    user_dir = MEDIA_DIR / user
    user_dir.mkdir(parents=True, exist_ok=True)
    (user_dir / fname).write_bytes(base64.b64decode(data_b64))
    return f"{MEDIA_BASE_URL}/{user}/{fname}"


def _serialize_note(col: Collection, nid: int) -> dict:
    note = col.get_note(nid)
    field_names = [f["name"] for f in note.note_type()["flds"]]
    return {
        "note_id": int(note.id),
        "fields": dict(zip(field_names, note.fields)),
        "tags": list(note.tags),
        "model": note.note_type()["name"],
    }


# -- Endpoints --------------------------------------------------------------

@app.get("/health")
async def health():
    available_curricula = []
    if CURRICULUM_DIR.is_dir():
        available_curricula = sorted(p.stem for p in CURRICULUM_DIR.glob("*.json"))
    return {
        "status": "ok",
        "users": list(USERS.keys()),
        "gemini_configured": bool(GEMINI_API_KEY),
        "gemini_backend": GEMINI_BACKEND,
        "image_model": GEMINI_IMAGE_MODEL,
        "tts_model": GEMINI_TTS_MODEL,
        "media_base_url": MEDIA_BASE_URL or None,
        "available_curricula": available_curricula,
    }


# -- /cards -----------------------------------------------------------------

@app.post("/cards", response_model=CardResponse)
async def create_card(req: CardCreate):
    """Add a card. If `req.auto` is set, the bot generates image+audio+fields."""
    _check_user(req.user)

    fields = dict(req.fields)
    audio_obj = req.audio
    image_obj = req.image
    image_generated = False
    audio_generated = False

    if req.auto:
        a = req.auto
        # Linguistic fields the agent supplies (Pydantic guarantees all present + non-empty).
        fields.setdefault("Word", a.word)
        fields.setdefault("Translation", a.translation)
        fields.setdefault("IPA", a.ipa)
        fields.setdefault("Example", a.example)
        fields.setdefault("ExampleTranslation", a.example_translation)

        safe = _safe_filename(a.word)
        tts_text = f"{a.word}. {a.example}"  # ALWAYS combined — context aids learning + sidesteps safety filter

        # Generate audio + image in parallel, with retries on transient errors.
        # If either ultimately fails, raise 503 — we never persist a half-card.
        try:
            audio_bytes, image_bytes = await asyncio.gather(
                asyncio.to_thread(_gen_with_retries, generate_audio, tts_text, kind="audio"),
                asyncio.to_thread(_gen_with_retries, generate_image, a.image_prompt, kind="image"),
            )
        except Exception as e:
            raise HTTPException(503, f"media generation failed: {e}")

        audio_obj = Media(
            filename=f"{safe}.wav",
            data_b64=base64.b64encode(audio_bytes).decode(),
        )
        image_obj = Media(
            filename=f"{safe}.png",
            data_b64=base64.b64encode(image_bytes).decode(),
        )
        audio_generated = True
        image_generated = True

    async with _locks[req.user]:
        prefs = _load_user_prefs(req.user)
        col = _open_collection(req.user)
        try:
            deck_id = _ensure_deck(col, prefs)
            nt = _ensure_note_type(col, prefs)

            if audio_obj:
                url = _store_media(req.user, audio_obj.filename, audio_obj.data_b64)
                fields["Audio"] = (
                    f'<audio controls src="{url}" preload="auto"></audio>'
                )
            if image_obj:
                url = _store_media(req.user, image_obj.filename, image_obj.data_b64)
                fields["Image"] = f'<img src="{url}">'

            note = col.new_note(nt)
            for f in FIELDS:
                note[f] = fields.get(f, "")
            for tag in req.tags:
                if tag not in note.tags:
                    note.tags.append(tag)
            col.add_note(note, deck_id)

            synced = True
            try:
                col = _sync(col, req.user)
            except Exception as e:
                log.exception("sync failed for %s: %s", req.user, e)
                synced = False

            return CardResponse(
                success=True,
                note_id=int(note.id),
                synced=synced,
                image_generated=image_generated,
                audio_generated=audio_generated,
            )
        finally:
            if col is not None:
                col.close()


@app.get("/cards")
async def list_cards(user: str, query: str = "", limit: int = 50, offset: int = 0):
    """Search notes by Anki query syntax. Examples:
        ?query=                    all notes
        ?query=deck:Polish         notes in Polish deck
        ?query=tag:auto            tagged 'auto'
        ?query=added:1             added in last day
        ?query=Word:pies           field-match
    """
    _check_user(user)
    async with _locks[user]:
        col = _open_collection(user)
        try:
            nids = list(col.find_notes(query))
            total = len(nids)
            page = nids[offset : offset + limit]
            return {
                "total": total,
                "offset": offset,
                "limit": limit,
                "notes": [_serialize_note(col, nid) for nid in page],
            }
        finally:
            col.close()


@app.get("/cards/{nid}")
async def get_card(nid: int, user: str):
    _check_user(user)
    async with _locks[user]:
        col = _open_collection(user)
        try:
            try:
                return _serialize_note(col, nid)
            except Exception:
                raise HTTPException(404, f"note {nid} not found")
        finally:
            col.close()


@app.patch("/cards/{nid}")
async def patch_card(nid: int, req: CardPatch):
    _check_user(req.user)
    async with _locks[req.user]:
        col = _open_collection(req.user)
        try:
            try:
                note = col.get_note(nid)
            except Exception:
                raise HTTPException(404, f"note {nid} not found")
            for k, v in req.fields.items():
                if k in note:
                    note[k] = v
            for t in req.add_tags:
                if t not in note.tags:
                    note.tags.append(t)
            for t in req.remove_tags:
                if t in note.tags:
                    note.tags.remove(t)
            col.update_note(note)

            synced = True
            try:
                col = _sync(col, req.user)
            except Exception as e:
                log.exception("sync failed for %s: %s", req.user, e)
                synced = False
            return {
                "success": True,
                "note_id": nid,
                "synced": synced,
                "note": _serialize_note(col, nid) if col else None,
            }
        finally:
            if col is not None:
                col.close()


@app.delete("/cards/{nid}")
async def delete_card(nid: int, user: str):
    _check_user(user)
    async with _locks[user]:
        col = _open_collection(user)
        try:
            col.remove_notes([nid])
            synced = True
            try:
                col = _sync(col, user)
            except Exception as e:
                log.exception("sync failed for %s: %s", user, e)
                synced = False
            return {"success": True, "removed": [nid], "synced": synced}
        finally:
            if col is not None:
                col.close()


@app.delete("/cards")
async def bulk_delete_cards(user: str, query: str = ""):
    """Bulk delete notes matching the Anki query. Use query='' to wipe all."""
    _check_user(user)
    async with _locks[user]:
        col = _open_collection(user)
        try:
            nids = list(col.find_notes(query))
            if nids:
                col.remove_notes(nids)
            synced = True
            try:
                col = _sync(col, user)
            except Exception as e:
                log.exception("sync failed for %s: %s", user, e)
                synced = False
            return {
                "success": True,
                "removed_count": len(nids),
                "removed_ids": nids,
                "synced": synced,
            }
        finally:
            if col is not None:
                col.close()


# -- /curriculum ------------------------------------------------------------

@app.get("/curriculum")
async def get_curriculum(user: str, next: int = 0):
    """Without `next`: return progress info only.
    With `next=N`: also return the next N untaught words from the cursor.
    Curriculum is auto-selected based on the user's target_language_code."""
    _check_user(user)
    progress = _load_progress(user)
    cur = _curriculum_for_user(user)
    words = cur.get("words", [])
    idx = progress["current_index"]
    body = {
        "user": user,
        "current_index": idx,
        "total": len(words),
        "remaining": max(0, len(words) - idx),
        "taught_count": len(progress.get("taught", [])),
        "recent_taught": progress.get("taught", [])[-10:],
        "curriculum_version": cur.get("version"),
    }
    if next > 0:
        body["next_words"] = words[idx : idx + next]
    return body


@app.patch("/curriculum")
async def patch_curriculum(req: CurriculumPatch):
    """Mark words as taught and advance the cursor by len(mark_taught)."""
    _check_user(req.user)
    progress = _load_progress(req.user)
    now_iso = datetime.now(timezone.utc).isoformat()
    for i, word in enumerate(req.mark_taught):
        progress["taught"].append({
            "word": word,
            "taught_at": now_iso,
            "note_id": req.note_ids[i] if i < len(req.note_ids) else None,
        })
    progress["current_index"] += len(req.mark_taught)
    _save_progress(req.user, progress)
    cur = _curriculum_for_user(req.user)
    return {
        "success": True,
        "current_index": progress["current_index"],
        "total": len(cur.get("words", [])),
    }


@app.delete("/curriculum")
async def reset_curriculum(user: str):
    _check_user(user)
    cur = _curriculum_for_user(user)
    _save_progress(user, {
        "curriculum_version": cur.get("version", "0"),
        "current_index": 0,
        "taught": [],
    })
    return {"success": True}


# -- /media -----------------------------------------------------------------

@app.get("/media/{user}/{filename}")
async def get_media(user: str, filename: str):
    safe_user = re.sub(r"[^A-Za-z0-9_-]", "", user) or "_"
    safe_filename = re.sub(r"[^A-Za-z0-9._-]", "", filename) or "_"
    if safe_user != user or safe_filename != filename:
        raise HTTPException(404)
    path = (MEDIA_DIR / safe_user / safe_filename).resolve()
    if not path.is_file():
        raise HTTPException(404)
    if not str(path).startswith(str(MEDIA_DIR.resolve())):
        raise HTTPException(404)
    return FileResponse(path)


# -- /users (preferences + routing + registration) --------------------------

def _validate_ankiweb_creds(ankiweb_username: str, ankiweb_password: str) -> None:
    """Verify the AnkiWeb username+password by attempting sync_login. Raises
    HTTPException(400) with a friendly message if the creds are rejected."""
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        col = Collection(str(Path(tmp) / "verify.anki2"))
        try:
            col.sync_login(ankiweb_username, ankiweb_password, None)
        except Exception as e:
            raise HTTPException(400, f"AnkiWeb login failed: {e}")
        finally:
            col.close()


@app.post("/users")
async def create_user(req: UserCreate):
    """Register a new user. Validates AnkiWeb creds, persists secrets + prefs,
    and bootstraps the user's Anki collection. Idempotent on telegram_user_id —
    if a user already exists for the given TG id, returns that user instead."""
    # 1. Has this TG id already been claimed?
    for u in USERS:
        prefs = _load_user_prefs(u)
        if prefs.get("telegram_user_id") == req.telegram_user_id:
            return {
                "user": u,
                "preferences": prefs,
                "already_registered": True,
            }

    # 2. Validate username
    if not USERNAME_RE.match(req.username):
        raise HTTPException(
            400,
            "username must be 3-32 chars, lowercase letters/digits/dashes/underscores, starting with a letter",
        )
    if req.username in RESERVED_USERNAMES:
        raise HTTPException(400, f"username {req.username!r} is reserved")
    if req.username in USERS:
        raise HTTPException(409, f"username {req.username!r} is already taken")

    # 3. Validate AnkiWeb creds (network call to sync.ankiweb.net)
    await asyncio.to_thread(_validate_ankiweb_creds, req.ankiweb_username, req.ankiweb_password)

    # 4. Persist secrets + preferences
    _save_user_secrets(req.username, {
        "ankiweb_username": req.ankiweb_username,
        "ankiweb_password": req.ankiweb_password,
    })
    prefs = dict(DEFAULT_USER_PREFS)
    prefs.update({
        "wizard_completed": True,
        "target_language": req.target_language,
        "target_language_code": req.target_language_code,
        "native_language": req.native_language,
        "native_language_code": req.native_language_code,
        "proficiency_level": req.proficiency_level,
        "pronunciation_style": req.pronunciation_style,
        "pronunciation_example": req.pronunciation_example,
        "interests": req.interests,
        "telegram_user_id": req.telegram_user_id,
    })
    _save_user_prefs(req.username, prefs)

    # 5. Register in-memory
    USERS[req.username] = {
        "username": req.ankiweb_username,
        "password": req.ankiweb_password,
    }
    _ensure_user_lock(req.username)

    # 6. Bootstrap collection (open + ensure deck/note type + first sync)
    async with _locks[req.username]:
        col = _open_collection(req.username)
        try:
            _ensure_note_type(col, prefs)
            _ensure_deck(col, prefs)
            col = _sync(col, req.username)
        finally:
            if col is not None:
                col.close()

    return {"user": req.username, "preferences": prefs, "already_registered": False}


@app.delete("/users/{user}")
async def delete_user(user: str):
    """Remove a user's preferences, secrets, collection, and media. Use with
    care — this is irreversible (the AnkiWeb collection itself is untouched)."""
    if user not in USERS:
        raise HTTPException(404, f"unknown user: {user}")
    USERS.pop(user, None)
    _auth_cache.pop(user, None)
    user_dir = DATA_DIR / user
    if user_dir.is_dir():
        shutil.rmtree(user_dir)
    user_media = MEDIA_DIR / user
    if user_media.is_dir():
        shutil.rmtree(user_media)
    return {"success": True, "user": user}


@app.get("/users")
async def list_users():
    """Return all configured users with their preferences, for agent lookup."""
    return {u: _load_user_prefs(u) for u in USERS}


@app.get("/users/by-telegram/{tg_id}")
async def find_user_by_telegram(tg_id: int):
    """Resolve an inbound Telegram user ID to one of the configured users.
    Returns 404 if no user has registered this telegram_user_id (yet)."""
    for u in USERS:
        prefs = _load_user_prefs(u)
        if prefs.get("telegram_user_id") == tg_id:
            return {"user": u, "preferences": prefs}
    raise HTTPException(404, f"no user registered for telegram_user_id={tg_id}")


@app.get("/users/{user}")
async def get_user_prefs(user: str):
    _check_user(user)
    return _load_user_prefs(user)


@app.patch("/users/{user}")
async def patch_user_prefs(user: str, req: UserPrefsPatch):
    _check_user(user)
    prefs = _load_user_prefs(user)
    update = req.model_dump(exclude_unset=True)
    prefs.update(update)
    _save_user_prefs(user, prefs)
    return prefs


# -- /v1/audio/speech (OpenAI-compatible TTS, served via Gemini) ------------
# Lets openclaw use Gemini-quality TTS for chat voice clips by configuring
# `messages.tts.openai.baseUrl=http://anki-bot:8080/v1`. The `model` and
# `voice` fields in the request are accepted but ignored — the bot uses its
# own GEMINI_TTS_MODEL and TTS_VOICE.

class OpenAITTSRequest(BaseModel):
    model: str = "gemini-tts"
    input: str = Field(min_length=1, max_length=4096)
    voice: str = "Kore"
    response_format: str = "wav"
    speed: float = 1.0


@app.post("/v1/audio/speech")
async def openai_compat_tts(req: OpenAITTSRequest):
    try:
        audio_bytes = await asyncio.to_thread(
            _gen_with_retries, generate_audio, req.input, kind="audio"
        )
    except Exception as e:
        raise HTTPException(503, f"TTS generation failed: {e}")
    return Response(content=audio_bytes, media_type="audio/wav")


@app.delete("/media/{user}")
async def wipe_media(user: str):
    _check_user(user)
    user_media = MEDIA_DIR / user
    removed = 0
    if user_media.is_dir():
        for f in user_media.iterdir():
            if f.is_file():
                f.unlink()
                removed += 1
    return {"success": True, "removed_count": removed}

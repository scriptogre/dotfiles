#!/usr/bin/env python3
"""
Mirrors all GitHub repos for a user to a Gitea instance.
Runs in a loop — checks for new repos every SYNC_INTERVAL (default 24h),
creates Gitea mirrors for any that don't exist yet.
Gitea handles the ongoing git sync (pull) via its built-in mirror interval.
"""

import json
import os
import sys
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone

GITHUB_USER = os.environ["GITHUB_USER"]
GITHUB_TOKEN = os.environ["GITHUB_TOKEN"]
GITEA_URL = os.environ["GITEA_URL"]  # e.g. https://gitea.christiantanul.com
GITEA_TOKEN = os.environ["GITEA_TOKEN"]
GITEA_OWNER = os.environ["GITEA_OWNER"]  # e.g. chris
MIRROR_INTERVAL = os.environ.get("MIRROR_INTERVAL", "8h")
SYNC_INTERVAL = os.environ.get("SYNC_INTERVAL", "24h")  # how often to check for new repos
HEALTH_FILE = "/tmp/healthcheck"


def parse_duration(s: str) -> int:
    """Parse a duration string like '24h', '30m', '1d' to seconds."""
    s = s.strip()
    multipliers = {"s": 1, "m": 60, "h": 3600, "d": 86400}
    if s[-1] in multipliers:
        return int(s[:-1]) * multipliers[s[-1]]
    return int(s)


def log(msg: str):
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    print(f"{ts} - {msg}", flush=True)


def log_error(msg: str):
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    print(f"{ts} - ERROR: {msg}", file=sys.stderr, flush=True)


def write_health(status: str, detail: str = ""):
    """Write health status to file for Docker healthcheck."""
    with open(HEALTH_FILE, "w") as f:
        ts = datetime.now(timezone.utc).isoformat()
        f.write(json.dumps({"status": status, "detail": detail, "last_check": ts}))


def api_get(url: str, headers: dict) -> list | dict:
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def api_post(url: str, headers: dict, data: dict) -> dict:
    body = json.dumps(data).encode()
    req = urllib.request.Request(url, data=body, headers={**headers, "Content-Type": "application/json"})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def get_all_github_repos() -> list[dict]:
    """Fetch all repos for the authenticated GitHub user (handles pagination)."""
    repos = []
    page = 1
    while True:
        url = f"https://api.github.com/user/repos?per_page=100&page={page}&affiliation=owner"
        headers = {"Authorization": f"token {GITHUB_TOKEN}", "Accept": "application/vnd.github.v3+json"}
        batch = api_get(url, headers)
        if not batch:
            break
        repos.extend(batch)
        page += 1
    return repos


def get_all_gitea_repos() -> dict[str, dict]:
    """Fetch all repos for the Gitea owner (handles pagination)."""
    repos = {}
    page = 1
    while True:
        url = f"{GITEA_URL}/api/v1/repos/search?owner={GITEA_OWNER}&limit=50&page={page}"
        headers = {"Authorization": f"token {GITEA_TOKEN}"}
        data = api_get(url, headers)
        batch = data.get("data", []) if isinstance(data, dict) else data
        if not batch:
            break
        for r in batch:
            repos[r["name"]] = r
        page += 1
    return repos


def create_mirror(gh_repo: dict):
    """Create a Gitea mirror repo from a GitHub repo."""
    url = f"{GITEA_URL}/api/v1/repos/migrate"
    headers = {"Authorization": f"token {GITEA_TOKEN}"}
    data = {
        "clone_addr": gh_repo["clone_url"],
        "mirror": True,
        "mirror_interval": MIRROR_INTERVAL,
        "repo_name": gh_repo["name"],
        "repo_owner": GITEA_OWNER,
        "service": "github",
        "auth_token": GITHUB_TOKEN,
        "private": gh_repo["private"],
        "description": gh_repo.get("description") or "",
    }
    return api_post(url, headers, data)



def handle_http_error(e: urllib.error.HTTPError, context: str) -> str:
    """Handle HTTP errors with clear messages. Returns error description."""
    body = e.read().decode()
    if e.code == 401:
        msg = f"{context}: Authentication failed (401). Token may have expired. {body}"
        log_error(msg)
        return msg
    elif e.code == 403:
        msg = f"{context}: Forbidden (403). Token may lack required permissions. {body}"
        log_error(msg)
        return msg
    else:
        msg = f"{context}: HTTP {e.code} {body}"
        log_error(msg)
        return msg


def main():
    log("Fetching GitHub repos...")
    try:
        gh_repos = get_all_github_repos()
    except urllib.error.HTTPError as e:
        msg = handle_http_error(e, "GitHub API")
        write_health("unhealthy", msg)
        return
    log(f"  Found {len(gh_repos)} repos on GitHub")

    log("Fetching Gitea repos...")
    try:
        gitea_repos = get_all_gitea_repos()
    except urllib.error.HTTPError as e:
        msg = handle_http_error(e, "Gitea API")
        write_health("unhealthy", msg)
        return
    log(f"  Found {len(gitea_repos)} repos on Gitea")

    created = 0
    skipped = 0
    errors = 0

    for gh_repo in gh_repos:
        name = gh_repo["name"]
        existing = gitea_repos.get(name)

        if existing:
            skipped += 1
            continue

        log(f"  Mirroring: {name} (private={gh_repo['private']})")
        try:
            create_mirror(gh_repo)
            created += 1
        except urllib.error.HTTPError as e:
            handle_http_error(e, f"Mirroring {name}")
            errors += 1

    summary = f"{created} created, {skipped} skipped, {errors} errors"
    log(f"Done: {summary}")

    if errors > 0:
        write_health("degraded", f"{errors} errors during sync")
    else:
        write_health("healthy", summary)


if __name__ == "__main__":
    interval = parse_duration(SYNC_INTERVAL)
    log(f"Starting gitea-mirror-sync (checking every {SYNC_INTERVAL})")
    while True:
        try:
            main()
        except Exception as e:
            log_error(str(e))
            write_health("unhealthy", str(e))
        log(f"Sleeping {SYNC_INTERVAL} until next check...")
        time.sleep(interval)

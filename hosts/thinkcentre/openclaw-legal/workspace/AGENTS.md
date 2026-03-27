# AGENTS — Instrucțiuni operaționale

## Cunoașterea cazului

Citește `/home/node/dosar-maghieru/CLAUDE.md` pentru toate regulile și convențiile cazului. Acesta e documentul principal — urmează-l exact.

Repo-ul este la `/home/node/dosar-maghieru/`. Citește mereu `FAPTE.md` complet înainte de a răspunde la întrebări despre caz.

## Workflow Git

- **Înainte de a citi orice fișier:** `cd /home/node/dosar-maghieru && git checkout main && git pull`
- **Nu face commit pe main.** Creează branch-uri: `claudia/<topic-descriptiv>` (ex: `claudia/expertiza-ionita`)
- **Push și PR:** După ce faci commit pe branch, push și creează PR cu `gh pr create`
- **Autentificare git:** Token-ul din env var `GITHUB_TOKEN` — configurează cu:
  ```bash
  git config --global credential.helper '!f() { echo "password=$GITHUB_TOKEN"; }; f'
  ```
- **Dacă git-ul se strică:** Șterge repo-ul și clonează din nou:
  ```bash
  rm -rf /home/node/dosar-maghieru
  git clone https://github.com/scriptogre/dosar-maghieru.git /home/node/dosar-maghieru
  ```

## Crearea PR-urilor

Folosește formatul acesta pentru body-ul PR-ului:

```markdown
## Sursă

Ce a trimis/spus Claudia (rezumat scurt, cu citat direct dacă e relevant).

## Ce am înțeles

Interpretarea: ce fapte noi, ce opinii, ce documente.

## Modificări

- `FAPTE.md` — [ce s-a adăugat/modificat și unde]
- `01-Partaj/2026-XX-XX_Nume_Document.md` — [transcriere nouă]
- etc.

## De verificat

Orice lucru nesigur sau care necesită atenția lui Christian.
```

Grupează modificările pe topic — un PR per subiect, nu un PR per mesaj.

## Duplicate

Înainte de a procesa un PDF nou, verifică dacă un fișier cu nume similar sau conținut similar există deja. Dacă e duplicat, spune-i Claudiei natural fără să o faci să se simtă prost.

## Escalare

Când ceva e prea complex sau dincolo de capabilitățile tale, spune-i Claudiei natural că Christian trebuie să ajute cu acea parte specifică.

## Memorie

- După conversații importante, actualizează MEMORY.md cu informații cheie
- Când Claudia oferă context nou, actualizează USER.md

## PDF-uri

**NU citi niciodată fișiere PDF direct.** Trimite-le la Gemini pentru transcriere și citește doar rezultatul .md. Vezi skill-ul `gemini-transcription` pentru detalii.

# AGENTS — Instrucțiuni operaționale

## Cunoașterea cazului

Citește `/home/node/dosar-maghieru/CLAUDE.md` pentru toate regulile și convențiile cazului. Acesta e documentul principal — urmează-l exact.

Repo-ul este la `/home/node/dosar-maghieru/`. Citește mereu `FAPTE.md` complet înainte de a răspunde la întrebări despre caz.

## Workflow Git

- **Înainte de a citi orice fișier:** `cd /home/node/dosar-maghieru && git checkout master && git pull && cp CLAUDE.md /home/node/.openclaw/workspace/BOOT.md`
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

## Când Claudia trimite un PDF

**NICIODATĂ nu tragi concluzii despre un document înainte de a-l citi.**

Tool-ul `pdf` folosește Gemini pentru transcriere. Poți citi PDF-uri direct cu tool-ul `pdf`.

Workflow obligatoriu — în ordine:

1. **Spune-i Claudiei:** „Procesez documentul, un moment." (nu analiza, nu concluzii, nu speculații)
2. **Verifică dacă documentul există deja** — listează fișierele din repo și caută după nume similar sau conținut similar
3. **Dacă există `.md`:** citește transcrierea existentă
4. **Dacă NU există `.md`:** folosește tool-ul `pdf` cu promptul de transcriere verbatim (vezi mai jos), salvează rezultatul ca `.md` lângă PDF, apoi citește transcrierea
5. **Abia acum** poți răspunde Claudiei despre conținutul documentului
6. **Urmează workflow-ul din CLAUDE.md** pentru actualizarea FAPTE.md, STRATEGIE.md, și crearea PR-ului

**Promptul pentru transcriere PDF:**
```
Transcrie acest document PDF în format Markdown. Păstrează structura originală. Marchează paginile cu **— PAGINA N —**. Notează ștampilele cu [Ștampilă: DESCRIERE]. Notează semnăturile cu [Semnătură: NUME]. Păstrează tot textul original, inclusiv date, numere, nume. Nu omite nimic. Nu traduce — păstrează limba originală. FOARTE IMPORTANT: Dacă un cuvânt sau fragment NU se poate citi clar, scrie [greu lizibil] în loc. NU inventa sau ghici cuvinte — e mai bine să marchezi [greu lizibil] decât să scrii un cuvânt greșit. Acuratețea e critică: acest text va fi folosit ca probă juridică.
```

**Fișierul `.md` salvat trebuie să aibă frontmatter:**
```yaml
---
verificat: false
nota: "Transcriere Gemini — de verificat manual cu PDF-ul original"
---
```

**NU sări peste pașii 1-5.** Nu răspunde niciodată despre conținutul unui document pe baza presupunerilor tale — doar pe baza textului citit din `.md`.

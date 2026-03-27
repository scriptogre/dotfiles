---
name: dosar-maghieru
description: "Cunoașterea și regulile cazului juridic dosar-maghieru. Folosește la orice întrebare despre caz, documente, fapte, strategie sau legislație relevantă."
---

# Dosar Maghieru — Skill

## Cum să folosești acest skill

1. **Citește CLAUDE.md din repo:** `/home/node/dosar-maghieru/CLAUDE.md` — acesta conține toate regulile, convențiile de denumire, structura folderelor și workflow-ul de lucru cu dosarul. Urmează-l exact.

2. **Citește FAPTE.md complet** înainte de a răspunde la orice întrebare despre caz. Nu citi parțial.

3. **Caută în fișierele .md** (transcrieri) când ai nevoie de detalii dintr-un document specific.

4. **NU citi fișiere PDF.** Folosește doar transcrierile .md. Dacă un document nu are transcriere, trimite PDF-ul la Gemini prin skill-ul `gemini-transcription`.

## Sincronizare repo

Înainte de a citi orice fișier din repo:

```bash
cd /home/node/dosar-maghieru && git checkout main && git pull
```

## Structura dosarului

Repo-ul e la `/home/node/dosar-maghieru/`. Citește CLAUDE.md pentru structura completă. Pe scurt:

- `FAPTE.md` — sursa de adevăr (fapte brute, cronologie, referințe)
- `STRATEGIE.md` — perspective subiective ale clientului, ipoteze
- `LEGE.md` — întrebări juridice validate cu temei legal de pe legislatie.just.ro
- `01-Partaj/` — dosarul de partaj
- `02-Apel/` — dosarul de anulare promisiune
- `03-Penal/` — plângerea penală
- `04-Documente-Suport/` — documente relevante pentru 2+ dosare

## Reguli critice

- **FAPTE.md = doar fapte.** Opinii, emoții, strategii → STRATEGIE.md
- **LEGE.md = doar legislatie.just.ro.** Nicio altă sursă nu e acceptată.
- **Citează cu link-uri.** Când menționezi o lege, oferă link-ul complet de pe legislatie.just.ro.
- **Transparență.** Spune-i Claudiei când cauți în legislație sau în documente.

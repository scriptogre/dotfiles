---
name: gemini-transcription
description: "Transcrie documente PDF în format Markdown folosind Gemini API. Folosește când Claudia trimite un PDF sau când trebuie transcris un document existent. De asemenea, poate face cercetare juridică aprofundată prin Gemini."
---

# Gemini Transcription & Research

## Regula #1: NU citi PDF-uri direct

**Nu folosi niciodată tool-ul `read` sau `pdf` pe fișiere PDF.** Asta va umple contextul și va consuma token-uri inutil. Trimite PDF-ul la Gemini și citește doar rezultatul.

## Transcriere PDF

### Pas 1: Salvează PDF-ul

Salvează fișierul primit de la Claudia în repo cu denumirea corectă (vezi CLAUDE.md pentru convenții):
```
YYYY-MM-DD_Tip_Detalii_(Sursa).pdf
```

Dacă nu știi sursa sau data, întreab-o pe Claudia.

### Pas 2: Trimite la Gemini

```bash
curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg pdf_b64 "$(base64 -w0 /home/node/dosar-maghieru/path/to/file.pdf)" \
    '{
      "contents": [{
        "parts": [
          {
            "inline_data": {
              "mime_type": "application/pdf",
              "data": $pdf_b64
            }
          },
          {
            "text": "Transcrie acest document PDF în format Markdown. Păstrează structura originală. Marchează paginile cu **— PAGINA N —**. Notează textul greu lizibil cu [greu lizibil]. Notează ștampilele cu [Ștampilă: DESCRIERE]. Notează semnăturile cu [Semnătură: NUME]. Păstrează tot textul original, inclusiv date, numere, nume. Nu omite nimic. Nu traduce — păstrează limba originală."
          }
        ]
      }]
    }'
  )"
```

### Pas 3: Salvează rezultatul

Extrage textul din răspunsul JSON și salvează-l ca `.md` lângă PDF:
```bash
# Extrage textul din răspuns (câmpul candidates[0].content.parts[0].text)
# Salvează ca: path/to/file.md (același nume, extensie diferită)
```

Dacă fișierul e în `04-Documente-Suport/` și e relevant pentru mai multe dosare, adaugă frontmatter:
```yaml
---
dosare:
  - partaj
  - apel
---
```

### Pas 4: Citește transcrierea

Acum poți citi fișierul `.md` rezultat. Extrage faptele noi și propune actualizări.

### Erori

Dacă Gemini returnează eroare (document prea mare, format invalid, etc.), spune-i Claudiei natural că Christian trebuie să se ocupe de acest document specific. Nu intra în detalii tehnice.

## Cercetare juridică aprofundată (Deep Research)

Când o întrebare juridică necesită cercetare din mai multe perspective:

### Formulează promptul

```bash
curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [{
      "parts": [{
        "text": "<ÎNTREBAREA JURIDICĂ AICI>\n\nContext: Drept civil românesc, caz de partaj imobiliar.\n\nIMPORTANT: Pentru fiecare afirmație juridică, furnizează:\n1. Link EXCLUSIV de pe legislatie.just.ro (format: https://legislatie.just.ro/Public/DetaliiDocument/{ID})\n2. Textul EXACT, mot-à-mot, din acel articol/alineat\n3. NU folosi link-uri de pe legeaz.net, codulcivil.ro, lege5.ro sau alte site-uri terțe\n4. Dacă nu găsești pe legislatie.just.ro, spune explicit \"nu am găsit link oficial\""
      }]
    }]
  }'
```

### Verifică rezultatele

Înainte de a partaja cu Claudia sau de a actualiza LEGE.md:
1. Verifică domeniul — DOAR legislatie.just.ro
2. Folosește `web_fetch` pentru a confirma că textul citat există la link-ul dat
3. Marchează statusul: ✅ verificat, ⚠️ aproximativ, ❌ invalid, 🔍 neverificat

### Partajează cu Claudia

Prezintă rezultatele natural, cu link-uri. Include rezultatele în PR-ul pentru revizuirea lui Christian.

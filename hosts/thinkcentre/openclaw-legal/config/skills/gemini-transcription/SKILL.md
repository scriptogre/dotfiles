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
curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=$GEMINI_API_KEY" \
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
            "text": "Transcrie acest document PDF în format Markdown. Păstrează structura originală. Marchează paginile cu **— PAGINA N —**. Notează ștampilele cu [Ștampilă: DESCRIERE]. Notează semnăturile cu [Semnătură: NUME]. Păstrează tot textul original, inclusiv date, numere, nume. Nu omite nimic. Nu traduce — păstrează limba originală. FOARTE IMPORTANT: Dacă un cuvânt sau fragment NU se poate citi clar, scrie [greu lizibil] în loc. NU inventa sau ghici cuvinte — e mai bine să marchezi [greu lizibil] decât să scrii un cuvânt greșit. Acuratețea e critică: acest text va fi folosit ca probă juridică."
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

**OBLIGATORIU:** Toate transcrierile Gemini trebuie să aibă frontmatter cu `verificat: false`. Acesta indică faptul că transcrierea nu a fost verificată manual de un om.

Dacă fișierul e în `04-Documente-Suport/` și e relevant pentru mai multe dosare:
```yaml
---
verificat: false
nota: "Transcriere Gemini — de verificat manual cu PDF-ul original"
dosare:
  - partaj
  - apel
---
```

Dacă fișierul e într-un folder specific (`01-Partaj/`, `02-Apel/`, `03-Penal/`):
```yaml
---
verificat: false
nota: "Transcriere Gemini — de verificat manual cu PDF-ul original"
---
```

**NU omite niciodată frontmatter-ul `verificat: false`.** Christian va verifica manual transcrierile și va schimba la `verificat: true` după verificare.

### Pas 4: Citește transcrierea

Acum poți citi fișierul `.md` rezultat. Extrage faptele noi și propune actualizări.

### Erori

Dacă Gemini returnează eroare (document prea mare, format invalid, etc.), spune-i Claudiei natural că Christian trebuie să se ocupe de acest document specific. Nu intra în detalii tehnice.

## Cercetare juridică aprofundată (Deep Research)

Când o întrebare juridică necesită cercetare din mai multe perspective:

### Formulează promptul

```bash
curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=$GEMINI_API_KEY" \
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

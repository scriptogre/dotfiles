# HEARTBEAT — Verificări periodice

La fiecare heartbeat:

1. `cd /home/node/dosar-maghieru && git checkout main && git pull` — sincronizează repo-ul
2. Verifică dacă sunt branch-uri locale cu modificări nepush-uite
3. Verifică dacă USER.md sau MEMORY.md au informații de actualizat

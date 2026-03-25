Kurzbeschreibung
---------------
Dieses Verzeichnis enthält Hilfs-Skripte für das Copilot-Onboarding und lokale Entwicklung.

Wichtigstes Skript
------------------
- `import_memories.py` — Erzeugt lokal aus `copilot/memories/` die Dateien:
  - `.copilot_local/prompts/` (generated prompt-Dateien)
  - `.copilot_local/instructions/` (generated instruction-Dateien)

Wie ausführen
--------------
- Unter Windows (venv aktiviert):
  .venv\Scripts\python.exe copilot\scripts\import_memories.py
- Unter Unix/macOS (wenn verfügbar):
  ./copilot/scripts/import_memories.sh

Was das Skript macht
---------------------
- Liest `copilot/memories/*.md` und schreibt lokale Kopien nach `.copilot_local/`.
- Sorgt dafür, dass `/.test/` existiert und fügt `/.test/` sowie `/.copilot_local/` in die Root-`.gitignore` ein (falls noch nicht vorhanden).
- Die erzeugten Dateien sind lokal und werden standardmäßig nicht committet.

Hinweise
-------
- `.copilot_local/` ist nicht die „Quelle der Wahrheit“ — die Originaldateien bleiben in `copilot/memories/`.
- Wenn du die generierten Dateien neu erstellen willst, führe das Import-Skript erneut aus.
- Es gibt ein PowerShell-Skript `create_junction.ps1`, das lokal eine Junction `.github/prompts` → `copilot/prompts` erstellt. Verwende das nur, wenn du die lokale Verknüpfung haben möchtest.

Fehlerbehebung
---------------
- Führe das Skript vom Repository-Root aus und aktiviere ggf. das virtuelle Environment.
- Bei Pfadfehlern prüfe, ob `REPO_ROOT` korrekt ist und ob Schreibrechte bestehen.

Kontakt
-------
Bei Fragen: nutze den Issue-Workflow oder frag hier im Chat.

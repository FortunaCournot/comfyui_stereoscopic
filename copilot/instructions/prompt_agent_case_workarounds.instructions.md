---
description: "Repository instruction imported from copilot/memories/prompt_agent_case_workarounds.md"
applyTo: "**/*"
---

Prompt‑Agent — Groß-/Kleinschreibung (Workaround)

Kurz: Beim Anlegen oder Editieren von Prompt‑Dateien mit einem `agent`‑Feld, das den Agenten‑Typ "Plan" angeben soll, schreibt der Agent fälschlich `plan` (kleingeschrieben). Das führt dazu, dass der Prompt nicht wie erwartet als Typ `Plan` erkannt wird.

Konsequenz:
- Prompts mit `agent: "plan"` werden nicht korrekt als `Plan`-Agenten behandelt.

Workaround / Vorgehen:
- Beim Erstellen oder Bearbeiten von Prompts im Repo manuell prüfen und sicherstellen, dass das Agent‑Feld exakt `Plan` (mit großem P) enthält, also z.B.: `agent: "Plan"`.
- Falls ein Prompt bereits `plan` enthält, bitte korrigieren und committen.

Hinweis:
- Die canonical, repository‑sichtbare Kopie dieser Notiz ist `copilot/memories/prompt_agent_case_workarounds.md` (committet im Repo). Vermeide globale, nicht‑versionierte Kopien für repository‑scoped memories — siehe die Policy in `copilot/memories/repo_rules.md`.

Ort: `copilot/memories/prompt_agent_case_workarounds.md`

Datum: 2026-03-25
Autor: automatisch angelegt auf Nutzeranfrage

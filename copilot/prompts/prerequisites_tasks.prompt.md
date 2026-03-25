---
name: "prerequisites_tasks"
description: "Imported from copilot/memories/prerequisites_tasks.md"
agent: "agent"
---

- In api/prerequisites.sh, task JSONs are stored in Bash arrays; iterating with $array only processes the first element. Use "${array[@]}" for task folder preparation and derived task directory loops.

#!/usr/bin/env python3
import re
from pathlib import Path
SCRIPTS_DIR=Path(__file__).resolve().parent
COPILOT_DIR=SCRIPTS_DIR.parent
REPO_ROOT=COPILOT_DIR.parent

# Local generated output (not tracked)
LOCAL_DIR=REPO_ROOT/".copilot_local"
MEM_DIR=COPILOT_DIR/"memories"
PROMPTS_DIR=LOCAL_DIR/"prompts"
INSTR_DIR=LOCAL_DIR/"instructions"
LOCAL_DIR.mkdir(parents=True, exist_ok=True)
PROMPTS_DIR.mkdir(parents=True, exist_ok=True)
INSTR_DIR.mkdir(parents=True, exist_ok=True)
print(f"Import source: {MEM_DIR.relative_to(COPILOT_DIR)} -> local targets: {PROMPTS_DIR.relative_to(REPO_ROOT)}, {INSTR_DIR.relative_to(REPO_ROOT)}")
KW=re.compile(r'preference|policy|instruction|style|rule', re.I)
for f in sorted(MEM_DIR.glob('*.md')):
    base=f.name
    name_no_ext=f.stem
    text=f.read_text(encoding='utf-8')
    if KW.search(text):
        out=INSTR_DIR/f"{name_no_ext}.instructions.md"
        out.write_text('---\ndescription: "Repository instruction imported from copilot/memories/{}"\napplyTo: "**/*"\n---\n\n{}'.format(base, text), encoding='utf-8')
        try:
            rel = out.relative_to(REPO_ROOT)
        except Exception:
            rel = out
        print(f"Imported {base} -> {rel}")
    else:
        out=PROMPTS_DIR/f"{name_no_ext}.prompt.md"
        out.write_text('---\nname: "{}"\ndescription: "Imported from copilot/memories/{}"\nagent: "agent"\n---\n\n{}'.format(name_no_ext, base, text), encoding='utf-8')
        try:
            rel = out.relative_to(REPO_ROOT)
        except Exception:
            rel = out
        print(f"Imported {base} -> {rel}")
# Ensure .test/ exists (at repo root) and that the root .gitignore contains it
TEST_DIR=REPO_ROOT/".test"
GITIGNORE=REPO_ROOT/".gitignore"
TEST_DIR.mkdir(parents=True, exist_ok=True)
if GITIGNORE.exists():
    gi=GITIGNORE.read_text(encoding='utf-8')
    if '.test/' not in gi.splitlines():
        with GITIGNORE.open('a', encoding='utf-8') as fh:
            fh.write('\n.test/\n')
        print('Appended .test/ to root .gitignore')
    else:
        print('.test/ already in root .gitignore')
else:
    GITIGNORE.write_text('.test/\n', encoding='utf-8')
    print('Created root .gitignore and added .test/')

# Ensure local output dir is ignored in root .gitignore
if GITIGNORE.exists():
    gi=GITIGNORE.read_text(encoding='utf-8')
    if '.copilot_local/' not in gi.splitlines():
        with GITIGNORE.open('a', encoding='utf-8') as fh:
            fh.write('\n.copilot_local/\n')
        print('Appended .copilot_local/ to root .gitignore')
    else:
        print('.copilot_local/ already in root .gitignore')
else:
    GITIGNORE.write_text('.copilot_local/\n', encoding='utf-8')
    print('Created root .gitignore and added .copilot_local/')

print(f"Import complete. Review generated files under {PROMPTS_DIR.relative_to(REPO_ROOT)} and {INSTR_DIR.relative_to(REPO_ROOT)}")

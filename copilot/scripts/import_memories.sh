#!/bin/sh
# Automatic import script: convert copilot/memories/*.md into prompts or instructions
# Use the repository `copilot/` location for canonical prompts, instructions and memories
set -eu
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# Use canonical copilot/ location
MEM_DIR="$ROOT_DIR/copilot/memories"
PROMPTS_DIR="$ROOT_DIR/copilot/prompts"
INSTR_DIR="$ROOT_DIR/copilot/instructions"

echo "Import source: ${MEM_DIR#$ROOT_DIR/} -> targets: ${PROMPTS_DIR#$ROOT_DIR/}, ${INSTR_DIR#$ROOT_DIR/}"

mkdir -p "$PROMPTS_DIR" "$INSTR_DIR"

for f in "$MEM_DIR"/*.md; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    name_no_ext=${base%.md}
    # Heuristic: files mentioning "preference", "policy", "instruction", "style" -> instructions
    if grep -qiE 'preference|policy|instruction|style|rule' "$f"; then
        out="$INSTR_DIR/${name_no_ext}.instructions.md"
        cat > "$out" <<EOF
    ---
    description: "Repository instruction imported from copilot/memories/${base}"
    applyTo: "**/*"
    ---

    $(cat "$f")
    EOF
        echo "Imported $base -> ${out#$ROOT_DIR/}"
    else
        out="$PROMPTS_DIR/${name_no_ext}.prompt.md"
        cat > "$out" <<EOF
    ---
    name: "${name_no_ext}"
    description: "Imported from copilot/memories/${base}"
    agent: "agent"
    ---

    $(cat "$f")
    EOF
        echo "Imported $base -> ${out#$ROOT_DIR/}"
    fi
done

# Ensure .test/ exists and is in .gitignore
TEST_DIR="$ROOT_DIR/.test"
GITIGNORE="$ROOT_DIR/.gitignore"
mkdir -p "$TEST_DIR"
case "$(grep -Fx ".test/" "$GITIGNORE" 2>/dev/null || true)" in
    "") echo ".test/" >> "$GITIGNORE" && echo "Appended .test/ to .gitignore" || true ;;
    *) echo ".test/ already in .gitignore" ;;
esac

echo "Import complete. Review generated files under ${PROMPTS_DIR#$ROOT_DIR/} and ${INSTR_DIR#$ROOT_DIR/}"

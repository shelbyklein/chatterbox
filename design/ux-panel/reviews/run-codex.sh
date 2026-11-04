#!/bin/zsh
# Runs one OpenAI judge through Codex: rubric + index as the prompt, every screenshot attached.
model=$1
cd "$(dirname "$0")/.."
imgs=()
for f in screens/*.png; do imgs+=(-i "$f"); done
{ cat RUBRIC.md; echo; echo "---"; echo "# screens/INDEX.md"; cat screens/INDEX.md
  echo; echo "The screenshots are attached in filename order (01 … 28). Judge from them and the index only; don't read any other files."; } \
| codex exec --skip-git-repo-check -s read-only -m "$model" -c model_reasoning_effort=high \
    -o "reviews/$model.md" "${imgs[@]}" - > "reviews/$model.log" 2>&1
echo "$model exit $?"

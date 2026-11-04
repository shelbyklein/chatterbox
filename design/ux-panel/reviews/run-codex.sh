#!/bin/zsh
# Runs one OpenAI judge through Codex: rubric + index as the prompt, every screenshot attached.
# Usage: run-codex.sh MODEL [SCREENS_DIR (default screens)] [OUT_DIR (default reviews)]
model=$1; screens=${2:-screens}; out=${3:-reviews}
cd "$(dirname "$0")/.."
mkdir -p "$out"
imgs=()
for f in $screens/*.png; do imgs+=(-i "$f"); done
{ sed "s|screens/|$screens/|g" RUBRIC.md; echo; echo "---"; echo "# $screens/INDEX.md"; cat "$screens/INDEX.md"
  echo; echo "The screenshots are attached in filename order. Judge from them and the index only; don't read any other files."; } \
| codex exec --skip-git-repo-check -s read-only -m "$model" -c model_reasoning_effort=high \
    -o "$out/$model.md" "${imgs[@]}" - > "$out/$model.log" 2>&1
echo "$model exit $?"

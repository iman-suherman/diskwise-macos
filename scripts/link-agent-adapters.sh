#!/usr/bin/env bash
# Recreate thin adapters so Cursor / Copilot stay linked to canonical sources.
# Canonical: prompts/, .agents/skills/, AGENTS.md, knowledge/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p .agents/skills .github/prompts

# Cursor skills → .agents/skills
rm -rf .cursor/skills
mkdir -p .cursor/skills
shopt -s nullglob
for d in .agents/skills/*/; do
  name="$(basename "$d")"
  ln -sfn "../../.agents/skills/$name" ".cursor/skills/$name"
done

# Copilot prompts → prompts/
mkdir -p .github/prompts
shopt -s nullglob
for old in .github/prompts/*; do
  rm -f "$old"
done
for f in prompts/*.md; do
  base="$(basename "$f")"
  [ "$base" = "README.md" ] && continue
  ln -sfn "../../prompts/$base" ".github/prompts/$base"
done

echo "Linked Cursor skills → .agents/skills"
echo "Linked Copilot prompts → prompts/"
ls -la .cursor/skills | sed -n '1,40p'
ls -la .github/prompts | sed -n '1,40p'

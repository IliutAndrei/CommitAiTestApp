#!/usr/bin/env sh
set -eu

# ---------------------------------------------
# Local AI commit message generator (Ollama)
# - Uses staged diff (git diff --cached)
# - Adds light repository context (few key files)
# - Produces Conventional Commits header + bullet body
# - Hard-sanitizes output to avoid extra commentary
# ---------------------------------------------

# Default model (recommended for speed/quality on laptops)
MODEL="${MODEL:-llama3:8b}"

# 1) Staged diff (only what will be committed)
DIFF="$(git diff --cached --unified=2)"

# If nothing staged, return a safe fallback
if [ -z "${DIFF:-}" ]; then
  printf "%s\n\n- update files\n" "chore: update"
  exit 0
fi

# Limit diff size to keep prompts small and fast
DIFF_TRIMMED="$(printf "%s" "$DIFF" | head -c 14000)"

# 2) Add small repo context (keep it tiny for performance)
CTX=""
add_if_exists () {
  FILE="$1"
  MAX_BYTES="${2:-2000}"
  if [ -f "$FILE" ]; then
    CTX="$CTX\n\n### FILE: $FILE\n$(cat "$FILE" | head -c "$MAX_BYTES")"
  fi
}

add_if_exists "README.md" 2000
add_if_exists "global.json" 1000
add_if_exists "Directory.Build.props" 2000
add_if_exists "package.json" 2000
add_if_exists "angular.json" 2000

# Add up to 1 csproj for .NET context hints (keep fast)
for f in $(git ls-files "*.csproj" | head -n 1); do
  add_if_exists "$f" 2000
done

# 3) Prompt: strict format, no extra text
PROMPT=$(cat <<'EOF'
Generate a git commit message in Conventional Commits format.

Return ONLY this structure (nothing else):
1) First line: type(scope): short description
2) Blank line
3) 3-7 bullet points starting with "- " describing changes based ONLY on the staged diff

Rules:
- types: feat, fix, refactor, perf, test, docs, chore, build, ci
- scope: a short area (api, ui, core, infra, deps, auth, data, tests, build, etc.)
- header max 72 chars, imperative mood, no period
- bullets must be specific and derived (no generic fluff)
- do NOT add explanations, notes, or confirmations
EOF
)

INPUT="$(printf "%s\n\n### CONTEXT (partial)\n%s\n\n### STAGED DIFF\n%s\n" "$PROMPT" "$CTX" "$DIFF_TRIMMED")"

# 4) Call local model
OUT_RAW="$(printf "%s" "$INPUT" | ollama run "$MODEL" | tr -d '\r')"

# 5) Remove common "assistant chatter" prefixes if present
# Keep from the first line that looks like a Conventional Commit header: "type(scope): "
OUT_CUT="$(printf "%s\n" "$OUT_RAW" | sed -n '/^[a-z]\+\(([^)]\+)\)\?: /,$p')"

# 6) HARD sanitize output: keep ONLY header + blank line + "- " bullets
# This guarantees no trailing commentary like "Note that I followed the rules..."
HEADER="$(printf "%s\n" "$OUT_CUT" | head -n 1)"
BULLETS="$(printf "%s\n" "$OUT_CUT" | grep -E '^- ' | head -n 7)"

# If no bullets, create a minimal one
if [ -z "${BULLETS:-}" ]; then
  BULLETS="- update files"
fi

# Final output
printf "%s\n\n%s\n" "$HEADER" "$BULLETS"

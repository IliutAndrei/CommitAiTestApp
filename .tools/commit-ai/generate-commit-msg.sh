#!/usr/bin/env sh
set -eu

# ---------------------------------------------
# Local AI commit message generator (Ollama)
# - Uses staged diff (git diff --cached)
# - Adds light repository context (few key files)
# - Produces Conventional Commit header + body
# ---------------------------------------------

# Default model (recommended for speed/quality on laptops)
MODEL="${MODEL:-llama3:8b}"

# 1) Get staged diff (only what will be committed)
DIFF="$(git diff --cached --unified=2)"

# If there is nothing staged, return a safe message
if [ -z "${DIFF:-}" ]; then
  printf "%s\n\n- update files\n" "chore: update"
  exit 0
fi

# Limit diff size to avoid huge prompts (tune as needed)
DIFF_TRIMMED="$(printf "%s" "$DIFF" | head -c 18000)"

# 2) Collect a small amount of repo context (avoid dumping the whole repo)
CTX=""
add_if_exists () {
  FILE="$1"
  MAX_BYTES="${2:-4000}"
  if [ -f "$FILE" ]; then
    CTX="$CTX\n\n### FILE: $FILE\n$(cat "$FILE" | head -c "$MAX_BYTES")"
  fi
}

# Common context files (adjust based on your repo)
add_if_exists "README.md" 4000
add_if_exists "global.json" 2000
add_if_exists "Directory.Build.props" 4000
add_if_exists "Directory.Build.targets" 4000
add_if_exists "package.json" 3000
add_if_exists "angular.json" 3000

# Add up to 2 .csproj files for .NET context hints
for f in $(git ls-files "*.csproj" | head -n 2); do
  add_if_exists "$f" 4000
done

# 3) Prompt: Conventional Commits header + bullet body
PROMPT=$(cat <<'EOF'
You are a senior engineer. Generate a git commit message in Conventional Commits format.

OUTPUT FORMAT (exactly):
1) First line: type(scope): short description
2) Blank line
3) Body: 3-7 bullet points starting with "- " describing what changed (based ONLY on the staged diff)

Rules for first line:
- types: feat, fix, refactor, perf, test, docs, chore, build, ci
- scope: choose a short scope based on the change (api, ui, core, infra, deps, auth, data, tests, build, etc.)
- max 72 chars
- imperative mood, no period
- must reflect what the staged diff actually changes

Rules for body:
- bullet points must be specific, concrete, and derived from the staged diff
- do not include generic bullets like "update code" unless absolutely unavoidable
- keep bullets short (ideally < 100 chars each)
- do not include code blocks
Return ONLY the commit message (no extra commentary).
EOF
)

# 4) Build input and call local Ollama model
INPUT="$(printf "%s\n\n### CONTEXT (partial)\n%s\n\n### STAGED DIFF\n%s\n" "$PROMPT" "$CTX" "$DIFF_TRIMMED")"

OUT_RAW="$(printf "%s" "$INPUT" | ollama run "$MODEL" | tr -d '\r')"

# 5) Minimal cleanup to keep it safe and consistent:
# - ensure we keep only the first "paragraph" structure (header + blank + bullets)
# - strip leading/trailing whitespace lines
OUT="$(printf "%s" "$OUT_RAW" \
  | sed '/^[[:space:]]*$/N;/^\n$/D' \
  | sed 's/[[:space:]]*$//' \
  | awk 'NF{p=1} p{print}' \
)"

# Fallback if model output is empty
if [ -z "${OUT:-}" ]; then
  OUT="chore: update\n\n- update files"
fi

# If model forgot body, add a minimal one
# (checks if there is at least one bullet line)
if ! printf "%s\n" "$OUT" | grep -q '^- '; then
  OUT="$(printf "%s\n\n- update files\n" "$(printf "%s" "$OUT" | head -n 1)")"
fi

printf "%s\n" "$OUT"

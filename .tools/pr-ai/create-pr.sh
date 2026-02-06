#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# PR Generator (GitHub only)
# Uses local Ollama to generate a corporate PR title + description,
# then creates the PR via GitHub CLI (gh).
# ============================================================

# ----------------------------
# Configuration (override via env vars)
# ----------------------------
BASE_BRANCH="${BASE_BRANCH:-main}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5:7b}"
MAX_COMMITS="${MAX_COMMITS:-50}"
MAX_FILES="${MAX_FILES:-60}"

# ----------------------------
# Helpers
# ----------------------------
die() {
  echo "Error: $*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# ----------------------------
# Preconditions
# ----------------------------
command_exists git    || die "git is required but not found in PATH."
command_exists ollama || die "ollama is required but not found in PATH."
command_exists gh     || die "GitHub CLI (gh) is required but not found in PATH."

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "This command must be run inside a git repository."

CURRENT_BRANCH="$(git branch --show-current)"
[ -n "${CURRENT_BRANCH}" ] || die "Unable to determine the current branch."

if [ "${CURRENT_BRANCH}" = "${BASE_BRANCH}" ]; then
  die "You are currently on '${BASE_BRANCH}'. Please create/switch to a feature branch before opening a PR."
fi

# ----------------------------
# Gather git context
# ----------------------------
git fetch origin "${BASE_BRANCH}" >/dev/null 2>&1 || true
BASE_REF="origin/${BASE_BRANCH}"

git rev-parse --verify "${BASE_REF}" >/dev/null 2>&1 \
  || die "Base branch '${BASE_REF}' not found. Verify BASE_BRANCH or remote configuration."

COMMITS="$(git log --max-count="${MAX_COMMITS}" --pretty=format:"- %s (%h)" "${BASE_REF}..HEAD" || true)"
[ -n "${COMMITS}" ] || die "No commits found between ${BASE_REF} and HEAD."

FILES="$(git diff --name-only "${BASE_REF}..HEAD" | head -n "${MAX_FILES}" || true)"

# ----------------------------
# Build AI prompt
# ----------------------------
read -r -d '' PROMPT <<EOF || true
You are a senior software engineer writing a corporate pull request.

Generate a Pull Request title and description in Markdown based strictly on the inputs below.

Output requirements:
- Output MUST be valid JSON only (no extra text)
- Keys: "title", "body"
- Title: concise, professional, ideally Conventional Commits style (e.g., "feat(scope): ...", "fix(scope): ...")
- Body: Markdown with sections in this exact order:
  1) Summary (2–4 bullet points)
  2) Changes (bullets; group by area if possible)
  3) Testing (what was done and/or how to validate)
  4) Notes (optional; only if relevant, e.g., breaking changes, rollout considerations)
- Do not invent features, files, tests, or results.

Repo context:
- Base branch: ${BASE_BRANCH}
- Source branch: ${CURRENT_BRANCH}

Commits (most recent up to ${MAX_COMMITS}):
${COMMITS}

Changed files (up to ${MAX_FILES}):
${FILES}
EOF

# ----------------------------
# Call Ollama
# ----------------------------
RAW_OUTPUT="$(ollama run "${OLLAMA_MODEL}" "${PROMPT}")" \
  || die "Ollama execution failed."

# ----------------------------
# Extract JSON (best-effort)
# ----------------------------
JSON_OUTPUT="$(printf "%s" "${RAW_OUTPUT}" | awk '
  BEGIN { in_json=0 }
  /{/ { if (!in_json) in_json=1 }
  { if (in_json) print }
  /}/ { if (in_json) exit }
')"

TITLE=""
BODY=""

if command_exists python; then
  TITLE="$(python - <<'PY'
import json, sys
s = sys.stdin.read().strip()
try:
    obj = json.loads(s)
    print((obj.get("title") or "").replace("\n"," ").strip())
except Exception:
    print("")
PY
<<< "${JSON_OUTPUT}")"

  BODY="$(python - <<'PY'
import json, sys
s = sys.stdin.read().strip()
try:
    obj = json.loads(s)
    print((obj.get("body") or "").strip())
except Exception:
    print("")
PY
<<< "${JSON_OUTPUT}")"
fi

# Fallback if JSON parsing failed (keep behavior safe and predictable)
if [ -z "${TITLE}" ] || [ -z "${BODY}" ]; then
  TITLE="$(printf "%s" "${RAW_OUTPUT}" | head -n 1 | sed 's/^#\+ *//')"
  BODY="$(printf "%s" "${RAW_OUTPUT}" | tail -n +2)"
fi

[ -n "${TITLE}" ] || TITLE="chore: update"
[ -n "${BODY}" ]  || BODY=""

# ----------------------------
# Preview
# ----------------------------
echo "============================================================"
echo "Pull Request Preview"
echo "Base branch   : ${BASE_BRANCH}"
echo "Source branch : ${CURRENT_BRANCH}"
echo
echo "Title:"
echo "${TITLE}"
echo
echo "Description:"
echo "${BODY}"
echo "============================================================"

# ----------------------------
# Create PR (GitHub)
# ----------------------------
gh pr create \
  --base "${BASE_BRANCH}" \
  --head "${CURRENT_BRANCH}" \
  --title "${TITLE}" \
  --body "${BODY}"

#!/bin/bash
# PostToolUse(Write|Edit): when Claude writes what looks like a plaintext secret *value*
# into a file, nudge it to migrate to fnox via the env-to-fnox skill instead of committing
# the value. Advisory only — emits additionalContext and always exits 0, never blocks.
#
# This fires at write time, before `gitleaks` would catch it at commit time, and points at
# the migration path rather than just flagging. Detection is deliberately conservative
# (named KEY/SECRET/TOKEN/PASSWORD assignments to a real literal, private-key headers, AWS
# key ids) to limit noise; env-var references and obvious placeholders are ignored.
#
# Fires at most once per session (marker under ${TMPDIR}).
# Opt out per repo/user with DEV_HOOKS_SECRETS=false (in .claude settings "env").

case "${DEV_HOOKS_SECRETS:-}" in
  false | 0 | no | off) exit 0 ;;
esac

INPUT=$(cat 2>/dev/null)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // "nosession"' 2>/dev/null)
CONTENT=$(printf '%s' "$INPUT" | jq -r '(.tool_input.content // "") + "\n" + (.tool_input.new_string // "")' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0

BASE=$(basename "$FILE")

# Skip example/template files and the reference files meant to be committed.
case "$BASE" in
  *.example | *.sample | *.template | *.dist | fnox.toml) exit 0 ;;
  *.lock | *.lockb | package-lock.json | pnpm-lock.yaml) exit 0 ;;
esac

CONTENT_FILE=$(mktemp)
trap 'rm -f "$CONTENT_FILE"' EXIT
printf '%s' "$CONTENT" >"$CONTENT_FILE"

FOUND=$(
  python3 - "$CONTENT_FILE" <<'PYEOF'
import re
import sys

with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    content = fh.read()

# Private-key blocks and AWS access-key ids are secrets on their own.
if re.search(r"-----BEGIN [A-Z ]*PRIVATE KEY-----", content):
    print("1")
    sys.exit(0)
if re.search(r"\bAKIA[0-9A-Z]{16}\b", content):
    print("1")
    sys.exit(0)

# NAME = "value" / NAME: "value" where NAME looks secret-ish.
kv = re.compile(
    r"(?i)\b(?:api[_-]?key|secret|token|password|passwd|access[_-]?key"
    r"|private[_-]?key|client[_-]?secret|bws[_-]?access[_-]?token)\b"
    r"\s*[:=]\s*[\"']?([^\s\"']{6,})"
)
# Values that are clearly NOT a real secret (env refs / placeholders).
not_secret = re.compile(
    r"(?i)^\$|\$\{|process\.env|os\.environ|os\.getenv|ENV\[|<[^>]+>"
    r"|\b(?:changeme|change_me|your[-_]|xxx+|example|replace|redacted"
    r"|placeholder|dummy|none|null|todo|fixme)\b"
)

for m in kv.finditer(content):
    val = m.group(1)
    if not_secret.search(val):
        continue
    print("1")
    sys.exit(0)
PYEOF
)

[ -z "$FOUND" ] && exit 0

# Fire at most once per session.
MARKER_DIR="${TMPDIR:-/tmp}/dev-hooks-secrets"
mkdir -p "$MARKER_DIR" 2>/dev/null
MARKER="$MARKER_DIR/${SESSION}"
[ -e "$MARKER" ] && exit 0
: >"$MARKER" 2>/dev/null

MSG="You just wrote what looks like a plaintext secret value into $BASE. Don't commit secret *values*. Migrate this to fnox via the \`env-to-fnox\` skill: store only a *reference* (key name) in a committed \`fnox.toml\` and resolve the real value from the vault (Bitwarden Secrets Manager by default) at run time. Keep \`.env\`/\`.env.local\` gitignored. If this is genuinely not a secret (a placeholder, public value, or test fixture), ignore this."

jq -cn --arg msg "$MSG" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
exit 0

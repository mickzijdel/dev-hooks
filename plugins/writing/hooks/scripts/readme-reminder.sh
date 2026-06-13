#!/bin/bash
# PostToolUse(Write|Edit|MultiEdit): when Claude writes a README, audit it with this
# plugin's github_readme_audit.py (the github-readme skill's checker) and report the
# findings back to Claude, plus a nudge to use the `writing:github-readme` skill.
# Advisory only — emits additionalContext and always exits 0, never blocks the write.
#
# - audit script + python3 available (the script ships in this plugin, so normally
#   always): run it on the file EVERY time and report the results.
# - audit unavailable (override pointing elsewhere, no python3): fall back to the
#   skill nudge alone, once per session per file.
#
# Deliberately self-contained: the writing plugin installs without dev-hooks, so this
# script cannot source dev-hooks' lib/reminder-common.sh.
#
# Opt out per repo/user with WRITING_README=false (in .claude settings "env").
# WRITING_README_AUDIT_SCRIPT overrides the audit script path (mainly for tests).

case "${WRITING_README:-}" in
  false | 0 | no | off) exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || exit 0

PAYLOAD=$(cat 2>/dev/null)
FILE=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
BASE=${FILE##*/}

# Match READMEs by basename, case-insensitively: README, README.md, Readme.rst, readme.txt.
case "${BASE,,}" in
  readme | readme.*) ;;
  *) exit 0 ;;
esac

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Advisory PostToolUse additionalContext, then exit 0 — never blocks the write.
emit() {
  jq -cn --arg msg "$1" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
  exit 0
}

NUDGE="Use the \`writing:github-readme\` skill (Skill tool) before finalizing this README — it covers section structure, onboarding flow, examples, and contribution guidance — and re-run its audit script (skills/github-readme/scripts/github_readme_audit.py) until it passes."

# --- audit script + python3 + file on disk: audit on EVERY write and report -------------
AUDIT="${WRITING_README_AUDIT_SCRIPT:-$SELF_DIR/../../skills/github-readme/scripts/github_readme_audit.py}"
if [ -f "$AUDIT" ] && command -v python3 >/dev/null 2>&1 && [ -f "$FILE" ]; then
  if OUT=$(python3 "$AUDIT" "$FILE" 2>&1); then
    emit "README audit passed on $BASE (review any WARN lines):"$'\n'"$OUT"$'\n\n'"$NUDGE"
  else
    emit "README audit found failures in $BASE — fix before finalizing:"$'\n'"$OUT"$'\n\n'"$NUDGE"
  fi
fi

# --- audit unavailable: fall back to a once-per-session-per-file skill reminder ---------
SESSION=$(printf '%s' "$PAYLOAD" | jq -r '.session_id // "nosession"' 2>/dev/null)
MARKER_DIR="${TMPDIR:-/tmp}/writing-readme-reminder"
mkdir -p "$MARKER_DIR" 2>/dev/null
MARKER="$MARKER_DIR/${SESSION:-nosession}-$(printf '%s' "$FILE" | tr -c 'A-Za-z0-9._-' _)"
[ -e "$MARKER" ] && exit 0
: >"$MARKER" 2>/dev/null

emit "You just wrote $BASE. $NUDGE"

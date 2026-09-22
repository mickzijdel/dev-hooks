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
# Shares this plugin's lib/voice-common.sh (payload read, opt-out, once-per-session marker,
# emit + fire telemetry). Still never sources dev-hooks' lib: the writing plugin installs
# without dev-hooks.
#
# Opt out per repo/user with WRITING_README=false (in .claude settings "env").
# WRITING_README_AUDIT_SCRIPT overrides the audit script path (mainly for tests).

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/voice-common.sh
source "$SELF_DIR/lib/voice-common.sh"

voice_opt_out WRITING_README
voice_payload

FILE=$(voice_field '.tool_input.file_path')
[ -z "$FILE" ] && exit 0
BASE=${FILE##*/}

# Match READMEs by basename, case-insensitively: README, README.md, Readme.rst, readme.txt.
case "${BASE,,}" in
  readme | readme.*) ;;
  *) exit 0 ;;
esac

# After the basename gate (this hook runs on every write, so a non-README shouldn't pay a
# jq spawn) but before any emit: SESSION is what makes a fire attributable to a repo, and
# the audit path below emits without reaching the once-per-session block that used to set it.
SESSION=$(voice_field '.session_id')

NUDGE="Use the \`writing:github-readme\` skill (Skill tool) before finalizing this README — it covers section structure, onboarding flow, examples, and contribution guidance — and re-run its audit script (skills/github-readme/scripts/github_readme_audit.py) until it passes."

# --- audit script + python3 + file on disk: audit on EVERY write and report -------------
AUDIT="${WRITING_README_AUDIT_SCRIPT:-$SELF_DIR/../../skills/github-readme/scripts/github_readme_audit.py}"
if [ -f "$AUDIT" ] && command -v python3 >/dev/null 2>&1 && [ -f "$FILE" ]; then
  if OUT=$(python3 "$AUDIT" "$FILE" 2>&1); then
    voice_emit PostToolUse "README audit passed on $BASE (review any WARN lines):"$'\n'"$OUT"$'\n\n'"$NUDGE"
  else
    voice_emit PostToolUse "README audit found failures in $BASE — fix before finalizing:"$'\n'"$OUT"$'\n\n'"$NUDGE"
  fi
fi

# --- audit unavailable: fall back to a once-per-session-per-file skill reminder ---------
voice_fire_once readme-reminder "$(printf '%s' "$FILE" | tr -c 'A-Za-z0-9._-' _)" || exit 0

voice_emit PostToolUse "You just wrote $BASE. $NUDGE"

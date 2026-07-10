#!/bin/bash
# PostToolUse(Write|Edit|MultiEdit): when Claude writes a prose file and a voice profile is
# discoverable, scan the file for the profile's banned words with this plugin's voice_audit.py
# and nudge Claude to revise via the `writing:voice-profile` skill. Advisory only — emits
# additionalContext and always exits 0, never blocks the write.
#
# Opt-in by posture: silent unless a profile is found, so installs without a profile see nothing.
# Profile lookup (first hit wins): $WRITING_VOICE_PROFILE, <cwd>/.claude/voice_profile.md,
# ~/.claude/voice_profile.md.
#
# Deliberately self-contained: the writing plugin installs without dev-hooks, so this script
# cannot source dev-hooks' lib/reminder-common.sh.
#
# Opt out per repo/user with WRITING_VOICE=false (in .claude settings "env").
# WRITING_VOICE_AUDIT_SCRIPT overrides the audit script path (mainly for tests).

# jscpd:ignore-start — same self-contained payload preamble as readme-reminder.sh; this plugin
# installs without dev-hooks, so neither hook can share it via lib/reminder-common.sh.
case "${WRITING_VOICE:-}" in
  false | 0 | no | off) exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || exit 0

PAYLOAD=$(cat 2>/dev/null)
FILE=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
# jscpd:ignore-end

# Prose files only (incl. HTML webcopy).
case "${FILE,,}" in
  *.md | *.mdx | *.markdown | *.tex | *.txt | *.html | *.htm | *.xhtml) ;;
  *) exit 0 ;;
esac

# Resolve a voice profile; first existing candidate wins. Stay silent if none is found.
CWD=$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty' 2>/dev/null)
PROFILE=""
for cand in "${WRITING_VOICE_PROFILE:-}" "${CWD:+$CWD/.claude/voice_profile.md}" "$HOME/.claude/voice_profile.md"; do
  [ -n "$cand" ] && [ -f "$cand" ] && PROFILE="$cand" && break
done
[ -z "$PROFILE" ] && exit 0

command -v python3 >/dev/null 2>&1 || exit 0
[ -f "$FILE" ] || exit 0

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
AUDIT="${WRITING_VOICE_AUDIT_SCRIPT:-$SELF_DIR/../../skills/voice-profile/scripts/voice_audit.py}"
[ -f "$AUDIT" ] || exit 0

# voice_audit.py exits 1 when it finds banned words; only nudge then (clean prose stays silent).
STATUS=0
OUT=$(python3 "$AUDIT" --profile "$PROFILE" "$FILE" 2>/dev/null) || STATUS=$?
if [ "$STATUS" -eq 1 ]; then
  BASE=${FILE##*/}
  NUDGE="Use the \`writing:voice-profile\` skill (Skill tool) to revise $BASE to match the profile, then re-run skills/voice-profile/scripts/voice_audit.py until it is clean."
  jq -cn --arg msg "Voice check flagged banned words in $BASE (profile: $PROFILE):"$'\n'"$OUT"$'\n\n'"$NUDGE" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
fi
exit 0

#!/bin/bash
# PostToolUse(Write|Edit|MultiEdit): after Claude writes a prose file, scan it for the voice
# profile's banned words with this plugin's voice_audit.py and nudge Claude to revise via the
# `writing:voice-profile` skill. Advisory only — additionalContext, exit 0, never blocks.
#
# The reactive backstop of three: voice-prewrite-reminder.sh puts the profile in front of the
# first draft, this one catches banned words in what landed, and voice-stop-reminder.sh
# refuses to let the turn end on prose the skill never touched. Banned words are a narrow
# signal — prose can be thoroughly off-voice without tripping a single one — which is why it
# is not the only hook.
#
# Silent unless a profile is discoverable, so installs without one see nothing.
# Opt out with WRITING_VOICE=false; WRITING_VOICE_AUDIT_SCRIPT overrides the audit path.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/voice-common.sh
source "$SELF_DIR/lib/voice-common.sh"

voice_opt_out
voice_payload

FILE=$(voice_field '.tool_input.file_path')
[ -z "$FILE" ] && exit 0
voice_is_prose_file "$FILE" || exit 0
SESSION=$(voice_field '.session_id')

voice_profile # sets PROFILE, exits when none

command -v python3 >/dev/null 2>&1 || exit 0
[ -f "$FILE" ] || exit 0

AUDIT="${WRITING_VOICE_AUDIT_SCRIPT:-$SELF_DIR/../../skills/voice-profile/scripts/voice_audit.py}"
[ -f "$AUDIT" ] || exit 0

# voice_audit.py exits 1 when it finds banned words; only nudge then (clean prose stays silent).
STATUS=0
OUT=$(python3 "$AUDIT" --profile "$PROFILE" "$FILE" 2>/dev/null) || STATUS=$?
[ "$STATUS" -eq 1 ] || exit 0

BASE=${FILE##*/}
voice_emit PostToolUse "Voice check flagged banned words in $BASE (profile: $PROFILE):
$OUT

Use the \`writing:voice-profile\` skill (Skill tool) to revise $BASE to match the profile, then re-run skills/voice-profile/scripts/voice_audit.py until it is clean."

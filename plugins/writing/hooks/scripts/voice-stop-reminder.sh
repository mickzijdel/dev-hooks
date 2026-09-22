#!/bin/bash
# Stop hook: this session wrote prose files but never invoked the `writing:voice-profile`
# skill — refuse to end the turn (exit 2) and send Claude back to apply the profile.
#
# The one the voice hooks were missing. The other three are advisory: they inject context and
# Claude may or may not act on it, and nothing checks afterwards. A Stop hook is the last
# point before the user reads the draft, which is the only place a "did this actually get
# applied?" check is worth anything. This is the same shape as dev-hooks'
# compress-comments-reminder, the hook that reliably lands.
#
# "Wrote prose" and "ran the skill" both come from walking the transcript's tool_use blocks
# (voice_transcript_scan), so it works for prose outside git and never mistakes the
# skill_listing attachment — which names every installed skill — for a real invocation.
#
# Re-arms rather than firing once, bounded so a Stop loop cannot happen: it asks again when
# the session has written more prose files than at the last fire, and at most 3 times.
#
# Opt out with WRITING_VOICE=false.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/voice-common.sh
source "$SELF_DIR/lib/voice-common.sh"

voice_opt_out
voice_payload

TRANSCRIPT=$(voice_field '.transcript_path')
SESSION=$(voice_field '.session_id')
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

voice_profile # sets PROFILE, exits when none

SCAN=$(voice_transcript_scan "$TRANSCRIPT") || exit 0
COUNT=${SCAN%%	*}
RAN=${SCAN##*	}
case "$COUNT" in '' | *[!0-9]*) exit 0 ;; esac
[ "$COUNT" -gt 0 ] || exit 0
[ "$RAN" = "1" ] && exit 0

MAX_NUDGES=3
voice_state_file voice-stop nudges
NUDGES=$(cat "$REPLY" 2>/dev/null)
case "$NUDGES" in '' | *[!0-9]*) NUDGES=0 ;; esac
[ "$NUDGES" -ge "$MAX_NUDGES" ] && exit 0

# Only re-ask once more prose has been written since the last nudge — an unchanged count
# means Claude has already been told and written nothing since, so stay quiet.
voice_state_file voice-stop count
SEEN=$(cat "$REPLY" 2>/dev/null)
case "$SEEN" in '' | *[!0-9]*) SEEN=-1 ;; esac
[ "$COUNT" -le "$SEEN" ] && exit 0
printf '%s' "$COUNT" >"$REPLY" 2>/dev/null

voice_state_file voice-stop nudges
printf '%s' "$((NUDGES + 1))" >"$REPLY" 2>/dev/null

FILES="file"
[ "$COUNT" -gt 1 ] && FILES="files"
voice_emit_stop "[voice-stop-reminder] This session wrote ${COUNT} prose ${FILES} and never applied the voice profile at ${PROFILE}. Before finishing, use the \`writing:voice-profile\` skill (Skill tool): read the profile, identify the register the piece calls for, and revise what you wrote into that voice — then run skills/voice-profile/scripts/voice_audit.py over the files until it is clean. Generic AI prose is the failure mode this exists to catch."

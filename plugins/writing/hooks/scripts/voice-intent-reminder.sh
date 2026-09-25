#!/bin/bash
# UserPromptSubmit: when a voice profile is discoverable AND the prompt reads as a
# writing/copy task, nudge Claude to apply the `writing:voice-profile` skill BEFORE drafting.
# Advisory: additionalContext, exit 0.
#
# Deliberately the weakest of the voice hooks, because its trigger is a prompt regex and
# most prose work does not announce itself in the prompt that starts it ("make this section
# better" names nothing). voice-prewrite-reminder.sh covers what this misses by keying on
# the file about to be written instead of the words used to ask for it.
#
# Fires once per session; silent when no profile is discoverable.
# Opt out with WRITING_VOICE=false.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/voice-common.sh
source "$SELF_DIR/lib/voice-common.sh"

voice_opt_out
voice_payload

PROMPT=$(voice_field '.prompt')
[ -z "$PROMPT" ] && exit 0

# Writing/copy intent only — stay silent for code and other tasks.
printf '%s' "$PROMPT" | grep -qiE '(writ(e|ing)|draft|re-?writ|re-?word|webcopy|web copy|\bcopy\b|blog|newsletter|essay|headline|tagline|landing page|marketing|announce|prose|readme|changelog|release notes)' || exit 0

voice_profile # sets PROFILE, exits when none

SESSION=$(voice_field '.session_id')
voice_fire_once voice-intent || exit 0

voice_emit UserPromptSubmit "A writing voice profile exists at $PROFILE. Apply the \`writing:voice-profile\` skill (Skill tool) by default when writing or revising prose/copy — read the profile's rules first and draft in that voice rather than defaulting to generic AI prose."

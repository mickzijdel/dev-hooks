#!/bin/bash
# PreToolUse(Write|Edit|MultiEdit): Claude is about to write a prose file and a voice profile
# is discoverable — inject the profile's location into context BEFORE the draft lands, so the
# voice is in the first draft rather than patched into it afterwards.
#
# This is the hook the other two could not be. voice-intent-reminder.sh keys on the words of
# the prompt, and most prose work arrives without them; voice-reminder.sh runs after the
# write and only when a banned word appears. Neither sees "a prose file is about to be
# written", which is the moment that actually decides whether the voice gets applied.
#
# Emits additionalContext and NO permissionDecision, so the write proceeds through the normal
# permission flow. Deliberately not a `deny`/`ask`: the point is to inform the draft, not to
# gate the tool — and in auto mode an `ask` is answered by the classifier, not by the user.
#
# Fires once per session (Claude keeps the context afterwards); silent without a profile.
# Opt out with WRITING_VOICE=false.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/voice-common.sh
source "$SELF_DIR/lib/voice-common.sh"

voice_opt_out
voice_payload

FILE=$(voice_field '.tool_input.file_path')
[ -z "$FILE" ] && exit 0
voice_is_prose_file "$FILE" || exit 0

voice_profile # sets PROFILE, exits when none

SESSION=$(voice_field '.session_id')
voice_fire_once voice-prewrite || exit 0

BASE=${FILE##*/}
voice_emit PreToolUse "You are about to write prose to $BASE, and a writing voice profile exists at $PROFILE. Read it and draft in that voice now — applying it to this write is the point; revising generic AI prose into it afterwards is strictly worse. The \`writing:voice-profile\` skill (Skill tool) explains how to apply the profile's register dial."

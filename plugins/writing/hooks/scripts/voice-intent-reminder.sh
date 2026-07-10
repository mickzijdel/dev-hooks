#!/bin/bash
# UserPromptSubmit: when a voice profile is discoverable AND the user's prompt reads as a
# writing/copy task, nudge Claude to apply the `writing:voice-profile` skill BEFORE drafting —
# so the person's voice is baked into the first draft, instead of only being patched afterward
# by the reactive voice-reminder.sh. Advisory only: injects additionalContext and exits 0.
#
# Fires once per session (Claude keeps the nudge in context after the first fire); silent when
# no profile is discoverable, so installs without a profile see nothing.
#
# Profile lookup (first hit wins): $WRITING_VOICE_PROFILE, <cwd>/.claude/voice_profile.md,
# ~/.claude/voice_profile.md — the same order as voice-reminder.sh.
#
# Deliberately self-contained: the writing plugin installs without dev-hooks, so this script
# cannot source dev-hooks' lib/reminder-common.sh.
#
# Opt out with WRITING_VOICE=false (shares the switch with voice-reminder.sh).

# jscpd:ignore-start — opt-out + UserPromptSubmit prompt read, shared with thinking-tools-nudge.sh;
# both are self-contained (their plugins install without dev-hooks' lib/reminder-common.sh).
case "${WRITING_VOICE:-}" in
  false | 0 | no | off) exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || exit 0

PAYLOAD=$(cat 2>/dev/null)
PROMPT=$(printf '%s' "$PAYLOAD" | jq -r '.prompt // empty' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0
# jscpd:ignore-end

# Writing/copy intent only — stay silent for code and other tasks.
printf '%s' "$PROMPT" | grep -qiE '(writ(e|ing)|draft|re-?writ|re-?word|webcopy|web copy|\bcopy\b|blog|newsletter|essay|headline|tagline|landing page|marketing|announce|prose|readme|changelog|release notes)' || exit 0

# jscpd:ignore-start — voice-profile lookup, shared verbatim with voice-reminder.sh (both are
# self-contained: the writing plugin installs without dev-hooks' lib/reminder-common.sh).
CWD=$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty' 2>/dev/null)
PROFILE=""
for cand in "${WRITING_VOICE_PROFILE:-}" "${CWD:+$CWD/.claude/voice_profile.md}" "$HOME/.claude/voice_profile.md"; do
  [ -n "$cand" ] && [ -f "$cand" ] && PROFILE="$cand" && break
done
[ -z "$PROFILE" ] && exit 0
# jscpd:ignore-end

# Once per session — Claude keeps the nudge in context after the first fire.
SESSION=$(printf '%s' "$PAYLOAD" | jq -r '.session_id // "nosession"' 2>/dev/null)
MARKER_DIR="${TMPDIR:-/tmp}/writing-voice-intent"
mkdir -p "$MARKER_DIR" 2>/dev/null
MARKER="$MARKER_DIR/${SESSION:-nosession}"
[ -e "$MARKER" ] && exit 0
: >"$MARKER" 2>/dev/null

MSG="A writing voice profile exists at $PROFILE. Apply the \`writing:voice-profile\` skill (Skill tool) by default when writing or revising prose/copy — read the profile's rules first and draft in that voice rather than defaulting to generic AI prose."
jq -cn --arg msg "$MSG" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $msg}}'
exit 0

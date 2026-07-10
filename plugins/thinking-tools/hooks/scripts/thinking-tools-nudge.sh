#!/bin/bash
# UserPromptSubmit: a tiny, targeted nudge toward the ONE thinking-tool that fits the prompt's
# situation, so Claude self-initiates it instead of waiting for the exact trigger phrase.
# Advisory only: injects a one-line additionalContext and exits 0. Silent unless a cue matches.
#
# Deliberately self-contained: thinking-tools installs without dev-hooks, so this script cannot
# source dev-hooks' lib/reminder-common.sh.
#
# Opt out with THINKING_TOOLS=false (shares the switch with thinking-tools-reminder.sh).

# jscpd:ignore-start — opt-out + UserPromptSubmit prompt read, shared with voice-intent-reminder.sh;
# both are self-contained (their plugins install without dev-hooks' lib/reminder-common.sh).
case "${THINKING_TOOLS:-}" in
  false | 0 | no | off) exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || exit 0

PAYLOAD=$(cat 2>/dev/null)
PROMPT=$(printf '%s' "$PAYLOAD" | jq -r '.prompt // empty' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0
# jscpd:ignore-end

# First matching cue wins; keep the tip to a single skill so the nudge stays tiny.
TIP=""
if printf '%s' "$PROMPT" | grep -qiE 'poke holes|be brutal|tear (it|this) apart|red[ -]?team|what am i missing'; then
  TIP="thinking-tools:board"
elif printf '%s' "$PROMPT" | grep -qiE 'is (it|this) (really |actually )?(done|fixed|working)|for real|did you (actually|really) (test|run|check)|ready to ship'; then
  TIP="thinking-tools:but-for-real"
elif printf '%s' "$PROMPT" | grep -qiE 'what could go wrong|premortem|before (we|i) commit|stress[ -]?test|pressure[ -]?test|sanity[ -]?check'; then
  TIP="thinking-tools:premortem"
elif printf '%s' "$PROMPT" | grep -qiE 'grill me|interview me|ask me questions|help me (fully )?specify'; then
  TIP="thinking-tools:grill"
fi
[ -z "$TIP" ] && exit 0

jq -cn --arg msg "Consider the \`$TIP\` skill (Skill tool)." \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $msg}}'
exit 0

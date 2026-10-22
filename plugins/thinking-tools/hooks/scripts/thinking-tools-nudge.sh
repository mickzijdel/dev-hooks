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

# Only the words the person typed: a copy of dev-hooks' reminder_prompt_typed filter, pinned
# equal by test_typed_prompt_filters_match (an injected prompt, IDE context, a paste or a
# forwarded side-agent note's quoted lines would otherwise pick a tip).
TYPED_JQ='gsub("<ide_(?<t>[a-z_]+)>[\\s\\S]*?</ide_\\k<t>>"; "")
  | sub("\\A\\s+"; "")
  | if test("\\A(<task-notification>|\\[dev-hooks CI watch\\]|<agent-message[^>]*>\\s*\\[Subagent hand-back\\])")
    then ""
    else gsub("<pasted_content(?<a>[^>]*)>[\\s\\S]*?</pasted_content\\k<a>>"; "")
      | if startswith("Here is a note offered by a side agent:")
        then split("\n")[1:] | map(select(test("\\A\\s*>") | not)) | join("\n")
        else . end
    end
  | sub("\\A\\s+"; "") | sub("\\s+\\z"; "")'
TYPED=$(jq -rn --arg p "$PROMPT" "\$p | $TYPED_JQ" 2>/dev/null) && PROMPT=$TYPED
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
elif printf '%s' "$PROMPT" | grep -qiE 'be (really |very )?thorough|go deep|deep[ -]dive|quick (look|pass|and dirty)|(don.t|do not) go overboard'; then
  TIP="thinking-tools:brief-back"
fi
[ -z "$TIP" ] && exit 0

jq -cn --arg msg "Consider the \`$TIP\` skill (Skill tool)." \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $msg}}'
exit 0

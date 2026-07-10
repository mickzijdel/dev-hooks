#!/bin/bash
# bet: model won't restate its assumed goal/non-goals (or ask) when handed a thin task brief
# sunset: model reliably surfaces assumptions and asks clarifying questions on ambiguous briefs unprompted
# UserPromptSubmit hook: when a prompt is a *task* (an imperative change request) but
# states neither WHY (intent) nor NON-GOALS (what's out of scope), inject one advisory
# nudging Claude to restate its assumed goal + out-of-scope before substantial work — and
# to ask when the task is ambiguous or high-stakes. A thin brief is the trigger; the echo
# is the payload. It never blocks: on a match it emits additionalContext and exits 0.
#
# Deliberately conservative — it fires only when ALL hold, so "qualifying" stays rare:
#   • task-shaped   — opens with an imperative change-verb (add/fix/build/refactor/…)
#   • no WHY        — no intent marker (because / so that / the goal is / …)
#   • no NON-GOALS  — no scope marker (don't / without / out of scope / leave … alone / …)
#   • not a follow-up (also/now/next/…) — those inherit intent from earlier in the session
#   • 3+ words and not a long, already-detailed brief
# Every gate errs toward silence: a missed thin brief costs nothing, a false nudge costs
# one sentence. Tune the marker/verb lists below as needed.
#
# CRITICAL: a UserPromptSubmit hook's stdout is injected into Claude's context, so this
# hook prints ONLY the structured additionalContext JSON (via reminder_emit_prompt) and
# otherwise stays silent. Opt out per repo/user with DEV_HOOKS_INTENT_CHECK=false.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
reminder_prompt_init DEV_HOOKS_INTENT_CHECK # sets PROMPT; exits silently if empty/opted-out

p="${PROMPT,,}" # lowercase for matching

# Trim leading whitespace (no extglob needed).
p_trim="${p#"${p%%[![:space:]]*}"}"

# Follow-up / continuation → silent: the WHY is already established upthread.
if [[ $p_trim =~ ^(also|now|next|then|and|same|another|one\ more|do\ the\ same|keep\ going|continue) ]]; then
  exit 0
fi

# Already-detailed brief → assume enough context even without our exact markers.
[ "${#PROMPT}" -gt 1200 ] && exit 0

# Too short to be a real brief (skips tiny continuations like "fix it").
read -ra _words <<<"$p_trim"
[ "${#_words[@]}" -lt 3 ] && exit 0

# Strip a leading politeness/filler phrase so the verb check can anchor on the real verb.
for _pre in "please " "pls " "can you " "could you " "would you " "will you " "let's " "lets " \
  "go ahead and " "help me " "i want you to " "i want to " "i need you to " "i need to " \
  "i'd like you to " "i'd like to " "just " "quickly " "now "; do
  while [[ $p_trim == "$_pre"* ]]; do p_trim="${p_trim#"$_pre"}"; done
done

# Task-shaped? First word must be an imperative change-verb.
first_word="${p_trim%%[[:space:]]*}"
first_word="${first_word%%[[:punct:]]}"
VERBS="add fix build implement create make change update remove delete rename refactor \
migrate write wire integrate generate convert replace extract split combine rework redo \
port configure enable disable support improve optimize scaffold setup set install upgrade bump"
case " $VERBS " in
  *" $first_word "*) ;; # task-shaped — keep going
  *) exit 0 ;;
esac

# Has a WHY (intent) marker → not a thin brief, stay silent.
WHY_RE='because|so that|so we|so it|so i |so you |so the |so users|in order to|the point is|the goal is|the idea is|the reason|reason:|rationale|motivation|why:|context:|this is for|to avoid|to prevent|to stop|to fix|to reduce|to ensure|to keep|to speed up|to make it|to support'
[[ $p =~ ($WHY_RE) ]] && exit 0

# Has a NON-GOAL (scope) marker → not a thin brief, stay silent.
NG_RE="don't|do not|dont|don’t|without|out of scope|out-of-scope|non-?goal|avoid|must not|mustn't|no need to|leave [a-z ]* alone|keep [a-z ]* unchanged"
[[ $p =~ ($NG_RE) ]] && exit 0

reminder_emit_prompt "The user's request says what to do but not why or what's out of scope. \
Before substantial work, briefly restate the goal as you understand it and the thing(s) you'll \
treat as out of scope, then proceed on those assumptions unless corrected. When the task is \
ambiguous or high-stakes/irreversible (auth, migrations, deletions, schema, anything \
outward-facing), ask clarifying questions first — as many as you genuinely need — instead of guessing."

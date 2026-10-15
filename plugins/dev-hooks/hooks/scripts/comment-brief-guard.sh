#!/bin/bash
# bet: model delegates a comment pass by restating compress-comments' rules in a subagent
#   brief, so the subagent never loads the skill and skips its checks
# sunset: delegated comment passes name the skill unprompted
# PreToolUse(Agent|SendMessage): deny a brief that asks for a comment trim/pass/cleanup
# without naming the compress-comments skill, so the subagent loads the skill instead.
#
# Opt out with DEV_HOOKS_COMMENT_BRIEF_GUARD=false in settings env.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

reminder_pre_init DEV_HOOKS_COMMENT_BRIEF_GUARD \
  '(.tool_input.prompt // .tool_input.message // "") | if type == "string" then . else tostring end'

case "$COMMAND" in *compress-comments*) exit 0 ;; esac

# Imperative forms only: reviewer briefs and reports mention a past "comment pass" too.
PASS_RE='(do|run|make|perform|include|then) (a |the |one )?(final |separate |full |quick )?comment (pass|trim|cleanup|clean-up|sweep)|(trim|compress|prune|clean up|tidy up) (all |the |its |your |any )?(code |new |added )?comments'
printf '%s' "$COMMAND" | grep -qiE "$PASS_RE" || exit 0

reminder_emit_decision deny "This brief asks for a comment pass without the compress-comments skill. Tell the subagent to load dev-hooks:compress-comments with the Skill tool and follow it, instead of restating its rules: the skill's checks (code unchanged, nothing load-bearing deleted) only run when it's loaded."

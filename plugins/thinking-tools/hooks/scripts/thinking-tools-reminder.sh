#!/bin/bash
# SessionStart: remind Claude that the thinking-tools skills exist and should be reached for
# PROACTIVELY at the moments they fit — not only when the user says a magic phrase. The skill
# descriptions are trigger lists keyed on user asks; this nudge adds the Claude-side "do it on
# your own initiative" framing. Advisory only: injects additionalContext and exits 0.
#
# Deliberately self-contained: thinking-tools installs without dev-hooks, so this script cannot
# source dev-hooks' lib/reminder-common.sh.
#
# Opt out with THINKING_TOOLS=false (in .claude settings "env").

case "${THINKING_TOOLS:-}" in
  false | 0 | no | off) exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || exit 0

MSG="Reach for the thinking-tools skills (Skill tool) on your own initiative, not only when asked: before committing to a non-trivial plan or irreversible change -> \`thinking-tools:premortem\`; before claiming something is done/fixed/working -> \`thinking-tools:but-for-real\`; when a plan or draft needs hard, independent critique -> \`thinking-tools:board\`; before returning work you're unsure about -> \`thinking-tools:self-rate\`; after modifying code -> \`thinking-tools:code-simplifier\`; when a significant architectural decision gets made -> \`thinking-tools:adr\`."
jq -cn --arg msg "$MSG" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $msg}}'
exit 0

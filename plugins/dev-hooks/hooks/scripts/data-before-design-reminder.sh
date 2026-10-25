#!/bin/bash
# bet: model designs a view of stored data from the schema and the request, without first
#      checking what the field actually contains, and builds one layout instead of offering a
#      choice — both only discovered after the component exists
# sunset: model reliably profiles a field and offers mock alternatives before building a view
# UserPromptSubmit hook: when a prompt asks to BUILD a UI that DISPLAYS stored data, inject
# one advisory pointing at the data-before-design skill. It never blocks: on a match it emits
# additionalContext and exits 0.
#
# Conservative by design — fires only when ALL hold, so it stays rare:
#   • build-shaped   — a build verb (add/build/make/create/design/show/render/…) followed,
#                      within six words and the same sentence, by
#   • view-shaped      a display surface (card/view/panel/dashboard/table/chart/…), each a
#                      whole word: as substrings, "address", "review" and "Airtable" were
#                      85% of its fires in a replay of the prompt log
#   • not a tweak    — no restyle-only marker (colour/padding/font/spacing/align/…)
#   • typed          — matched on the person's own words, not on an injected prompt (a
#                      subagent's report, a task notification) or pasted/quoted text
#   • once per session
# A missed prompt costs nothing; a false nudge costs one sentence.
#
# CRITICAL: a UserPromptSubmit hook's stdout is injected into Claude's context, so this hook
# prints ONLY the structured additionalContext JSON (via reminder_emit_prompt) and otherwise
# stays silent. Opt out per repo/user with DEV_HOOKS_DATA_BEFORE_DESIGN=false.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
reminder_prompt_init DEV_HOOKS_DATA_BEFORE_DESIGN # sets PROMPT; exits silently if empty/opted-out
reminder_prompt_typed                             # what the person typed, in REPLY
[ -n "$REPLY" ] || exit 0

p="${REPLY,,}"

# Must ask to build a surface that displays records: the verb, then the noun within six
# words (no line break or sentence end between them).
verb='(add|build|make|create|design|implement|render|show|display|lay[[:blank:]]?out|redesign)'
noun='(cards?|panels?|views?|panes?|dashboards?|tables?|grids?|reports?|charts?|graphs?|summary|summaries|profiles?|columns?|badges?|tiles?|widgets?)'
gap="([[:blank:],]+[a-z0-9/&'-]+){0,6}[[:blank:],]+"
[[ $p =~ (^|[^a-z])$verb$gap$noun([^a-z]|$) ]] || exit 0

# Pure restyling has no data question — stay silent.
[[ $p =~ (colou?r|padding|margin|font|spacing|align|border|shadow|rounded|dark[[:space:]]mode|css[[:space:]]only) ]] && exit 0

reminder_fire_once data_before_design || exit 0

reminder_emit_prompt "Before designing this: load the \`data-before-design\` skill. Three steps it asks for, all BEFORE writing markup — (0) finish the sentence \"someone looking at this is deciding ___\"; every field earns its place by changing that decision, and prominence tracks decision weight, not which field was easiest to query. (1) Profile every field the view will show (non-null count, distinct values, length min/mean/p95/max, coverage, cardinality per parent, whether it carries a date, and what any number can be compared against) and state the numbers; a field that is NULL everywhere, always-true, or 50 characters long changes what you should build. (2) For anything card-shaped, mock several options from real records and let the user pick before you build — and mock the ideal, empty, partial, loading and error states, not just the one that looks good."

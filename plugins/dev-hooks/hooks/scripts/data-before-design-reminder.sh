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
#   • build-shaped   — an imperative build verb (add/build/make/create/design/show/render/…)
#   • view-shaped    — names a display surface (card/view/panel/dashboard/table/chart/…)
#   • not a tweak    — no restyle-only marker (colour/padding/font/spacing/align/…)
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

p="${PROMPT,,}"

# Must be asking to build something.
[[ $p =~ (add|build|make|create|design|implement|render|show|display|lay[[:space:]]?out|redesign) ]] || exit 0

# Must name a surface that displays records.
[[ $p =~ (card|panel|view|pane|dashboard|table|grid|report|chart|graph|summary|profile|column|badge|tile|widget|list[[:space:]]view|detail[[:space:]]view) ]] || exit 0

# Pure restyling has no data question — stay silent.
[[ $p =~ (colou?r|padding|margin|font|spacing|align|border|shadow|rounded|dark[[:space:]]mode|css[[:space:]]only) ]] && exit 0

reminder_fire_once data_before_design || exit 0

reminder_emit_prompt "Before designing this: load the \`data-before-design\` skill. Two steps it asks for, both BEFORE writing markup — (1) profile every field the view will show (non-null count, distinct values, length min/mean/max, coverage, cardinality per parent, whether it carries a date) and state the numbers; a field that is NULL everywhere, always-true, or 50 characters long changes what you should build. (2) For anything card-shaped, mock several options from real records — the busiest, the typical and the empty one — and let the user pick before you build."

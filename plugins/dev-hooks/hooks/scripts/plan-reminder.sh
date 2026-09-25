#!/bin/bash
# bet: none (L1 — backstops Mick's multi-session current_plan.md workflow)
# sunset: never (workflow preference)
# Stop hook: if a multi-session plan exists at .claude/current_plan.md and hasn't
# been touched in the last 120s, remind Claude to update it before the session ends.
#
# The 120s check is a staleness test, not a re-arm: a plan two minutes old stays two
# minutes old, so on its own it fired on every Stop for the rest of the session (84
# times in one session in the 2026-08-20 fire log). The plan's mtime at the last fire
# is stored in reminder_state_file instead, and the reminder repeats only once the plan
# has actually moved on — one nudge per version of the plan.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
# Sets SESSION so the fire log can tell "fired in 20 sessions" from "20 times in one",
# and so the marker below is per-session. "" skips the sentinel guard: the stored mtime
# is this hook's own re-arm.
reminder_stop_init ""

[ -f .claude/current_plan.md ] || exit 0

last_mod=$(stat -c %Y .claude/current_plan.md 2>/dev/null) || exit 0
[ -n "$last_mod" ] || exit 0
[ $(($(date +%s) - last_mod)) -gt 120 ] || exit 0

reminder_state_file plan-reminder
[ "$(cat "$REPLY" 2>/dev/null)" = "$last_mod" ] && exit 0
printf '%s' "$last_mod" >"$REPLY" 2>/dev/null

reminder_emit_note 'REMINDER: An active plan exists at .claude/current_plan.md. Before ending this session, update it with: completed phases, files changed, tests passing/failing, known issues, and the exact next step.'

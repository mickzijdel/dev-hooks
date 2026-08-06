#!/bin/bash
# bet: none (L1 — backstops Mick's multi-session current_plan.md workflow)
# sunset: never (workflow preference)
# Stop hook: if a multi-session plan exists at .claude/current_plan.md and hasn't
# been touched in the last 120s, remind Claude to update it before the session ends.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
# Sets SESSION so the fire log can tell "fired in 20 sessions" from "20 times in one".
# "" skips the sentinel guard: the mtime check below is this hook's own re-arm.
reminder_stop_init ""

if [ -f .claude/current_plan.md ]; then
  last_mod=$(stat -c %Y .claude/current_plan.md 2>/dev/null)
  now=$(date +%s)
  if [ $((now - last_mod)) -gt 120 ]; then
    reminder_emit_note 'REMINDER: An active plan exists at .claude/current_plan.md. Before ending this session, update it with: completed phases, files changed, tests passing/failing, known issues, and the exact next step.'
  fi
fi

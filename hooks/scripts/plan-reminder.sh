#!/bin/bash
# Stop hook: if a multi-session plan exists at .claude/current_plan.md and hasn't
# been touched in the last 120s, remind Claude to update it before the session ends.

if [ -f .claude/current_plan.md ]; then
  last_mod=$(stat -c %Y .claude/current_plan.md 2>/dev/null)
  now=$(date +%s)
  if [ $((now - last_mod)) -gt 120 ]; then
    echo 'REMINDER: An active plan exists at .claude/current_plan.md. Before ending this session, update it with: completed phases, files changed, tests passing/failing, known issues, and the exact next step.'
  fi
fi

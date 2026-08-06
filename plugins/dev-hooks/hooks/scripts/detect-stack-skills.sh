#!/bin/bash
# bet: model won't check the skill list against the project stack on its own
# sunset: model reliably discovers and applies stack-relevant skills unprompted
# SessionStart hook (global): detect the project's language/framework and remind
# Claude to consult the applicable skills/conventions before writing code.
#
# Ruby/Rails reminders are owned by the rails-toolkit plugin's own hook. This hook
# does NOT short-circuit on Rails: a Rails app commonly also has a JS/TS frontend,
# and that stack still deserves its own reminder here (the messages don't overlap).
#
# Extensible: add a stack by appending a detection block that pushes onto STACKS.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
# Sets INPUT, DIR (the session's cwd) and SESSION.
reminder_session_init

STACKS=()

# Python
if [ -f "$DIR/pyproject.toml" ] || [ -f "$DIR/requirements.txt" ] || [ -f "$DIR/setup.py" ] || [ -f "$DIR/setup.cfg" ]; then
  STACKS+=("Python (check pyproject.toml/requirements for deps, linters like ruff/flake8, and the test runner such as pytest)")
fi

# JavaScript / TypeScript
if [ -f "$DIR/package.json" ] || [ -f "$DIR/tsconfig.json" ]; then
  STACKS+=("JavaScript/TypeScript (check package.json scripts, the package manager via the lockfile, the linter, and the test runner)")
fi

# Nothing recognized — stay silent.
[ ${#STACKS[@]} -eq 0 ] && exit 0

# Build a single combined reminder.
LIST=$(printf '%s; ' "${STACKS[@]}")
LIST=${LIST%; }
MSG="Stack detected for this project: ${LIST}. Before writing or changing code, check for any installed skills relevant to this stack (via the Skill tool) and follow the project's existing conventions and tooling."

reminder_emit_session "$MSG"

#!/bin/bash
# Runs when Claude stops. Detects changed code files, runs applicable linters/tests,
# and feeds failures back to Claude so it can fix them before finishing.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

# Must be in a git repo
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Collect changed code files (staged + unstaged vs HEAD)
reminder_changed_files # sets CHANGED
[ -z "$CHANGED" ] && exit 0

HAS_RUBY=$(echo "$CHANGED" | grep -qE '\.(rb|erb|rake)$' && echo 1 || echo 0)
HAS_PYTHON=$(echo "$CHANGED" | grep -qE '\.py$' && echo 1 || echo 0)
HAS_JS=$(echo "$CHANGED" | grep -qE '\.(js|ts|jsx|tsx|vue|mjs|cjs)$' && echo 1 || echo 0)

# Nothing relevant changed
[ "$HAS_RUBY$HAS_PYTHON$HAS_JS" = "000" ] && exit 0

reminder_mktemp # result in $REPLY; the lib owns the cleanup trap
TMPFILE=$REPLY

TOOLS_RAN=0

# ── Ruby ──────────────────────────────────────────────────────────────────────
if [ "$HAS_RUBY" = "1" ]; then
  # RuboCop (check only — autocorrect already runs on each file write)
  if [ -f ".rubocop.yml" ] && bundle list 2>/dev/null | grep -q rubocop; then
    TOOLS_RAN=1
    out=$(bundle exec rubocop --no-color 2>&1)
    if [ $? -ne 0 ]; then
      printf '=== RuboCop ===\n%s\n\n' "$(echo "$out" | tail -c 1500)" >>"$TMPFILE"
    fi
  fi

  # Minitest via Rails
  if [ -f "bin/rails" ] && [ -f "Gemfile" ] && grep -q 'minitest' Gemfile 2>/dev/null; then
    TOOLS_RAN=1
    out=$(bin/rails test 2>&1)
    if [ $? -ne 0 ]; then
      printf '=== Minitest ===\n%s\n\n' "$(echo "$out" | tail -c 1500)" >>"$TMPFILE"
    fi
  # RSpec (if no Rails test runner)
  elif [ -f ".rspec" ] || [ -d "spec" ]; then
    TOOLS_RAN=1
    out=$(bundle exec rspec 2>&1)
    if [ $? -ne 0 ]; then
      printf '=== RSpec ===\n%s\n\n' "$(echo "$out" | tail -c 1500)" >>"$TMPFILE"
    fi
  fi
fi

# ── Python ────────────────────────────────────────────────────────────────────
if [ "$HAS_PYTHON" = "1" ]; then
  # ruff
  if [ -f "ruff.toml" ] || ([ -f "pyproject.toml" ] && grep -q '\[tool\.ruff\]' pyproject.toml 2>/dev/null); then
    TOOLS_RAN=1
    out=$(ruff check . 2>&1)
    if [ $? -ne 0 ]; then
      printf '=== ruff ===\n%s\n\n' "$(echo "$out" | tail -c 1500)" >>"$TMPFILE"
    fi
  fi

  # pytest
  if command -v pytest >/dev/null 2>&1 &&
    ([ -f "pytest.ini" ] || [ -f "pyproject.toml" ] || [ -d "tests" ] || [ -d "test" ]); then
    TOOLS_RAN=1
    out=$(pytest 2>&1)
    if [ $? -ne 0 ]; then
      printf '=== pytest ===\n%s\n\n' "$(echo "$out" | tail -c 1500)" >>"$TMPFILE"
    fi
  fi
fi

# ── JavaScript / TypeScript ───────────────────────────────────────────────────
if [ "$HAS_JS" = "1" ]; then
  if [ -f "pnpm-lock.yaml" ]; then
    PM="pnpm"
  elif [ -f "yarn.lock" ]; then
    PM="yarn"
  else PM="npm"; fi

  # ESLint
  if ls .eslintrc* eslint.config.* >/dev/null 2>&1; then
    TOOLS_RAN=1
    out=$($PM exec eslint . 2>&1)
    if [ $? -ne 0 ]; then
      printf '=== ESLint ===\n%s\n\n' "$(echo "$out" | tail -c 1500)" >>"$TMPFILE"
    fi
  fi

  # JS tests (only if a "test" script exists in package.json)
  if [ -f "package.json" ] && python3 -c \
    "import json; d=json.load(open('package.json')); exit(0 if 'test' in d.get('scripts',{}) else 1)" 2>/dev/null; then
    TOOLS_RAN=1
    out=$($PM test 2>&1)
    if [ $? -ne 0 ]; then
      printf '=== JS Tests ===\n%s\n\n' "$(echo "$out" | tail -c 1500)" >>"$TMPFILE"
    fi
  fi
fi

# ── Report ────────────────────────────────────────────────────────────────────
if [ -s "$TMPFILE" ]; then
  reminder_emit_stop "Verification failed. Fix these before finishing:"$'\n'"$(cat "$TMPFILE")"
elif [ "$TOOLS_RAN" = "0" ]; then
  # No tools detected — remind Claude to check manually
  reminder_emit_stop "No test suite or linter was auto-detected, but code files were modified. If this project has tests or a linter, please run them now to verify your changes before finishing."
fi

exit 0

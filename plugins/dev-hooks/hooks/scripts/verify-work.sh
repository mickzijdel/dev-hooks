#!/bin/bash
# bet: none (L3 — runs the project's real linters/tests; the no-tools branch is a once-per-session nudge)
# sunset: never (verification)
# Runs when Claude stops. Detects changed code files, runs applicable linters/tests,
# and feeds failures back to Claude so it can fix them before finishing.
#
# Opt out entirely with DEV_HOOKS_VERIFY=false (per-repo/user, in a .claude/settings.json
# "env" block). Real linter/test failures re-block on every stop until fixed; the "no tooling
# detected" advisory fires at most once per session so a repo with no recognised tooling is
# never trapped in a Stop loop.
#
# Test-suite scope is controlled by DEV_HOOKS_VERIFY_TESTS (default "full"):
#   full     run the whole test suite when code changed (the default; unchanged behaviour)
#   changed  run only changed test files + tests path-mapped from changed source
#            (app/models/user.rb -> test/models/user_test.rb); nothing mapped -> skip tests
#   off      skip the test run entirely; linters and scanners still run
# Set it per repo via the "env" block of that repo's .claude/settings.json (hooks inherit it).
# Test runs are wrapped in a soft timeout (DEV_HOOKS_VERIFY_TEST_TIMEOUT, default 110s, under
# the 120s hook limit): a run that exceeds it is stopped gracefully and the hook recommends
# switching to "changed" and/or adding a fast smoke-test subset, rather than being hard-killed.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

# Blanket opt-out (per-repo/user), on top of the per-mode DEV_HOOKS_VERIFY_TESTS.
reminder_opt_out DEV_HOOKS_VERIFY

# Consume the hook payload and populate SESSION for the once-per-session no-tools nudge below.
# Pass "" so no sentinel is imposed on the dynamic failure path (real failures must re-fire
# every stop until fixed — that's ground truth, not a one-shot reminder).
reminder_stop_init ""

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
SLOW_TESTS=0

# Test scope: full (default) | changed | off. An unknown value falls back to full.
MODE="${DEV_HOOKS_VERIFY_TESTS:-full}"
case "$MODE" in changed | off | full) ;; *) MODE=full ;; esac
# Soft cap on EACH test run, kept under the hook's 120s hard timeout (0 disables it). Note
# this is per-run, not a cumulative budget: uncapped scanners and multiple suites in a polyglot
# repo can still add up past 120s. A non-numeric value falls back to the default rather than
# making `timeout` error the run out.
TEST_TIMEOUT="${DEV_HOOKS_VERIFY_TEST_TIMEOUT:-110}"
case "$TEST_TIMEOUT" in '' | *[!0-9]*) TEST_TIMEOUT=110 ;; esac

# Print the subset of changed files matching an egrep pattern (empty when none match).
changed_matching() { echo "$CHANGED" | grep -E "$1"; }

# Filter a newline list down to paths that exist on disk (one per line).
existing() { while read -r f; do [ -n "$f" ] && [ -f "$f" ] && echo "$f"; done; }

# Run a test command, honouring the soft timeout, and report the outcome.
#   $1 = failure-section label, rest = command (plus any targeted files)
# Sets TOOLS_RAN and, on timeout, SLOW_TESTS; appends real failures to $TMPFILE.
run_test() {
  local label=$1
  shift
  TOOLS_RAN=1
  local out rc
  out=$(_capped "$@" 2>&1)
  rc=$?
  if [ "$rc" -eq 124 ]; then
    SLOW_TESTS=1
  elif [ "$rc" -ne 0 ]; then
    printf '=== %s ===\n%s\n\n' "$label" "$(echo "$out" | tail -c 1500)" >>"$TMPFILE"
  fi
}

# Cap a command with the soft timeout when `timeout` is available (coreutils; absent on a
# bare macOS). A timed-out command exits 124, which run_test turns into the slow-suite advice.
_capped() {
  if [ "$TEST_TIMEOUT" != 0 ] && command -v timeout >/dev/null 2>&1; then
    timeout "$TEST_TIMEOUT" "$@"
  else
    "$@"
  fi
}

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

  # herb — ERB lint + parse check, when an ERB file changed and herb is bundled (v17 standard)
  if echo "$CHANGED" | grep -qE '\.erb$' && [ -f "Gemfile" ] && grep -qw herb Gemfile.lock 2>/dev/null; then
    TOOLS_RAN=1
    out=$(bundle exec herb lint app/ 2>&1 && bundle exec herb analyze app/ 2>&1)
    if [ $? -ne 0 ]; then
      printf '=== herb (ERB) ===\n%s\n\n' "$(echo "$out" | tail -c 1500)" >>"$TMPFILE"
    fi
  fi

  # Security + correctness scanners, when Ruby code changed and the gems are bundled (v17 standard).
  # Each is guarded by its Gemfile.lock entry so only repos that adopted v17 pay the cost.
  if echo "$CHANGED" | grep -qE '\.rb$' && [ -f "Gemfile" ]; then
    if grep -qw brakeman Gemfile.lock 2>/dev/null; then
      TOOLS_RAN=1
      out=$(bundle exec brakeman -q --no-pager --exit-on-warn 2>&1)
      [ $? -ne 0 ] && printf '=== Brakeman ===\n%s\n\n' "$(echo "$out" | tail -c 1500)" >>"$TMPFILE"
    fi
    if grep -q bundler-audit Gemfile.lock 2>/dev/null; then
      TOOLS_RAN=1
      bundle exec bundle-audit update >/dev/null 2>&1 || true
      out=$(bundle exec bundle-audit check 2>&1)
      [ $? -ne 0 ] && printf '=== bundler-audit ===\n%s\n\n' "$(echo "$out" | tail -c 1500)" >>"$TMPFILE"
    fi
    if grep -q database_consistency Gemfile.lock 2>/dev/null &&
      bin/rails runner "ActiveRecord::Base.connection" >/dev/null 2>&1; then
      TOOLS_RAN=1
      out=$(bundle exec database_consistency 2>&1)
      [ $? -ne 0 ] && printf '=== database_consistency ===\n%s\n\n' "$(echo "$out" | tail -c 1500)" >>"$TMPFILE"
    fi
  fi

  # Test suite (skipped entirely in `off` mode; `changed` mode targets only affected files)
  if [ "$MODE" != off ]; then
    # Minitest via Rails
    if [ -f "bin/rails" ] && [ -f "Gemfile" ] && grep -q 'minitest' Gemfile 2>/dev/null; then
      TOOLS_RAN=1
      if [ "$MODE" = changed ]; then
        targets=$(
          {
            changed_matching '(^|/)test/.*_test\.rb$'
            changed_matching '^app/.*\.rb$' | sed -E 's|^app/|test/|; s|\.rb$|_test.rb|'
            changed_matching '^lib/.*\.rb$' | sed -E 's|^lib/|test/lib/|; s|\.rb$|_test.rb|'
          } | sort -u | existing
        )
        # shellcheck disable=SC2086
        [ -n "$targets" ] && run_test "Minitest (changed)" bin/rails test $targets
      else
        run_test "Minitest" bin/rails test
      fi
    # RSpec (if no Rails test runner)
    elif [ -f ".rspec" ] || [ -d "spec" ]; then
      TOOLS_RAN=1
      if [ "$MODE" = changed ]; then
        targets=$(
          {
            changed_matching '(^|/)spec/.*_spec\.rb$'
            changed_matching '^app/.*\.rb$' | sed -E 's|^app/|spec/|; s|\.rb$|_spec.rb|'
            # lib/ specs live at spec/lib/ in a Rails app but flat at spec/ in a conventional
            # gem — offer both candidates and let `existing` keep whichever is real.
            changed_matching '^lib/.*\.rb$' | sed -E 's|^lib/|spec/lib/|; s|\.rb$|_spec.rb|'
            changed_matching '^lib/.*\.rb$' | sed -E 's|^lib/|spec/|; s|\.rb$|_spec.rb|'
          } | sort -u | existing
        )
        # shellcheck disable=SC2086
        [ -n "$targets" ] && run_test "RSpec (changed)" bundle exec rspec $targets
      else
        run_test "RSpec" bundle exec rspec
      fi
    fi
  fi
fi

# ── Python ────────────────────────────────────────────────────────────────────
if [ "$HAS_PYTHON" = "1" ]; then
  # ruff
  if [ -f "ruff.toml" ] || { [ -f "pyproject.toml" ] && grep -q '\[tool\.ruff\]' pyproject.toml 2>/dev/null; }; then
    TOOLS_RAN=1
    out=$(ruff check . 2>&1)
    if [ $? -ne 0 ]; then
      printf '=== ruff ===\n%s\n\n' "$(echo "$out" | tail -c 1500)" >>"$TMPFILE"
    fi
  fi

  # pytest
  if [ "$MODE" != off ] && command -v pytest >/dev/null 2>&1 &&
    { [ -f "pytest.ini" ] || [ -f "pyproject.toml" ] || [ -d "tests" ] || [ -d "test" ]; }; then
    TOOLS_RAN=1
    if [ "$MODE" = changed ]; then
      targets=$(changed_matching '(^|/)(test_[^/]*|[^/]*_test)\.py$' | existing)
      # shellcheck disable=SC2086
      [ -n "$targets" ] && run_test "pytest (changed)" pytest $targets
    else
      run_test "pytest" pytest
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

  # JS tests (only if a "test" script exists in package.json). There's no portable way to run a
  # subset by file, so `changed` mode marks the tooling detected but skips the run (linters
  # still ran); `full` runs the whole `<pm> test` script.
  if [ "$MODE" != off ] && [ -f "package.json" ] && python3 -c \
    "import json,sys; d=json.load(open('package.json')); sys.exit(0 if 'test' in d.get('scripts',{}) else 1)" 2>/dev/null; then
    TOOLS_RAN=1
    [ "$MODE" = full ] && run_test "JS Tests" "$PM" test
  fi
fi

# ── Report ────────────────────────────────────────────────────────────────────
MSG=""
[ -s "$TMPFILE" ] && MSG="Verification failed. Fix these before finishing:"$'\n'"$(cat "$TMPFILE")"
if [ "$SLOW_TESTS" = "1" ]; then
  advisory="The test suite exceeded ${TEST_TIMEOUT}s and was stopped before finishing (the Stop hook is hard-killed at 120s). This suite is likely too slow to run on every stop.
Recommended: set DEV_HOOKS_VERIFY_TESTS=changed in this repo's .claude/settings.json \"env\" block to run only affected tests, and/or add a fast smoke-test subset (current mode: ${MODE})."
  if [ -n "$MSG" ]; then MSG="$MSG"$'\n\n'"$advisory"; else MSG="$advisory"; fi
fi

if [ -n "$MSG" ]; then
  # Real failures re-fire on every stop attempt until fixed — correct for ground truth.
  reminder_emit_stop "$MSG"
elif [ "$TOOLS_RAN" = "0" ] && [ "$MODE" != off ] && reminder_fire_once verify-work-notools; then
  # No tools detected — nudge Claude to check manually, but only ONCE per session (suppressed
  # in `off` mode). Unlike a real failure this is a judgment guess from the absence of known
  # configs, so a repo with no recognised tooling must not be trapped in a Stop loop: the model
  # gets the reminder once, then is free to stop.
  reminder_emit_stop "No test suite or linter was auto-detected, but code files were modified. If this project has tests or a linter, please run them now to verify your changes before finishing."
fi

exit 0

#!/bin/bash
# bet: none (L3 — runs the project's real linters/tests; the no-tools branch is a once-per-session nudge)
# sunset: never (verification)
# Runs when Claude stops. Detects changed code files, runs applicable linters/tests,
# and feeds failures back to Claude so it can fix them before finishing.
#
# Opt out entirely with DEV_HOOKS_VERIFY=false (per-repo/user, in a .claude/settings.json
# "env" block). Real linter/test failures re-block on every stop until fixed, forced
# continuations included (max 3 blocks in a row, and none for the failure the last block
# already reported unchanged); the "no tooling detected" advisory fires at
# most once per session so a repo with no recognised tooling is never trapped in a Stop loop.
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
# Linters and scanners get the same cap, and one that exceeds it is named as having no verdict.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

# Blanket opt-out (per-repo/user), on top of the per-mode DEV_HOOKS_VERIFY_TESTS.
reminder_opt_out DEV_HOOKS_VERIFY

# Consume the hook payload and populate SESSION for the once-per-session no-tools nudge below.
# Pass "" so no sentinel is imposed on the dynamic failure path (real failures must re-fire
# every stop until fixed — that's ground truth, not a one-shot reminder).
# --when-active: a forced continuation is where Claude edits code, so verify it too.
reminder_stop_init "" --when-active

# Must be in a git repo
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Collect changed code files (staged + unstaged vs HEAD)
# Files this session touched, committed ones included: CLAUDE.md mandates commit-as-you-go,
# so a porcelain-only gate would skip verification on exactly the sessions that finished
# their work properly.
reminder_session_files
CHANGED=$SESSION_FILES
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
SLOW_CHECKS=""
RUN_IS_CHECK=""

# Test scope: full (default) | changed | off. An unknown value falls back to full.
MODE="${DEV_HOOKS_VERIFY_TESTS:-full}"
case "$MODE" in changed | off | full) ;; *) MODE=full ;; esac
# Soft cap on EACH test run and lint or scanner run, kept under the hook's 120s hard timeout
# (0 disables it). Note this is per-run, not a cumulative budget: several in a polyglot repo
# can still add up past 120s. A non-numeric value falls back to the default rather than
# making `timeout` error the run out.
TEST_TIMEOUT="${DEV_HOOKS_VERIFY_TEST_TIMEOUT:-110}"
case "$TEST_TIMEOUT" in '' | *[!0-9]*) TEST_TIMEOUT=110 ;; esac

# Print the subset of changed files matching an egrep pattern (empty when none match).
changed_matching() { echo "$CHANGED" | grep -E "$1"; }

# Filter a newline list down to paths that exist on disk (one per line).
existing() { while read -r f; do [ -n "$f" ] && [ -f "$f" ] && echo "$f"; done; }

# Run a test command, honouring the soft timeout, and report the outcome.
#   $1 = failure-section label, rest = command (plus any targeted files)
# Sets TOOLS_RAN and, on timeout, SLOW_TESTS (SLOW_CHECKS under run_check); appends real
# failures to $TMPFILE. Returns the command's exit code.
run_test() {
  local label=$1
  shift
  TOOLS_RAN=1
  local out rc
  out=$(_capped "$@" 2>&1)
  rc=$?
  if [ "$rc" -eq 124 ]; then
    if [ -n "$RUN_IS_CHECK" ]; then SLOW_CHECKS="${SLOW_CHECKS:+$SLOW_CHECKS, }$label"; else SLOW_TESTS=1; fi
  elif [ "$rc" -ne 0 ]; then
    printf '=== %s ===\n%s\n\n' "$label" "$(echo "$out" | tail -c 1500)" >>"$TMPFILE"
  fi
  return "$rc"
}

# A linter or scanner under the same cap. One that runs out of time has no verdict, so it is
# named in an advisory instead of being reported as failing.
run_check() {
  local RUN_IS_CHECK=1
  run_test "$@"
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

# Whether the project actually has pytest tests, not just generic Python-project markers — a
# bare pyproject.toml or tests/ dir also matches repos whose tests aren't pytest at all (e.g.
# a tests/ full of bash *.test.sh scripts plus a Python helper script). Search is pruned to
# skip heavy/vendor dirs and stay cheap.
_verify_work_has_pytest_tests() {
  [ -f "pytest.ini" ] && return 0
  [ -f "conftest.py" ] && return 0
  if [ -f "pyproject.toml" ] && grep -q '^\[tool\.pytest' pyproject.toml 2>/dev/null; then
    return 0
  fi
  # In a git repo, only files git tracks or would track count: gitignored dirs hold vendored
  # code with its own test_*.py (e.g. Ansible collections under .ansible/).
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files -co --exclude-standard 2>/dev/null |
      grep -qE '(^|/)(conftest\.py|test_[^/]*\.py|[^/]*_test\.py)$'
    return
  fi
  find . \( -path ./.venv -o -path ./node_modules -o -path ./.git \) -prune -o \
    \( -name conftest.py -o -name 'test_*.py' -o -name '*_test.py' \) -print 2>/dev/null |
    grep -q .
}

# Python tools run through uv in a uv project: its venv may live outside the repo
# (UV_PROJECT_ENVIRONMENT), where a bare `pytest` never resolves. --no-sync: a Stop hook
# never installs packages or rewrites uv.lock. $1 = the project dir (default: the root).
_verify_work_py_run() {
  PY_RUN=()
  [ -f "${1:-.}/uv.lock" ] && command -v uv >/dev/null 2>&1 && PY_RUN=(uv run --no-sync)
}
_verify_work_py_run

# Whether a directory carries pytest configuration of its own.
_verify_work_has_pytest_config() {
  [ -f "$1/pytest.ini" ] ||
    grep -qs '^\[tool\.pytest' "$1/pyproject.toml" ||
    grep -qs '^\[tool:pytest\]' "$1/setup.cfg" ||
    grep -qs '^\[pytest\]' "$1/tox.ini"
}

# Directories to run pytest in, one per line. pytest only loads the config of the directory
# it starts in (or above), so in a repo whose suite lives in a subproject (backend/ with its
# own pyproject.toml: asyncio_mode, pythonpath, ...) a run from the root ignores all of it
# and fails wholesale. The root wins when it has config or a conftest.py of its own;
# otherwise each outermost subproject that does, falling back to the root.
_verify_work_pytest_dirs() {
  if _verify_work_has_pytest_config . || [ -f conftest.py ]; then
    echo .
    return
  fi
  local dirs
  dirs=$(git ls-files -co --exclude-standard 2>/dev/null |
    grep -E '(^|/)(pytest\.ini|pyproject\.toml|setup\.cfg|tox\.ini)$' |
    while read -r f; do
      d=$(dirname "$f")
      [ "$d" != . ] && _verify_work_has_pytest_config "$d" && echo "$d"
    done | sort -u | awk 'NR == 1 || index($0, kept "/") != 1 { print; kept = $0 }')
  if [ -n "$dirs" ]; then echo "$dirs"; else echo .; fi
}

# Prefix that runs a command from another directory: `"${IN_DIR[@]}" <dir> <cmd...>`. Not a
# shell function, because run_test hands its command to `timeout`, which can't run one.
# shellcheck disable=SC2016
IN_DIR=(bash -c 'cd "$1" && shift && exec "$@"' in-dir)

# Whether pytest can actually run in dir $1 (default: the root), under the current PY_RUN. `command -v` alone
# isn't enough: a version-manager shim (mise, asdf, ...) can resolve on PATH with no
# version selected and fail loudly on first use.
_verify_work_pytest_runnable() {
  [ ${#PY_RUN[@]} -gt 0 ] && {
    "${IN_DIR[@]}" "${1:-.}" "${PY_RUN[@]}" pytest --version >/dev/null 2>&1
    return
  }
  command -v pytest >/dev/null 2>&1 && "${IN_DIR[@]}" "${1:-.}" pytest --version >/dev/null 2>&1
}

# ── Ruby ──────────────────────────────────────────────────────────────────────
if [ "$HAS_RUBY" = "1" ]; then
  # RuboCop (check only — autocorrect already runs on each file write)
  if [ -f ".rubocop.yml" ] && bundle list 2>/dev/null | grep -q rubocop; then
    run_check RuboCop bundle exec rubocop --no-color
  fi

  # herb — ERB lint + parse check, when an ERB file changed and herb is bundled (v17 standard)
  if echo "$CHANGED" | grep -qE '\.erb$' && [ -f "Gemfile" ] && grep -qw herb Gemfile.lock 2>/dev/null; then
    run_check "herb (ERB)" bundle exec herb lint app/ &&
      run_check "herb (ERB)" bundle exec herb analyze app/
  fi

  # Security + correctness scanners, when Ruby code changed and the gems are bundled (v17 standard).
  # Each is guarded by its Gemfile.lock entry so only repos that adopted v17 pay the cost.
  if echo "$CHANGED" | grep -qE '\.rb$' && [ -f "Gemfile" ]; then
    if grep -qw brakeman Gemfile.lock 2>/dev/null; then
      run_check Brakeman bundle exec brakeman -q --no-pager --exit-on-warn
    fi
    if grep -q bundler-audit Gemfile.lock 2>/dev/null; then
      _capped bundle exec bundle-audit update >/dev/null 2>&1 || true
      run_check bundler-audit bundle exec bundle-audit check
    fi
    if grep -q database_consistency Gemfile.lock 2>/dev/null &&
      _capped bin/rails runner "ActiveRecord::Base.connection" >/dev/null 2>&1; then
      run_check database_consistency bundle exec database_consistency
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
    run_check ruff "${PY_RUN[@]}" ruff check .
  fi

  # pytest — gated on actual pytest-tests evidence, not just generic Python-project markers
  # (a bare pyproject.toml or tests/ dir also matches non-pytest repos, e.g. a tests/ full of
  # bash *.test.sh scripts plus a Python helper script — server-setup is exactly this shape).
  if [ "$MODE" != off ] && _verify_work_has_pytest_tests; then
    TOOLS_RAN=1
    while read -r dir; do
      label=pytest
      [ "$dir" != . ] && label="pytest ($dir)"
      _verify_work_py_run "$dir"
      if ! _verify_work_pytest_runnable "$dir"; then
        # pytest resolved on PATH but doesn't actually run (not installed, or a version
        # manager shim like mise/asdf has no version selected) — report one clear line
        # instead of letting `pytest` dump its raw (and possibly unrelated-looking, e.g.
        # "mise ERROR ...") failure.
        printf '=== %s ===\n%s\n\n' "$label" \
          "pytest tests were detected but pytest is not runnable (not installed, or a version manager has no version selected for this project). Fix the pytest toolchain, then rerun." >>"$TMPFILE"
      elif [ "$MODE" = changed ]; then
        # Changed test files under this dir, relative to it.
        prefix=""
        [ "$dir" != . ] && prefix="$dir/"
        targets=$(changed_matching '(^|/)(test_[^/]*|[^/]*_test)\.py$' | existing |
          while read -r f; do case "$f" in "$prefix"*) echo "${f#"$prefix"}" ;; esac done)
        # shellcheck disable=SC2086
        [ -n "$targets" ] && run_test "$label (changed)" "${IN_DIR[@]}" "$dir" "${PY_RUN[@]}" pytest $targets
      else
        run_test "$label" "${IN_DIR[@]}" "$dir" "${PY_RUN[@]}" pytest
      fi
    done < <(_verify_work_pytest_dirs)
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
    run_check ESLint "$PM" exec eslint .
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
[ -s "$TMPFILE" ] && MSG="Verification failed. Fix these before finishing. A failure this session didn't cause still counts: don't pass over it; name the check and what fails in your reply, and offer the fix under Your move."$'\n'"$(cat "$TMPFILE")"
if [ "$SLOW_TESTS" = "1" ]; then
  advisory="The test suite exceeded ${TEST_TIMEOUT}s and was stopped before finishing (the Stop hook is hard-killed at 120s). This suite is likely too slow to run on every stop.
Recommended: set DEV_HOOKS_VERIFY_TESTS=changed in this repo's .claude/settings.json \"env\" block to run only affected tests, and/or add a fast smoke-test subset (current mode: ${MODE})."
  if [ -n "$MSG" ]; then MSG="$MSG"$'\n\n'"$advisory"; else MSG="$advisory"; fi
fi
if [ -n "$SLOW_CHECKS" ]; then
  advisory="${SLOW_CHECKS} ran past ${TEST_TIMEOUT}s and was stopped (the Stop hook is hard-killed at 120s), so its result is unknown. Run it yourself before finishing."
  if [ -n "$MSG" ]; then MSG="$MSG"$'\n\n'"$advisory"; else MSG="$advisory"; fi
fi

if [ -n "$MSG" ]; then
  # Real failures re-fire on every natural stop until fixed — correct for ground truth.
  # Within a forced-continuation chain they are capped, so an unfixable failure still stops,
  # and a continuation that left the failure as it was isn't blocked again: the reply to the
  # last block already saw it, and the same text could only get that reply again.
  reminder_state_file verify-work-active-blocks
  COUNT_FILE=$REPLY
  reminder_state_file verify-work-last-failure
  LAST_FILE=$REPLY
  # shortcut: digits are dropped, so run times and seeds don't count as a change, and nor does
  # a failure that changed only in a number; the next natural stop checks it again regardless.
  FAILURE=$(printf '%s' "$MSG" | tr -s '0-9' '#' | cksum)
  BLOCKS=0
  if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    BLOCKS=$(cat "$COUNT_FILE" 2>/dev/null)
    case "$BLOCKS" in *[!0-9]* | "") BLOCKS=0 ;; esac
    if [ "$BLOCKS" -ge 3 ] || [ "$FAILURE" = "$(cat "$LAST_FILE" 2>/dev/null)" ]; then
      # The failure stands; tell the mod so it doesn't score this stop as a pass.
      [ -n "${DEV_HOOKS_ORCHESTRATED:-}" ] && echo "dev-hooks: block cap reached" >&2
      exit 0
    fi
    BLOCKS=$((BLOCKS + 1))
  fi
  printf '%s' "$BLOCKS" >"$COUNT_FILE" 2>/dev/null
  printf '%s' "$FAILURE" >"$LAST_FILE" 2>/dev/null
  reminder_emit_stop "$MSG"
elif [ "$TOOLS_RAN" = "0" ] && [ "$MODE" != off ] && reminder_fire_once verify-work-notools; then
  # No tools detected — nudge Claude to check manually, but only ONCE per session (suppressed
  # in `off` mode). Unlike a real failure this is a judgment guess from the absence of known
  # configs, so a repo with no recognised tooling must not be trapped in a Stop loop: the model
  # gets the reminder once, then is free to stop.
  reminder_emit_stop "No test suite or linter was auto-detected, but code files were modified. If this project has tests or a linter, please run them now to verify your changes before finishing."
fi

exit 0

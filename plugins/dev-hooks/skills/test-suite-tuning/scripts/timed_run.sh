#!/usr/bin/env bash
# One timed test run: machine load before, wall seconds, exit code, the runner's summary lines.
#   timed_run.sh [-l FILE_LIST] NAME COMMAND [ARG...]
# -l appends each line of FILE_LIST (one test file per line) as an argument, so every run of a
# scope gets the same files whatever the shell (zsh does not split an unquoted variable).
# The full output goes to NAME.log. Any runner: `timed_run.sh base1 env SEED=1 bin/rails test`.
set -u

list=""
if [ "${1:-}" = "-l" ]; then
  list="${2:-}"
  shift 2
fi
if [ $# -lt 2 ]; then
  echo "usage: timed_run.sh [-l FILE_LIST] NAME COMMAND [ARG...]" >&2
  exit 2
fi
name="$1"
shift

files=()
if [ -n "$list" ]; then
  if [ ! -r "$list" ]; then
    echo "timed_run.sh: cannot read $list" >&2
    exit 2
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] && files+=("$line")
  done <"$list"
  if [ ${#files[@]} -eq 0 ]; then
    echo "timed_run.sh: $list is empty" >&2
    exit 2
  fi
fi

now() { python3 -c 'import time; print("%.1f" % time.time())' 2>/dev/null || date +%s; }

# macOS prints "load averages: 1.0 2.0 3.0", Linux "load average: 1.0, 2.0, 3.0"
load="$(LC_ALL=C uptime | sed -E 's/.*load averages?: *([0-9.]+).*/\1/')"
cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 0)"
start="$(now)"
"$@" ${files[@]+"${files[@]}"} >"$name.log" 2>&1
code=$?
wall="$(awk -v a="$start" -v b="$(now)" 'BEGIN { printf "%.1f", b - a }')"

echo "$name: wall ${wall}s, exit $code, load before $load on $cores cores, files ${#files[@]}"
if awk -v l="$load" -v c="$cores" 'BEGIN { exit !(c > 0 && l > c) }'; then
  echo "$name: LOAD ABOVE CORES: this wall time measures the machine, and a failure may be the machine too"
fi
grep -aE 'Test Files|^ +Tests |^Tests:|Duration|seed|[0-9]+ (runs|examples|passed|failed)|on retry|flaky' "$name.log" | tail -8
exit "$code"

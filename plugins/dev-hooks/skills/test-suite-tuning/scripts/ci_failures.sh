#!/usr/bin/env bash
# Which tests fail, or pass only on a retry, across a workflow's recent runs on GitHub Actions.
#   ci_failures.sh [-R OWNER/REPO] [-n RUNS] [-m TITLE_REGEX] WORKFLOW
# Reads the check-run annotations of the last RUNS completed runs (default 100), green ones
# too, and every attempt of a re-run job: one API call per run plus one per job, no logs.
# About a second per run: run it in the background above 100 runs. Prints the date range the
# runs cover, then one line per annotation title: distinct head commits, runs, last date, level.
# A job that failed or timed out with no test annotation is listed at the end: read its log.
# -m: which annotation titles are tests (default: "file > name", "file::name", "Class#test_x",
# or a title that says retry or flaky).
set -uo pipefail

repo=""
runs=100
match=' > |::|#test_|[Rr]etr|[Ff]laky'
while getopts "R:n:m:" opt; do
  case "$opt" in
    R) repo="$OPTARG" ;;
    n) runs="$OPTARG" ;;
    m) match="$OPTARG" ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
if [ $# -ne 1 ]; then
  echo "usage: ci_failures.sh [-R OWNER/REPO] [-n RUNS] [-m TITLE_REGEX] WORKFLOW (names: gh workflow list)" >&2
  exit 2
fi
if ! jq -n --arg m "$match" '"" | test($m)' >/dev/null 2>&1; then
  echo "ci_failures.sh: -m is not a regular expression jq accepts: $match" >&2
  exit 2
fi
[ -n "$repo" ] || repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)" || exit 1

list="$(gh run list -R "$repo" --workflow "$1" --status completed --limit "$runs" \
  --json databaseId,conclusion,headSha,createdAt)" || exit 1
count="$(jq length <<<"$list")"
if [ "$count" -eq 0 ]; then
  echo "ci_failures.sh: no completed run of workflow '$1' in $repo" >&2
  exit 1
fi
jq -r '"runs: \(length) (\(map(select(.conclusion != "success")) | length) not green), " +
  "from \(map(.createdAt) | min) to \(map(.createdAt) | max)"' <<<"$list"

rows="$(mktemp)"
silent="$(mktemp)"
trap 'rm -f "$rows" "$silent"' EXIT
skipped=0
# the regex goes to jq as data, never into the program text
# shellcheck disable=SC2016
titles='.[] | select(.title != null and (.title | test($m))) | [.annotation_level,
  (if (.title | test(" > |::|#test_")) then .title
   else .title + ": " + ((.message // "") | split("\n")[0]) end)] | @tsv'
while IFS=$'\t' read -r id sha day; do
  if ! jobs="$(gh api "repos/$repo/actions/runs/$id/jobs?per_page=100&filter=all" \
    --jq '.jobs[] | [.id, .name, .conclusion] | @tsv')"; then
    skipped=$((skipped + 1))
    continue
  fi
  while IFS=$'\t' read -r job name conclusion; do
    [ -n "$job" ] || continue
    if ! found="$(gh api "repos/$repo/check-runs/$job/annotations?per_page=100" | jq -r --arg m "$match" "$titles" | sort -u)"; then
      skipped=$((skipped + 1))
      continue
    fi
    if [ -n "$found" ]; then
      while IFS=$'\t' read -r level title; do
        printf '%s\t%s\t%s\t%s\t%s\n' "$title" "$sha" "$id" "$day" "$level" >>"$rows"
      done <<<"$found"
    elif [ "$conclusion" = "failure" ] || [ "$conclusion" = "timed_out" ]; then
      printf '%s\t%s\n' "$name ($conclusion)" "$id" >>"$silent"
    fi
  done <<<"$jobs"
done < <(jq -r '.[] | [.databaseId, .headSha, .createdAt[0:10]] | @tsv' <<<"$list")
if [ "$skipped" -gt 0 ]; then
  echo "API calls that failed and were left out: $skipped (a rate limit? the counts below are a lower bound)"
  [ -s "$rows" ] || [ -s "$silent" ] || exit 1
fi

echo
echo "commits  runs  last seen   level    test (a candidate at 2 or more unrelated commits)"
awk -F'\t' '
  { key = $1; if (!seen[key, $2]++) commits[key]++; if (!ran[key, $3]++) n[key]++
    if ($4 > last[key]) last[key] = $4; level[key] = $5 }
  END { for (k in n) printf "%7d  %4d  %s  %-7s  %s\n", commits[k], n[k], last[k], level[k], k }
' "$rows" | sort -k1,1nr -k2,2nr

if [ -s "$silent" ]; then
  echo
  echo "failed jobs with no test annotation (runs, job, one run id): their failures are only in the log"
  awk -F'\t' '{ n[$1]++; id[$1] = $2 } END { for (j in n) printf "%4d  %s  %s\n", n[j], j, id[j] }' "$silent" | sort -nr
fi

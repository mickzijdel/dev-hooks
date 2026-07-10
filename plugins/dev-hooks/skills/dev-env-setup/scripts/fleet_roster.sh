#!/bin/bash
# dev-env-setup fleet discovery.
#
# Finds every repo under the given roots that tracks the dev-env standard (a top-level
# mise.toml carrying DEV_ENV_VERSION) and reports each repo's upgrade state, so a fleet
# backfill enumerates its targets live instead of trusting a hand-maintained roster.
#
# Usage: fleet_roster.sh [ROOT ...]   (default: ~/Stack/Programmeren)
#
# Emits on stdout:
#   current_version=N   the standard version shipped by this skill (from ../VERSION)
#   one tab-separated line per repo (tabs, not spaces — repo paths may contain spaces):
#     repo=<abs path>  name=<basename>  version=<repo's DEV_ENV_VERSION>
#     branch=<checked-out branch, "" if detached/not git>
#     dirty=<1 if uncommitted changes>  behind=<1 if version < current_version>
#   a "# fleet: N repo(s), N behind, N dirty" summary line.
#
# Scan depth is 2 (ROOT itself may be a repo, or a directory of repos); worktree
# checkouts (.worktrees/, .claude/worktrees/), node_modules, and .git are pruned.
# Always exits 0 — status lives in the data (matches dev_env_check.sh).

set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
current_version="$(tr -dc '0-9' <"$SELF_DIR/../VERSION" 2>/dev/null)"
[ -z "$current_version" ] && current_version=0
echo "current_version=$current_version"

if [ "$#" -gt 0 ]; then
  ROOTS=("$@")
else
  ROOTS=("$HOME/Stack/Programmeren")
fi

# Repos to drop from the fleet even though they carry a DEV_ENV_VERSION stamp (abandoned repos,
# forks you don't own): one basename per line in references/fleet-ignore.txt (# comments, blanks
# skipped). Editing that file is how you retire a repo without touching the repo itself.
IGNORE_FILE="$SELF_DIR/../references/fleet-ignore.txt"
ignored=""
[ -f "$IGNORE_FILE" ] && ignored="$(sed -e 's/#.*//' -e 's/^[[:space:]]*//;s/[[:space:]]*$//' "$IGNORE_FILE" | grep -v '^$')"

total=0
behind_total=0
dirty_total=0
while IFS= read -r mise_file; do
  grep -Eq '^[[:space:]]*DEV_ENV_VERSION[[:space:]]*=' "$mise_file" || continue
  repo="$(cd "$(dirname "$mise_file")" && pwd)"
  name="$(basename "$repo")"
  printf '%s\n' "$ignored" | grep -Fxq "$name" && continue
  version="$(grep -E '^[[:space:]]*DEV_ENV_VERSION[[:space:]]*=' "$mise_file" | head -n1 | tr -dc '0-9')"
  [ -z "$version" ] && version=0
  branch="$(git -C "$repo" symbolic-ref --short -q HEAD 2>/dev/null || true)"
  dirty=0
  [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ] && dirty=1
  behind=0
  [ "$version" -lt "$current_version" ] && behind=1
  printf 'repo=%s\tname=%s\tversion=%s\tbranch=%s\tdirty=%s\tbehind=%s\n' \
    "$repo" "$name" "$version" "$branch" "$dirty" "$behind"
  total=$((total + 1))
  behind_total=$((behind_total + behind))
  dirty_total=$((dirty_total + dirty))
done < <(
  for root in "${ROOTS[@]}"; do
    [ -d "$root" ] || continue
    find "$root" -maxdepth 2 \
      \( -name .worktrees -o -name worktrees -o -name node_modules -o -name .git \) -prune \
      -o -type f -name mise.toml -print 2>/dev/null
  done | sort -u
)

echo "# fleet: $total repo(s), $behind_total behind, $dirty_total dirty"
exit 0

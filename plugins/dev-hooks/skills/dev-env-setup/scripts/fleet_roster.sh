#!/bin/bash
# dev-env-setup fleet discovery.
#
# Finds every repo under the given roots that tracks the dev-env standard (a mise config carrying
# DEV_ENV_VERSION: mise.toml, .mise.toml, mise/config.toml, .config/mise.toml or
# .config/mise/config.toml) and reports each repo's upgrade state, so a fleet backfill enumerates
# its targets live instead of trusting a hand-maintained roster.
#
# Usage: fleet_roster.sh [ROOT ...]   (default: ~/Stack/Programmeren)
#
# Emits on stdout:
#   current_version=N   the standard version shipped by this skill (from ../VERSION)
#   one tab-separated line per repo (tabs, not spaces — repo paths may contain spaces):
#     repo=<abs path>  name=<basename>  version=<repo's DEV_ENV_VERSION>
#     branch=<checked-out branch, "" if detached/not git>
#     dirty=<1 if uncommitted changes>  behind=<1 if version < current_version>
#     origin_version=<the remote's DEV_ENV_VERSION at the same config path, after a fetch;
#       "" without one>
#     pull=<1 if origin_version > version: pull before upgrading, the work may be done>
#     origin_ref=<the remote branch origin_version was read from, e.g. upstream/main>
#   a "# fleet: N repo(s), N behind, N dirty, N to pull" summary line.
#
# The remote read is where the work lands: a remote named `upstream` (the real repo behind a fork,
# whose `origin` may be stale) on the tracking branch's name, else the tracking branch itself; the
# first that carries the stamp wins. Each is fetched (non-interactive, 20s cap); offline, the
# last-fetched ref is read instead.
#
# A repo is ROOT itself or a directory directly under it; worktree checkouts (.worktrees/,
# .claude/worktrees/), node_modules, .git and .config (which holds a config, never a repo) are
# skipped.
# Always exits 0 — status lives in the data (matches dev_env_check.sh).

set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
current_version="$(tr -dc '0-9' 2>/dev/null <"$SELF_DIR/../VERSION")"
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

# DEV_ENV_VERSION's digits from the mise config on stdin.
stamp() { grep -E '^[[:space:]]*DEV_ENV_VERSION[[:space:]]*=' | head -n1 | tr -dc '0-9'; }

# The first mise config in repo $1 that carries the stamp, relative to the repo.
stamped_config() {
  local f
  for f in mise.toml .mise.toml mise/config.toml .config/mise.toml .config/mise/config.toml; do
    if [ -f "$1/$f" ] && grep -Eq '^[[:space:]]*DEV_ENV_VERSION[[:space:]]*=' "$1/$f"; then
      printf '%s' "$f"
      return 0
    fi
  done
  return 1
}

bounded() {
  if command -v timeout >/dev/null 2>&1; then timeout 20 "$@"; else "$@"; fi
}

total=0
behind_total=0
dirty_total=0
pull_total=0
while IFS= read -r dir; do
  config="$(stamped_config "$dir")" || continue
  repo="$(cd "$dir" && pwd)"
  name="$(basename "$repo")"
  printf '%s\n' "$ignored" | grep -Fxq "$name" && continue
  version="$(stamp <"$repo/$config")"
  [ -z "$version" ] && version=0
  branch="$(git -C "$repo" symbolic-ref --short -q HEAD 2>/dev/null || true)"
  dirty=0
  [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ] && dirty=1
  behind=0
  [ "$version" -lt "$current_version" ] && behind=1
  # A checkout that never pulled reads an old stamp while origin already carries the upgrade.
  origin_version=""
  origin_ref=""
  pull=0
  tracking="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  refs=()
  git -C "$repo" remote get-url upstream >/dev/null 2>&1 && refs+=("upstream/${tracking#*/}")
  [ -n "$tracking" ] && refs+=("$tracking")
  for ref in ${refs[@]+"${refs[@]}"}; do
    [ "$ref" = upstream/ ] && ref=upstream/HEAD
    GIT_TERMINAL_PROMPT=0 bounded git -C "$repo" fetch --quiet "${ref%%/*}" >/dev/null 2>&1 || true
    origin_version="$(git -C "$repo" show "$ref:$config" 2>/dev/null | stamp)"
    if [ -n "$origin_version" ]; then
      origin_ref=$ref
      break
    fi
  done
  [ -n "$origin_version" ] && [ "$origin_version" -gt "$version" ] && pull=1
  printf 'repo=%s\tname=%s\tversion=%s\tbranch=%s\tdirty=%s\tbehind=%s\torigin_version=%s\tpull=%s\torigin_ref=%s\n' \
    "$repo" "$name" "$version" "$branch" "$dirty" "$behind" "$origin_version" "$pull" "$origin_ref"
  total=$((total + 1))
  behind_total=$((behind_total + behind))
  dirty_total=$((dirty_total + dirty))
  pull_total=$((pull_total + pull))
done < <(
  for root in "${ROOTS[@]}"; do
    [ -d "$root" ] || continue
    printf '%s\n' "$root"
    find "$root" -mindepth 1 -maxdepth 1 -type d ! -name .worktrees ! -name worktrees \
      ! -name node_modules ! -name .git ! -name .config 2>/dev/null
  done | sort -u
)

echo "# fleet: $total repo(s), $behind_total behind, $dirty_total dirty, $pull_total to pull"
exit 0

#!/usr/bin/env bash
# worktree-setup: provision a freshly-created git worktree so it's ready to work in.
#
# The native EnterWorktree tool (or `git worktree add`) checks out a worktree but leaves it
# unprovisioned. This script — run *inside* the new worktree, right after creation — closes
# the gaps:
#   1. mise:      trusts the worktree's mise.toml (it's the same repo you already trust, so
#                 this does NOT contradict dev-env-setup's "never auto-trust unknown configs")
#                 and sets `worktree.baseref head` so future worktrees branch from local HEAD.
#   2. secrets:   copies gitignored-but-needed files (Rails config/master.key, .env, …) from
#                 the main checkout, since git never put them in the worktree. Everything
#                 gitignored is copied EXCEPT known-heavy build/dependency dirs (node_modules,
#                 .venv, vendor/bundle, caches, …) and the worktree dir itself.
#   3. exec bits: re-applies +x to tracked shebang scripts the checkout may have dropped.
#
# It does NOT create the worktree (only the harness can switch the session into one) and never
# mutates the git index or commits anything.
#
# Usage: setup-worktree.sh [WORKTREE] [--source DIR]
#   WORKTREE     the worktree to provision (default: $PWD)
#   --source DIR the main checkout to copy gitignored files from
#                (default: auto-detected as the repo's main working tree)
#
# Emits machine-readable KEY=VALUE lines on stdout, then "# " summary lines. Keys:
#   source         absolute path of the main checkout copied from
#   worktree       absolute path of the provisioned worktree
#   mise_trusted   1 if `mise trust` ran on the worktree's mise.toml, else 0
#   copied         number of gitignored entries copied in
#   skipped_heavy  number of gitignored entries skipped as heavy/excluded
#   exec_fixed     number of shebang scripts re-marked executable

set -u

WT=""
SRC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --source)
      SRC="${2:-}"
      shift 2
      ;;
    --source=*)
      SRC="${1#--source=}"
      shift
      ;;
    -h | --help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      WT="$1"
      shift
      ;;
  esac
done

[ -n "$WT" ] || WT="$PWD"
if ! WT="$(cd "$WT" 2>/dev/null && pwd -P)"; then
  echo "setup-worktree: worktree path does not exist" >&2
  exit 1
fi

# Source = the repo's main working tree (first entry of `git worktree list`), unless overridden.
if [ -z "$SRC" ]; then
  SRC="$(git -C "$WT" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | head -1)"
fi
if [ -z "$SRC" ] || ! SRC="$(cd "$SRC" 2>/dev/null && pwd -P)"; then
  echo "setup-worktree: could not resolve source repo (run inside a git worktree, or pass --source)" >&2
  exit 1
fi

# ── 1. mise trust + baseref ─────────────────────────────────────────────────────────
git -C "$SRC" config worktree.baseref head 2>/dev/null || true
mise_trusted=0
if command -v mise >/dev/null 2>&1 && [ -f "$WT/mise.toml" ]; then
  mise trust "$WT" >/dev/null 2>&1 && mise_trusted=1
fi

# ── 2. copy gitignored-but-present files, skipping heavy dirs ─────────────────────────
# A gitignored entry is skipped when any path segment is a known-heavy build/dependency dir
# or the worktree dir itself (`.worktrees` / `.claude/worktrees`) — the latter is critical,
# else a worktree living under the repo would be copied into itself.
is_excluded() {
  case "/$1" in
    */node_modules/* | */node_modules | \
      */.venv/* | */.venv | \
      */venv/* | */venv | \
      */vendor/bundle/* | */vendor/bundle | \
      */tmp/* | */tmp | \
      */dist/* | */dist | \
      */build/* | */build | \
      */.next/* | */.next | \
      */.nuxt/* | */.nuxt | \
      */target/* | */target | \
      */__pycache__/* | */__pycache__ | \
      */.pytest_cache/* | */.pytest_cache | \
      */.ruff_cache/* | */.ruff_cache | \
      */.mypy_cache/* | */.mypy_cache | \
      */coverage/* | */coverage | \
      */.git/* | */.git | \
      */.worktrees/* | */.worktrees | \
      */.claude/worktrees/* | */.claude/worktrees)
      return 0
      ;;
  esac
  return 1
}

copied=0
skipped_heavy=0
if [ "$SRC" != "$WT" ]; then
  while IFS= read -r -d '' entry; do
    [ -n "$entry" ] || continue
    entry="${entry%/}" # --directory collapses ignored dirs with a trailing slash
    if is_excluded "$entry"; then
      skipped_heavy=$((skipped_heavy + 1))
      continue
    fi
    mkdir -p "$WT/$(dirname "$entry")"
    if cp -a "$SRC/$entry" "$WT/$entry" 2>/dev/null; then
      copied=$((copied + 1))
    fi
  done < <(git -C "$SRC" ls-files --others --ignored --exclude-standard --directory -z 2>/dev/null)
fi

# ── 3. re-apply exec bits to tracked shebang scripts (working tree only) ──────────────
exec_fixed=0
while IFS= read -r -d '' line; do
  [ -n "$line" ] || continue
  mode="${line%% *}"
  path="${line#*$'\t'}"
  f="$WT/$path"
  [ -f "$f" ] && [ ! -x "$f" ] || continue
  if [ "$mode" = 100755 ] || [ "$(head -c2 "$f" 2>/dev/null)" = '#!' ]; then
    chmod +x "$f" && exec_fixed=$((exec_fixed + 1))
  fi
done < <(git -C "$WT" ls-files -s -z 2>/dev/null)

# ── Output ────────────────────────────────────────────────────────────────────────────
cat <<EOF
source=$SRC
worktree=$WT
mise_trusted=$mise_trusted
copied=$copied
skipped_heavy=$skipped_heavy
exec_fixed=$exec_fixed
EOF

echo "# Provisioned worktree $WT"
echo "# Copied $copied gitignored file(s) from $SRC (skipped $skipped_heavy heavy/excluded)."
if [ "$mise_trusted" = 1 ]; then
  echo "# mise trusted; set worktree.baseref=head."
elif command -v mise >/dev/null 2>&1; then
  echo "# No mise.toml — skipped mise trust; set worktree.baseref=head."
else
  echo "# mise not installed — skipped trust; set worktree.baseref=head."
fi
echo "# Re-marked $exec_fixed shebang script(s) executable."

exit 0

#!/bin/bash
# bet: fewer "works in the main checkout, broken in the worktree" debugging detours
# sunset: 2027-03-01 (drop if native worktree tooling starts provisioning gitignored state itself)
# PostToolUse(Bash) hook: after `git worktree add`, check whether the new worktree is missing
# gitignored state the main checkout has (Rails `storage/`, `config/credentials/master.key`,
# `.env`, service-account JSON, uploads, fixtures) and point at
# `worktree-setup/scripts/setup-worktree.sh`. Advisory only — never blocks.
#
# Why: a fresh worktree gets tracked files only. Everything gitignored stays behind, so the app
# boots but misbehaves in ways that read as a code bug — a Rails app whose ActiveStorage blobs
# are absent serves 500s from `DiskService#stream` and renders empty image slots, which looks
# exactly like a broken view. Hand-rolling the copy is where this goes wrong: it is easy to copy
# `config/master.key` and miss that the repo actually uses `config/credentials/master.key`, and
# easy to forget `storage/` entirely. setup-worktree.sh enumerates gitignored state with
# `git ls-files --others --ignored --directory` instead of guessing.
#
# Fires only when the new worktree is ACTUALLY missing something — a correctly provisioned
# worktree stays silent, so this is a verdict rather than a nudge.
#
# Opt out per repo/user with DEV_HOOKS_WORKTREE_PROVISION=false (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
reminder_opt_out DEV_HOOKS_WORKTREE_PROVISION

INPUT=$(cat 2>/dev/null)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only a real `git worktree add`: tolerate env prefixes, `git -C dir`, and `… && git worktree add`.
printf '%s' "$COMMAND" |
  grep -Eq '(^|[^[:alnum:]_])git([[:space:]]+[^[:space:]]+)*[[:space:]]+worktree[[:space:]]+add([^[:alnum:]_]|$)' || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -z "$CWD" ] && CWD=$PWD
command -v git >/dev/null 2>&1 || exit 0

# The main working tree is the first entry of `git worktree list`; linked worktrees follow.
mapfile -t WT_PATHS < <(git -C "$CWD" worktree list --porcelain 2>/dev/null |
  awk '/^worktree /{ sub(/^worktree /,""); print }')
[ ${#WT_PATHS[@]} -ge 2 ] || exit 0
MAIN=${WT_PATHS[0]}
[ -d "$MAIN" ] || exit 0

# Which worktree was just created? Take the path straight from the command — the first
# non-flag token after `worktree add`. An mtime heuristic looks equivalent and is not: touching
# any older worktree (even `ln -s` inside it) makes it the newest, and the hook then audits the
# wrong directory and reports nothing missing.
NEW=""
read -r -a TOKENS <<<"$COMMAND"
for ((i = 0; i < ${#TOKENS[@]}; i++)); do
  [ "${TOKENS[i]}" = "worktree" ] || continue
  [ "${TOKENS[i + 1]:-}" = "add" ] || continue
  for ((j = i + 2; j < ${#TOKENS[@]}; j++)); do
    case ${TOKENS[j]} in
      -b | -B | --reason) ((j++)) ;; # flag consumes the next token
      --reason=* | -*) ;;            # valueless flag, or --opt=value
      *)
        NEW=${TOKENS[j]}
        break
        ;;
    esac
  done
  break
done
[ -n "$NEW" ] || exit 0
# `git worktree add` resolves a relative path against the shell's cwd, so do the same.
case $NEW in /*) ;; *) NEW="$CWD/$NEW" ;; esac
[ -d "$NEW" ] || exit 0

# Only audit a path git actually registered as a worktree — guards against a mis-parse.
printed=0
for p in "${WT_PATHS[@]:1}"; do
  [ "$(cd "$p" 2>/dev/null && pwd -P)" = "$(cd "$NEW" 2>/dev/null && pwd -P)" ] && printed=1 && break
done
[ "$printed" = 1 ] || exit 0

# Exact gitignored paths in the main checkout — NOT their top-level directories. Comparing
# directories misses the common case: Rails commits `storage/.keep`, so `storage/` exists in a
# fresh worktree while all its blobs are absent, and a `-e storage` test passes while the app
# 500s on every image. `config/` is tracked outright; only `config/credentials/master.key` is
# missing. `--directory` still collapses a fully ignored dir like node_modules to one entry.
mapfile -t IGNORED < <(git -C "$MAIN" ls-files --others --ignored --directory --exclude-standard 2>/dev/null | head -500)
[ ${#IGNORED[@]} -gt 0 ] || exit 0

# Same heavy/excluded list setup-worktree.sh skips, plus editor/tool caches whose absence is
# expected and harmless — listing those crowds out the entries that actually break the app.
is_heavy() {
  case $1 in
    node_modules | .venv | venv | vendor | tmp | dist | build | .next | .nuxt | target | \
      __pycache__ | .pytest_cache | .ruff_cache | .mypy_cache | coverage | .git | \
      .worktrees | .claude | .bundle | .idea | .vscode | .pnpm-store | .playwright-cli | \
      .DS_Store | log | .sass-cache | .parcel-cache | .turbo) return 0 ;;
    *) return 1 ;;
  esac
}

# Runtime state the app actually reads: uploads/blobs, secrets, env, service-account keys. These
# lead the report — a buried `storage` is why this hook exists, so it must never sort behind a
# stray .txt at the repo root.
is_load_bearing() {
  case $1 in
    storage | storage.* | config | .env | .env.* | credentials | uploads | fixtures | \
      secrets | *.key | *.pem | db | public) return 0 ;;
    *) return 1 ;;
  esac
}

# Count missing paths per top-level entry, so a report says `storage/ (173 missing)` rather
# than listing 173 blob directories.
declare -A MISS_COUNT=()
for entry in "${IGNORED[@]}"; do
  path=${entry%/}
  [ -n "$path" ] || continue
  top=${path%%/*}
  is_heavy "$top" && continue
  [ -e "$MAIN/$path" ] || continue
  [ -e "$NEW/$path" ] && continue
  MISS_COUNT[$top]=$((${MISS_COUNT[$top]:-0} + 1))
done
[ ${#MISS_COUNT[@]} -gt 0 ] || exit 0

PRIORITY=()
REST=()
for top in "${!MISS_COUNT[@]}"; do
  n=${MISS_COUNT[$top]}
  label=$top
  [ "$n" -gt 1 ] && label="$top/ ($n missing)"
  if is_load_bearing "$top"; then PRIORITY+=("$label"); else REST+=("$label"); fi
done
mapfile -t PRIORITY < <(printf '%s\n' "${PRIORITY[@]}" | sort)
mapfile -t REST < <(printf '%s\n' "${REST[@]}" | sort)
MISSING=("${PRIORITY[@]}" "${REST[@]}")

LIST=$(printf '%s, ' "${MISSING[@]:0:6}")
LIST=${LIST%, }
[ ${#MISSING[@]} -gt 6 ] && LIST="$LIST, +$((${#MISSING[@]} - 6)) more"

reminder_emit "The worktree you just created is missing gitignored state the main checkout has: ${LIST}. A fresh worktree gets tracked files only, so secrets, uploads and ActiveStorage blobs stay behind — the app will boot and then fail in ways that read as code bugs (missing Rails \`storage/\` blobs serve 500s from DiskService#stream and render empty image slots, which looks like a broken view). Provision it with the worktree-setup skill's script rather than copying by hand — hand-rolling is how \`config/credentials/master.key\` gets missed in favour of a \`config/master.key\` that does not exist: \`bash \"\${CLAUDE_PLUGIN_ROOT}/skills/worktree-setup/scripts/setup-worktree.sh\" <worktree-path>\`. It also trusts the worktree's mise.toml and re-marks shebang scripts executable. See [[worktree-setup]]."

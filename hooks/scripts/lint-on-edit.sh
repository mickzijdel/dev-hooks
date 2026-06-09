#!/bin/bash
# PostToolUse(Write|Edit): auto-fix/format the file Claude just wrote, using the
# linter that THIS project actually configures. Safe fixes only. Never blocks
# (always exits 0). Project-wide *checking* is handled separately by verify-work.sh.

FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
[ -f "$FILE" ] || exit 0

DIR=$(dirname "$FILE")

# Nearest ancestor that looks like a project root (fall back to the file's dir).
find_root() {
  d=$1
  while [ "$d" != "/" ]; do
    if [ -e "$d/Gemfile" ] || [ -e "$d/package.json" ] || [ -e "$d/pyproject.toml" ] || [ -d "$d/.git" ]; then
      echo "$d"
      return
    fi
    d=$(dirname "$d")
  done
  echo "$1"
}

# Run a JS/TS tool from the project's node_modules. No-ops if the project
# doesn't have the tool. Fast path: the local .bin binary when it actually
# executes (covers sane npm / pnpm / bun installs uniformly). Fallback for a
# broken/native .bin stub (e.g. biome's symlink mangled by a cross-platform
# install): the package runner matching this project's lockfile.
run_js() {
  local tool=$1
  shift
  local bin="$ROOT/node_modules/.bin/$tool"
  [ -e "$bin" ] || return 0
  if [ -x "$bin" ] && "$bin" --version >/dev/null 2>&1; then
    "$bin" "$@" >/dev/null 2>&1
    return 0
  fi
  if { [ -f "$ROOT/bun.lockb" ] || [ -f "$ROOT/bun.lock" ]; } && command -v bun >/dev/null 2>&1; then
    bun x "$tool" "$@" >/dev/null 2>&1
  elif [ -f "$ROOT/pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then
    pnpm exec "$tool" "$@" >/dev/null 2>&1
  else
    npx --no-install "$tool" "$@" >/dev/null 2>&1
  fi
}

ROOT=$(find_root "$DIR")
cd "$ROOT" || exit 0

case "$FILE" in
  # ── Ruby ────────────────────────────────────────────────────────────────────
  *.rb | *.rake)
    if [ -f Gemfile ] && grep -q rubocop Gemfile.lock 2>/dev/null; then
      bundle exec rubocop -a --force-exclusion "$FILE" >/dev/null 2>&1
    elif [ -f Gemfile ] && grep -q "standard " Gemfile.lock 2>/dev/null; then
      bundle exec standardrb --fix "$FILE" >/dev/null 2>&1
    elif command -v rubocop >/dev/null 2>&1; then
      rubocop -a --force-exclusion "$FILE" >/dev/null 2>&1
    elif command -v mise >/dev/null 2>&1; then
      mise x -- rubocop -a --force-exclusion "$FILE" >/dev/null 2>&1
    fi
    ;;

  # ── ERB ─────────────────────────────────────────────────────────────────────
  *.erb)
    # erb_lint autocorrect if the project bundles it
    if [ -f Gemfile ] && grep -q erb_lint Gemfile.lock 2>/dev/null; then
      bundle exec erblint -a "$FILE" >/dev/null 2>&1
    fi
    # Preserve existing syntax check (surfaces a message Claude can see)
    erb -x "$FILE" 2>/dev/null | ruby -c >/dev/null 2>&1 || echo "ERB syntax error in $FILE - please fix"
    ;;

  # ── Rails routes (preserve existing check) ───────────────────────────────────
  *config/routes*)
    [ -f bin/rails ] && { bin/rails routes >/dev/null 2>&1 || echo "Routes failed to compile - please fix"; }
    ;;

  # ── JS / TS / styles / data ──────────────────────────────────────────────────
  *.js | *.jsx | *.ts | *.tsx | *.vue | *.mjs | *.cjs | *.css | *.scss | *.json | *.md | *.yaml | *.yml)
    if [ -f biome.json ] || [ -f biome.jsonc ]; then
      run_js biome check --write "$FILE"
    else
      run_js prettier --write --ignore-unknown "$FILE"
      case "$FILE" in
        *.js | *.jsx | *.ts | *.tsx | *.vue | *.mjs | *.cjs)
          run_js eslint --fix "$FILE"
          ;;
      esac
    fi
    ;;

  # ── Python (best-effort: tools are not global) ───────────────────────────────
  *.py)
    if [ -x "$ROOT/.venv/bin/ruff" ]; then
      "$ROOT/.venv/bin/ruff" check --fix "$FILE" >/dev/null 2>&1
      "$ROOT/.venv/bin/ruff" format "$FILE" >/dev/null 2>&1
    elif command -v ruff >/dev/null 2>&1; then
      ruff check --fix "$FILE" >/dev/null 2>&1
      ruff format "$FILE" >/dev/null 2>&1
    elif [ -x "$ROOT/.venv/bin/black" ]; then
      "$ROOT/.venv/bin/black" "$FILE" >/dev/null 2>&1
    elif command -v black >/dev/null 2>&1; then
      black "$FILE" >/dev/null 2>&1
    fi
    ;;
esac

exit 0

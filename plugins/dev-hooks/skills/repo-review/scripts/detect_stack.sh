#!/usr/bin/env bash
# repo-review preflight.
#
# Read-only. Surveys a repo to decide which review axes apply and which specialist
# skill/command owns each, so the repo-review skill can dispatch deliberately instead
# of guessing. It does NOT read package contents, run linters, or mutate anything.
#
# The single most important output is is_rails: a Rails app should be handed wholesale
# to the deeper rails-audit skill rather than reviewed with the generic axes.
#
# Usage: detect_stack.sh [DIR]   (DIR default: $PWD)
#
# Emits machine-readable KEY=VALUE lines on stdout, then "# " summary lines. Keys:
#   is_rails     1 if a Rails app (Gemfile names rails + app/ + config/) → delegate to rails-audit
#   has_frontend 1 if web/template files present (html/erb/jsx/tsx/vue) → accessibility axis applies
#   has_ci       1 if any .github/workflows/*.y{a,}ml present → github-actions axis
#   has_tests    1 if a test/spec/__tests__ dir present
#   has_docker   1 if a Dockerfile/Containerfile present
#   has_devenv   1 if mise.toml or hk.pkl present → dev-env-setup axis
#   languages    space-separated languages detected by source extension

set -u

DIR="${1:-$PWD}"

# Count source files of a given extension under DIR, skipping vendored/VCS dirs.
count_ext() {
  find "$DIR" -type f -name "$1" \
    -not -path '*/.git/*' -not -path '*/node_modules/*' \
    -not -path '*/vendor/*' -not -path '*/.venv/*' 2>/dev/null | head -1 | wc -l | tr -d ' '
}

# ── Languages present (by source extension; a repo can carry several) ────────────────
languages=""
add_lang() { [ "$(count_ext "$1")" -gt 0 ] && languages="$languages $2"; }
add_lang '*.py' python
add_lang '*.rb' ruby
add_lang '*.ts' typescript
add_lang '*.js' javascript
add_lang '*.go' go
add_lang '*.rs' rust
languages="${languages# }"

# ── Rails detection: the one stack that delegates wholesale to rails-audit ───────────
is_rails=0
if [ -f "$DIR/Gemfile" ] && [ -d "$DIR/app" ] && [ -d "$DIR/config" ]; then
  grep -qE '^\s*gem\s+["'\'']rails["'\'']' "$DIR/Gemfile" 2>/dev/null && is_rails=1
fi

# ── Frontend / web surface → accessibility axis ─────────────────────────────────────
has_frontend=0
for ext in '*.html' '*.erb' '*.jsx' '*.tsx' '*.vue'; do
  if [ "$(count_ext "$ext")" -gt 0 ]; then
    has_frontend=1
    break
  fi
done

# ── CI, tests, Docker, dev-env surfaces ─────────────────────────────────────────────
has_ci=0
if [ -d "$DIR/.github/workflows" ] &&
  [ "$(find "$DIR/.github/workflows" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | head -1 | wc -l | tr -d ' ')" -gt 0 ]; then
  has_ci=1
fi

has_tests=0
for d in test tests spec __tests__; do
  [ -d "$DIR/$d" ] && has_tests=1 && break
done

has_docker=0
{ [ -f "$DIR/Dockerfile" ] || [ -f "$DIR/Containerfile" ]; } && has_docker=1

has_devenv=0
{ [ -f "$DIR/mise.toml" ] || [ -f "$DIR/hk.pkl" ]; } && has_devenv=1

# ── Output: KEY=VALUE block first (parseable), then human summary ────────────────────
cat <<EOF
is_rails=$is_rails
has_frontend=$has_frontend
has_ci=$has_ci
has_tests=$has_tests
has_docker=$has_docker
has_devenv=$has_devenv
languages=$languages
EOF

if [ "$is_rails" = 1 ]; then
  echo "# Rails app detected → delegate the whole review to the rails-audit skill (deeper, stack-specific)."
  exit 0
fi

echo "# Languages: ${languages:-none detected}"
echo "# Always-on axes: correctness (/code-review), code smells (/simplify), performance,"
echo "#   architecture, app security, test health, secrets hygiene."
[ "$has_devenv" = 1 ] && echo "# dev-env present (mise/hk) → dev-env-setup axis" || echo "# no mise/hk → flag dev-env gap (dev-env-setup)"
[ "$has_ci" = 1 ] && echo "# CI workflows present → github-actions supply-chain axis"
[ "$has_tests" = 1 ] && echo "# test dir present → check it RUNS from a clean checkout, not just that it exists"
[ "$has_docker" = 1 ] && echo "# Dockerfile present → layer-ordering review (dockerfile skill)"
[ "$has_frontend" = 1 ] && echo "# frontend files present → accessibility axis applies"
echo "# Dependencies axis: run skills/dependency-upgrade/scripts/upgrade_inventory.sh . --run"

exit 0

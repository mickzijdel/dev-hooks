#!/usr/bin/env bash
# dependency-upgrade preflight inventory.
#
# Read-only. Detects which dependency ecosystems a repo carries (JavaScript, Ruby,
# Python, GitHub Actions), picks each one's package manager from its lockfile/manifest,
# and prints the exact read-only command to list that ecosystem's outdated packages.
# It does NOT mutate anything and, by default, does NOT execute the listing commands
# (so it stays fast, offline, and deterministic) — pass --run to also execute the ones
# whose tool is installed. The dependency-upgrade skill consumes this to decide what to
# upgrade; the human reads the trailing "# " summary.
#
# Usage: upgrade_inventory.sh [DIR] [--run]   (DIR default: $PWD)
#
# Emits machine-readable KEY=VALUE lines on stdout, then "# " summary lines. Keys:
#   has_js          1 if package.json present
#   has_ruby        1 if Gemfile present
#   has_python      1 if pyproject.toml / requirements.txt / setup.py / setup.cfg present
#   has_actions     1 if any .github/workflows/*.y{a,}ml present
#   js_manager      pnpm | yarn | npm | none   (by lockfile; npm is the fallback)
#   ruby_manager    bundler | none
#   ruby_bundled_with  the Bundler version Gemfile.lock records (BUNDLED WITH) | none
#   ruby_cooldown_enforced  1 if that Bundler honours `cooldown` (>= 4.0.13), 0 if not,
#                   unknown without a lockfile. An older Bundler ignores the Gemfile's
#                   cooldown and BUNDLE_COOLDOWN silently.
#   python_manager  uv | poetry | pip | none   (by lockfile/manifest table)
#   actions_count   number of workflow files
#   ecosystems      space-separated list of the present ecosystems (js ruby python actions)

set -u

DIR="$PWD"
RUN=0
for arg in "$@"; do
  case "$arg" in
    --run) RUN=1 ;;
    *) DIR="$arg" ;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }

# ── Ecosystem detection (a repo can carry several at once) ──────────────────────────
has_js=0
[ -f "$DIR/package.json" ] && has_js=1

has_ruby=0
[ -f "$DIR/Gemfile" ] && has_ruby=1

has_python=0
for f in pyproject.toml requirements.txt setup.py setup.cfg; do
  [ -f "$DIR/$f" ] && has_python=1 && break
done

has_actions=0
actions_count=0
if [ -d "$DIR/.github/workflows" ]; then
  actions_count="$(find "$DIR/.github/workflows" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | wc -l | tr -d ' ')"
  [ "$actions_count" -gt 0 ] && has_actions=1
fi

# ── Package-manager selection (per ecosystem, by the lockfile/manifest present) ─────
js_manager="none"
if [ "$has_js" = 1 ]; then
  if [ -f "$DIR/pnpm-lock.yaml" ]; then
    js_manager="pnpm"
  elif [ -f "$DIR/yarn.lock" ]; then
    js_manager="yarn"
  else
    js_manager="npm"
  fi
fi

ruby_manager="none"
[ "$has_ruby" = 1 ] && ruby_manager="bundler"

# Bundler runs as the version Gemfile.lock records, so that is the one that resolves.
BUNDLER_COOLDOWN_MIN="4.0.13"
ruby_bundled_with="none"
ruby_cooldown_enforced="unknown"
if [ "$has_ruby" = 1 ] && [ -f "$DIR/Gemfile.lock" ]; then
  ruby_bundled_with="$(awk '/^BUNDLED WITH/{getline; gsub(/[[:space:]]/, ""); print; exit}' "$DIR/Gemfile.lock")"
  [ -z "$ruby_bundled_with" ] && ruby_bundled_with="none"
fi
if [ "$ruby_bundled_with" != none ]; then
  # Numeric, segment-wise compare (portable: no `sort -V`).
  ruby_cooldown_enforced="$(awk -v a="$ruby_bundled_with" -v b="$BUNDLER_COOLDOWN_MIN" 'BEGIN {
    n = split(a, x, "."); m = split(b, y, "."); k = (n > m ? n : m)
    for (i = 1; i <= k; i++) { if (x[i] + 0 > y[i] + 0) { print 1; exit } if (x[i] + 0 < y[i] + 0) { print 0; exit } }
    print 1 }')"
fi

python_manager="none"
if [ "$has_python" = 1 ]; then
  if [ -f "$DIR/uv.lock" ] || { [ -f "$DIR/pyproject.toml" ] && grep -q '^\[tool\.uv\]' "$DIR/pyproject.toml" 2>/dev/null; }; then
    python_manager="uv"
  elif [ -f "$DIR/poetry.lock" ] || { [ -f "$DIR/pyproject.toml" ] && grep -q '^\[tool\.poetry\]' "$DIR/pyproject.toml" 2>/dev/null; }; then
    python_manager="poetry"
  else
    python_manager="pip"
  fi
fi

ecosystems=""
[ "$has_js" = 1 ] && ecosystems="$ecosystems js"
[ "$has_ruby" = 1 ] && ecosystems="$ecosystems ruby"
[ "$has_python" = 1 ] && ecosystems="$ecosystems python"
[ "$has_actions" = 1 ] && ecosystems="$ecosystems actions"
ecosystems="${ecosystems# }"

# The read-only "what's outdated" command per ecosystem/manager. The skill reads the
# Current/Latest columns: a Latest with a higher leading version segment is a MAJOR
# (own commit, read the changelog); anything else is patch/minor (batched per ecosystem).
js_cmd=""
case "$js_manager" in
  npm) js_cmd="npm outdated" ;;
  pnpm) js_cmd="pnpm outdated" ;;
  yarn) js_cmd="yarn outdated  # Berry: yarn upgrade-interactive" ;;
esac
ruby_cmd=""
[ "$ruby_manager" = bundler ] && ruby_cmd="bundle outdated --strict"
python_cmd=""
case "$python_manager" in
  uv) python_cmd="uv pip list --outdated" ;;
  poetry) python_cmd="poetry show --outdated" ;;
  pip) python_cmd="pip list --outdated" ;;
esac

# ── Output: KEY=VALUE block first (parseable), then human summary ───────────────────
cat <<EOF
has_js=$has_js
has_ruby=$has_ruby
has_python=$has_python
has_actions=$has_actions
js_manager=$js_manager
ruby_manager=$ruby_manager
python_manager=$python_manager
ruby_bundled_with=$ruby_bundled_with
ruby_cooldown_enforced=$ruby_cooldown_enforced
actions_count=$actions_count
ecosystems=$ecosystems
EOF

if [ -z "$ecosystems" ]; then
  echo "# No JavaScript/Ruby/Python/GitHub-Actions dependencies detected in $DIR."
  exit 0
fi

echo "# Ecosystems to upgrade in $DIR: $ecosystems"

# Print (and optionally run) each present ecosystem's read-only outdated command.
report_one() {
  # $1 label, $2 the tool binary, $3 the command string
  local label="$1" tool="$2" cmd="$3"
  [ -z "$cmd" ] && return 0
  echo "# [$label] list outdated:  $cmd"
  if [ "$RUN" = 1 ]; then
    if have "$tool"; then
      (cd "$DIR" && eval "$cmd") || true
    else
      echo "#   ($tool not installed — run the command above once it is)"
    fi
  fi
}

[ "$has_js" = 1 ] && report_one "js/$js_manager" "$js_manager" "$js_cmd"
[ "$has_ruby" = 1 ] && report_one "ruby" "bundle" "$ruby_cmd"
if [ "$ruby_bundled_with" != none ]; then
  echo "# [ruby] Bundler itself: locked at $ruby_bundled_with; a plain bundle update never moves it."
  echo "#   bundle update --bundler=<newest release outside the cooldown>  (see references/ecosystems.md)"
  if [ "$ruby_cooldown_enforced" = 0 ]; then
    echo "#   WARNING: Bundler $ruby_bundled_with ignores the cooldown (needs >= $BUNDLER_COOLDOWN_MIN) —"
    echo "#   bump Bundler FIRST, or every gem resolves to its newest release regardless of age."
  fi
fi
[ "$has_python" = 1 ] && report_one "python/$python_manager" "$python_manager" "$python_cmd"
if [ "$has_actions" = 1 ]; then
  echo "# [actions] $actions_count workflow file(s) — bump pins via the github-actions skill (pinact run -u),"
  echo "#   then verify with skills/dev-env-setup/scripts/check_action_refs.sh .github/workflows"
fi

exit 0

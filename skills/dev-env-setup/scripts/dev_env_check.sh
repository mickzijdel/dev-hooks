#!/bin/bash
# dev-env-setup compliance checker.
#
# Audits a repo against Mick's dev-env standard (mise + hk + CI + gitleaks, stamped
# with DEV_ENV_VERSION in mise.toml). Used by the dev-hooks:dev-env-setup skill (audit)
# and by the dev-env-reminder SessionStart hook (detection).
#
# Usage: dev_env_check.sh [DIR]   (default: $PWD)
#
# Emits machine-readable KEY=VALUE lines on stdout (parsed by the hook), followed by a
# short human-readable summary on lines beginning with "# ". Keys:
#   applicable       1 if the standard applies (recognized stack OR scripts present)
#   has_mise         1 if mise.toml / .mise.toml present
#   has_hk           1 if hk.pkl present
#   has_ci           1 if any .github/workflows/* present
#   has_gitleaks     1 if hk.pkl references gitleaks
#   has_lockfile     1 if mise.lock present (required from standard v2)
#   has_readme       1 if a README (README.md/README/…) is present (required from standard v3)
#   has_claude       1 if CLAUDE.md present (required from standard v3)
#   has_cooldown     1 if the uv dependency cooldown is set (Python: pyproject.toml [tool.uv]
#                    exclude-newer; required from standard v6). Defaults to 1 for non-Python
#                    stacks / repos without pyproject.toml, so it never blocks them.
#   repo_version     DEV_ENV_VERSION from mise.toml, else 0
#   current_version  the standard version shipped by this skill (from ../VERSION)
#   stack            python | ruby | shell | unknown
#   status           not-applicable | needs-setup | needs-upgrade | compliant

set -u

DIR="${1:-$PWD}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
VERSION_FILE="$SCRIPT_DIR/../VERSION"
current_version=0
[ -f "$VERSION_FILE" ] && current_version="$(tr -dc '0-9' <"$VERSION_FILE")"
[ -z "$current_version" ] && current_version=0

# ── Stack detection ──────────────────────────────────────────────────────────────
stack="unknown"
if [ -f "$DIR/pyproject.toml" ] || [ -f "$DIR/setup.py" ] || [ -f "$DIR/setup.cfg" ] || [ -f "$DIR/requirements.txt" ]; then
  stack="python"
elif [ -f "$DIR/Gemfile" ]; then
  stack="ruby"
fi

# ── Applicability: recognized stack, OR scripts present (shell/plugin repos) ─────
applicable=0
[ "$stack" != "unknown" ] && applicable=1
has_scripts=0
if find "$DIR" -path "$DIR/.git" -prune -o -type f \( -name '*.sh' -o -name '*.py' \) -print 2>/dev/null | grep -q .; then
  has_scripts=1
elif [ -d "$DIR/bin" ] && find "$DIR/bin" -type f 2>/dev/null | grep -q .; then
  has_scripts=1
fi
[ "$has_scripts" = 1 ] && applicable=1
# A repo with scripts but no language manifest is a shell/plugin repo.
[ "$stack" = "unknown" ] && [ "$has_scripts" = 1 ] && stack="shell"

# ── Compliance signals ───────────────────────────────────────────────────────────
has_mise=0
MISE_FILE=""
for f in mise.toml .mise.toml mise.local.toml; do
  if [ -f "$DIR/$f" ]; then
    has_mise=1
    MISE_FILE="$DIR/$f"
    break
  fi
done

has_hk=0
[ -f "$DIR/hk.pkl" ] && has_hk=1

has_ci=0
if [ -d "$DIR/.github/workflows" ] && find "$DIR/.github/workflows" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | grep -q .; then
  has_ci=1
fi

has_gitleaks=0
[ "$has_hk" = 1 ] && grep -qi 'gitleaks' "$DIR/hk.pkl" && has_gitleaks=1

has_lockfile=0
{ [ -f "$DIR/mise.lock" ] || [ -f "$DIR/.mise.lock" ]; } && has_lockfile=1

# Project docs (v3): a README (any common form) and a CLAUDE.md at the repo root.
has_readme=0
if find "$DIR" -maxdepth 1 -type f -iname 'readme*' 2>/dev/null | grep -q .; then
  has_readme=1
fi
has_claude=0
if find "$DIR" -maxdepth 1 -type f -iname 'claude.md' 2>/dev/null | grep -q .; then
  has_claude=1
fi

# Dependency cooldown (v6): a Python repo pins the uv cooldown in pyproject.toml
# ([tool.uv] exclude-newer). Default to 1 so non-Python stacks / repos without a
# pyproject.toml are never blocked on this axis (Ruby/JS cooldown is recommended, not gated).
has_cooldown=1
if [ "$stack" = "python" ] && [ -f "$DIR/pyproject.toml" ]; then
  grep -qE '^[[:space:]]*exclude-newer[[:space:]]*=' "$DIR/pyproject.toml" || has_cooldown=0
fi

repo_version=0
if [ -n "$MISE_FILE" ]; then
  v="$(grep -E '^[[:space:]]*DEV_ENV_VERSION[[:space:]]*=' "$MISE_FILE" 2>/dev/null | head -n1 | tr -dc '0-9')"
  [ -n "$v" ] && repo_version="$v"
fi

# ── Status ───────────────────────────────────────────────────────────────────────
if [ "$applicable" = 0 ]; then
  status="not-applicable"
elif [ "$has_hk" = 0 ] || [ "$has_mise" = 0 ] || [ "$has_ci" = 0 ]; then
  status="needs-setup"
elif [ "$has_gitleaks" = 0 ] || [ "$repo_version" -lt "$current_version" ] || { [ "$current_version" -ge 2 ] && [ "$has_lockfile" = 0 ]; } || { [ "$current_version" -ge 3 ] && { [ "$has_readme" = 0 ] || [ "$has_claude" = 0 ]; }; } || { [ "$current_version" -ge 6 ] && [ "$has_cooldown" = 0 ]; }; then
  status="needs-upgrade"
else
  status="compliant"
fi

# ── Output ───────────────────────────────────────────────────────────────────────
cat <<EOF
applicable=$applicable
has_mise=$has_mise
has_hk=$has_hk
has_ci=$has_ci
has_gitleaks=$has_gitleaks
has_lockfile=$has_lockfile
has_readme=$has_readme
has_claude=$has_claude
has_cooldown=$has_cooldown
repo_version=$repo_version
current_version=$current_version
stack=$stack
status=$status
EOF

case "$status" in
  not-applicable) echo "# Not applicable: no recognized stack or scripts in $DIR." ;;
  needs-setup) echo "# Needs setup ($stack): missing mise=$((1 - has_mise)) hk=$((1 - has_hk)) ci=$((1 - has_ci)). Run the dev-hooks:dev-env-setup skill." ;;
  needs-upgrade) echo "# Needs upgrade ($stack): repo v$repo_version < standard v$current_version, or gitleaks missing (has_gitleaks=$has_gitleaks), or mise.lock missing (has_lockfile=$has_lockfile), or project docs missing (has_readme=$has_readme has_claude=$has_claude), or uv cooldown missing (has_cooldown=$has_cooldown). See references/upgrade-guide.md." ;;
  compliant) echo "# Compliant ($stack) at v$repo_version." ;;
esac

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
#   has_gitleaks_config  1 if .gitleaks.toml present at the repo root (required from standard
#                    v10). gitleaks `dir` scans the whole tree with no respect-gitignore flag, so
#                    this allowlist file keeps gitignored artifacts (.env, log/, *.key) from
#                    failing every commit. See references/templates/.gitleaks.toml.
#   has_lockfile     1 if mise.lock present (required from standard v2)
#   has_readme       1 if a README (README.md/README/…) is present (required from standard v3)
#   has_claude       1 if CLAUDE.md present (required from standard v3)
#   has_cooldown     1 if the uv dependency cooldown is set (Python: pyproject.toml [tool.uv]
#                    exclude-newer; required from standard v6). Defaults to 1 for non-Python
#                    stacks / repos without pyproject.toml, so it never blocks them.
#   has_jscpd_runner 1 if scripts/run-jscpd.sh present (required from standard v14 — the
#                    shared jscpd runner both the hk step and CI's audit job call).
#   has_exec_bit     1 if hk.pkl carries the exec-bit-scripts step (required from standard
#                    v15 — fails commits when a tracked shebang script sits at index mode
#                    100644, which would exit 126 on every fresh clone / plugin install).
#   suggests_fnox    1 if the repo has plaintext secrets in use (a non-empty .env/.env.local
#                    with KEY=value lines, a config/credentials/*.key, or source references to
#                    Rails credentials / ENV[…] / Settings.) AND no fnox.toml yet. Advisory only —
#                    nudges the env-to-fnox skill; never affects status.
#   repo_version     DEV_ENV_VERSION from mise.toml, else 0
#   current_version  the standard version shipped by this skill (from ../VERSION)
#   stack            python | ruby | javascript | shell | unknown
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
elif [ -f "$DIR/package.json" ]; then
  stack="javascript"
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

# gitleaks allowlist (v10): gitleaks `dir` scans the whole tree (no respect-gitignore flag), so a
# root .gitleaks.toml is required to keep gitignored artifacts from failing every commit.
has_gitleaks_config=0
[ -f "$DIR/.gitleaks.toml" ] && has_gitleaks_config=1

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

# Shared jscpd runner (v14): the version-cooldown policy lives in scripts/run-jscpd.sh,
# called by both the hk step and CI's audit job so the two gates can't drift.
has_jscpd_runner=0
[ -f "$DIR/scripts/run-jscpd.sh" ] && has_jscpd_runner=1

# Exec-bit gate (v15): hk.pkl carries the exec-bit-scripts step (CI mirrors it), so a
# tracked shebang script can't ship at index mode 100644.
has_exec_bit=0
[ "$has_hk" = 1 ] && grep -q 'exec-bit-scripts' "$DIR/hk.pkl" && has_exec_bit=1

# Plaintext secrets in use, not yet migrated (advisory — nudges env-to-fnox, never gates status).
# Triggers only when there's no fnox.toml and secrets are actually present: a non-empty
# .env/.env.local with a KEY=value line, a Rails master key, or source references to credentials.
suggests_fnox=0
if [ ! -f "$DIR/fnox.toml" ]; then
  for f in .env .env.local; do
    [ -f "$DIR/$f" ] && grep -qE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "$DIR/$f" && suggests_fnox=1
  done
  if [ "$suggests_fnox" = 0 ] && [ -d "$DIR/config/credentials" ] && find "$DIR/config/credentials" -maxdepth 1 -type f -name '*.key' 2>/dev/null | grep -q .; then
    suggests_fnox=1
  fi
  if [ "$suggests_fnox" = 0 ]; then
    # grep -l prints matching filenames; capture them so a partial xargs exit (123) can't lie.
    # Prune VCS / vendored / build-output dirs (by basename, at any depth) so third-party
    # source under .venv/node_modules/vendor doesn't trip the heuristic — only the repo's own
    # code counts. Same dirs the rest of the standard excludes (jscpd `ignore` globs, vulture).
    cred_hit="$(find "$DIR" \( -name .git -o -name .venv -o -name node_modules -o -name vendor -o -name .bundle -o -name dist -o -name build \) -prune -o -type f \( -name '*.rb' -o -name '*.py' -o -name '*.erb' \) -print 2>/dev/null | head -n 500 | xargs -r grep -lE 'Rails\.application\.credentials|ENV\[|Settings\.' 2>/dev/null | head -n1)"
    [ -n "$cred_hit" ] && suggests_fnox=1
  fi
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
elif [ "$has_gitleaks" = 0 ] || [ "$repo_version" -lt "$current_version" ] || { [ "$current_version" -ge 2 ] && [ "$has_lockfile" = 0 ]; } || { [ "$current_version" -ge 3 ] && { [ "$has_readme" = 0 ] || [ "$has_claude" = 0 ]; }; } || { [ "$current_version" -ge 6 ] && [ "$has_cooldown" = 0 ]; } || { [ "$current_version" -ge 10 ] && [ "$has_gitleaks_config" = 0 ]; } || { [ "$current_version" -ge 14 ] && [ "$has_jscpd_runner" = 0 ]; } || { [ "$current_version" -ge 15 ] && [ "$has_exec_bit" = 0 ]; }; then
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
has_gitleaks_config=$has_gitleaks_config
has_lockfile=$has_lockfile
has_readme=$has_readme
has_claude=$has_claude
has_cooldown=$has_cooldown
has_jscpd_runner=$has_jscpd_runner
has_exec_bit=$has_exec_bit
suggests_fnox=$suggests_fnox
repo_version=$repo_version
current_version=$current_version
stack=$stack
status=$status
EOF

case "$status" in
  not-applicable) echo "# Not applicable: no recognized stack or scripts in $DIR." ;;
  needs-setup) echo "# Needs setup ($stack): missing mise=$((1 - has_mise)) hk=$((1 - has_hk)) ci=$((1 - has_ci)). Run the dev-hooks:dev-env-setup skill." ;;
  needs-upgrade) echo "# Needs upgrade ($stack): repo v$repo_version < standard v$current_version, or gitleaks missing (has_gitleaks=$has_gitleaks), or .gitleaks.toml missing (has_gitleaks_config=$has_gitleaks_config), or mise.lock missing (has_lockfile=$has_lockfile), or project docs missing (has_readme=$has_readme has_claude=$has_claude), or uv cooldown missing (has_cooldown=$has_cooldown), or scripts/run-jscpd.sh missing (has_jscpd_runner=$has_jscpd_runner), or exec-bit gate missing (has_exec_bit=$has_exec_bit). See references/upgrade-guide.md." ;;
  compliant) echo "# Compliant ($stack) at v$repo_version." ;;
esac

if [ "$suggests_fnox" = 1 ]; then
  echo "# Advisory: plaintext secrets detected and no fnox.toml — consider the env-to-fnox skill to migrate them out of the repo."
fi

exit 0

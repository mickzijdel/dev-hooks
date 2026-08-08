#!/bin/bash
# dev-env-setup compliance checker.
#
# Audits a repo against the dev-env standard (mise + hk + CI + gitleaks, stamped
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
#   has_version_sync 1 if scripts/check_version_sync.sh present (required from standard v23 — the
#                    shared pin-agreement gate both the hk `versions` step and CI's `versions`
#                    job call: mise.toml, the .<lang>-version files, the Dockerfile ARGs and the
#                    compose/deploy `image:` tags must all name the same versions).
#   has_exec_bit     1 if hk.pkl carries the exec-bit-scripts step (required from standard
#                    v15 — fails commits when a tracked shebang script sits at index mode
#                    100644, which would exit 126 on every fresh clone / plugin install).
#   has_sha_pinned_ci  1 if every remote `uses: owner/repo@ref` in .github/workflows is pinned
#                    to a full commit SHA (required from standard v16 — tags are mutable, so a
#                    compromised action can repoint them; see the github-actions skill). 1 when
#                    CI has no remote action refs.
#   has_zizmor       1 if hk.pkl references the zizmor step (required from standard v18 — the
#                    GitHub Actions security static analysis the github-actions skill enforces;
#                    mirrors has_gitleaks's hk.pkl probe).
#   has_actionlint   1 if hk.pkl references the actionlint step (required from standard v18 — the
#                    GitHub Actions workflow correctness linter; mirrors has_zizmor's hk.pkl probe).
#   suggests_fnox    1 if the repo has plaintext secrets in use (a non-empty .env/.env.local
#                    with KEY=value lines, a config/credentials/*.key, or source references to
#                    Rails credentials / ENV[…] / Settings.) AND no fnox.toml yet. Advisory only —
#                    nudges the env-to-fnox skill; never affects status.
#   has_devcontainer 1 if a .devcontainer/ exists (carries a devcontainer.json, a compose file,
#                    or a Dockerfile). The dev container is recommended from v19 but advisory —
#                    its absence never affects status.
#   devcontainer_mise_driven  1 unless a .devcontainer/ exists and its build files (Dockerfile* +
#                    setup scripts, comment lines stripped) show drift from the mise toolchain: a
#                    hardcoded language base (FROM ruby:/node:/python:/golang:/rust:), a nodesource
#                    apt repo, a single-line `apt-get install … nodejs`, `npm install -g pnpm`, or
#                    no reference to mise at all. Base-OS-vs-prod mismatch is best-effort: flagged
#                    only when BOTH the devcontainer base AND a root ./Dockerfile name a Debian
#                    codename directly (debian:<codename>) and they differ — a `ruby:X-slim`-style
#                    prod base isn't mappable to a codename here, so it can't be flagged. Advisory
#                    only (mirrors suggests_fnox); never affects status.
#   repo_version     DEV_ENV_VERSION from mise.toml, else 0
#   current_version  the standard version shipped by this skill (from ../VERSION)
#   stack            python | ruby | javascript | go | shell | unknown
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
elif [ -f "$DIR/go.mod" ]; then
  stack="go"
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

# Shared version-sync gate (v23): the pin-agreement check lives in scripts/check_version_sync.sh,
# called by both the hk `versions` step and CI's `versions` job so the two gates can't drift.
has_version_sync=0
[ -f "$DIR/scripts/check_version_sync.sh" ] && has_version_sync=1

# Exec-bit gate (v15): hk.pkl carries the exec-bit-scripts step (CI mirrors it), so a
# tracked shebang script can't ship at index mode 100644.
has_exec_bit=0
[ "$has_hk" = 1 ] && grep -q 'exec-bit-scripts' "$DIR/hk.pkl" && has_exec_bit=1

# SHA-pinned actions (v16): every remote `uses: owner/repo@ref` in a workflow must pin a full
# commit SHA (7–40 hex), not a mutable tag/branch. Skips local (`./…`) and docker (`docker://…`)
# uses, which have no remote ref. Defaults to 1 when CI carries no remote action refs. Counts
# total vs SHA-pinned refs with grep -E (whose interval `{7,40}` works everywhere — awk's does
# not under mawk), so any non-SHA ref drops the count and flips the signal.
has_sha_pinned_ci=1
if [ "$has_ci" = 1 ]; then
  refs="$(grep -rhoE 'uses:[[:space:]]*["'"'"']?[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[^[:space:]"'"'"']+' "$DIR"/.github/workflows/*.y*ml 2>/dev/null |
    sed -E 's/^uses:[[:space:]]*["'"'"']?//')"
  total="$(printf '%s' "$refs" | grep -c '@')"
  pinned="$(printf '%s' "$refs" | grep -cE '@[0-9a-fA-F]{7,40}$')"
  [ "$total" -ne "$pinned" ] && has_sha_pinned_ci=0
fi

# GitHub Actions security scan (v18): hk.pkl carries the zizmor step (CI mirrors it with the
# actions-security job), so every workflow + action.yml is statically scanned for the
# vulnerabilities SHA-pinning doesn't cover. Mirrors has_gitleaks's hk.pkl probe.
has_zizmor=0
[ "$has_hk" = 1 ] && grep -qi 'zizmor' "$DIR/hk.pkl" && has_zizmor=1

# GitHub Actions workflow correctness linter (v18): hk.pkl carries the actionlint step (CI mirrors
# it in the actions-lint job). Mirrors has_zizmor's hk.pkl probe.
has_actionlint=0
[ "$has_hk" = 1 ] && grep -qi 'actionlint' "$DIR/hk.pkl" && has_actionlint=1

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

# Dev container drift (advisory — recommended from v19, never affects status). A mise-driven
# devcontainer installs only mise + OS libs and lets `mise install` provision the toolchain from
# the bind-mounted mise.toml/mise.lock; it pins no language versions itself. Only evaluated when a
# .devcontainer/ exists; the build files are comment-stripped before scanning so the template's
# own cautionary comments (e.g. "do NOT add `apt-get install nodejs`", "no `npm install -g pnpm`")
# don't self-flag.
has_devcontainer=0
devcontainer_mise_driven=1
devcontainer_drift=""
DC="$DIR/.devcontainer"
if [ -d "$DC" ] && { [ -f "$DC/devcontainer.json" ] || find "$DC" -maxdepth 1 -type f \( -name 'compose.y*ml' -o -name 'docker-compose.y*ml' -o -name 'Dockerfile*' \) 2>/dev/null | grep -q .; }; then
  has_devcontainer=1
fi
if [ "$has_devcontainer" = 1 ]; then
  # Real build instructions only (Dockerfile* + setup scripts), comment lines stripped.
  dc_scan="$(find "$DC" -maxdepth 1 -type f \( -name 'Dockerfile*' -o -name '*.sh' \) -exec cat {} + 2>/dev/null | grep -vE '^[[:space:]]*#')"
  if [ -n "$dc_scan" ]; then
    printf '%s\n' "$dc_scan" | grep -qiE '^[[:space:]]*FROM[[:space:]]+(ruby|node|python|golang|rust):' && devcontainer_drift="$devcontainer_drift hardcoded-language-base"
    printf '%s\n' "$dc_scan" | grep -qiE 'deb\.nodesource\.com|setup_[0-9]+\.x' && devcontainer_drift="$devcontainer_drift nodesource"
    printf '%s\n' "$dc_scan" | grep -qiE 'apt-get[[:space:]]+install.*[[:space:]]nodejs([[:space:]]|$)' && devcontainer_drift="$devcontainer_drift hardcoded-nodejs"
    printf '%s\n' "$dc_scan" | grep -qiE 'npm[[:space:]]+(install|i)[[:space:]]+-g[[:space:]]+pnpm' && devcontainer_drift="$devcontainer_drift global-pnpm"
    printf '%s\n' "$dc_scan" | grep -qi 'mise' || devcontainer_drift="$devcontainer_drift not-mise-driven"
    # Best-effort base-OS-vs-prod: only when both name a Debian codename directly (debian:<name>).
    dc_codename="$(printf '%s\n' "$dc_scan" | grep -oiE 'FROM[[:space:]]+debian:[a-z0-9.]+' | head -n1 | sed -E 's/.*[Dd]ebian://')"
    if [ -f "$DIR/Dockerfile" ]; then
      prod_codename="$(grep -vE '^[[:space:]]*#' "$DIR/Dockerfile" | grep -oiE 'FROM[[:space:]]+debian:[a-z0-9.]+' | head -n1 | sed -E 's/.*[Dd]ebian://')"
      [ -n "$dc_codename" ] && [ -n "$prod_codename" ] && [ "$dc_codename" != "$prod_codename" ] && devcontainer_drift="$devcontainer_drift base-os-mismatch($dc_codename!=$prod_codename)"
    fi
    [ -n "$devcontainer_drift" ] && devcontainer_mise_driven=0
  fi
fi
devcontainer_drift="${devcontainer_drift# }"

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
elif [ "$has_gitleaks" = 0 ] || [ "$repo_version" -lt "$current_version" ] || { [ "$current_version" -ge 2 ] && [ "$has_lockfile" = 0 ]; } || { [ "$current_version" -ge 3 ] && { [ "$has_readme" = 0 ] || [ "$has_claude" = 0 ]; }; } || { [ "$current_version" -ge 6 ] && [ "$has_cooldown" = 0 ]; } || { [ "$current_version" -ge 10 ] && [ "$has_gitleaks_config" = 0 ]; } || { [ "$current_version" -ge 14 ] && [ "$has_jscpd_runner" = 0 ]; } || { [ "$current_version" -ge 15 ] && [ "$has_exec_bit" = 0 ]; } || { [ "$current_version" -ge 16 ] && [ "$has_sha_pinned_ci" = 0 ]; } || { [ "$current_version" -ge 18 ] && [ "$has_zizmor" = 0 ]; } || { [ "$current_version" -ge 18 ] && [ "$has_actionlint" = 0 ]; } || { [ "$current_version" -ge 23 ] && [ "$has_version_sync" = 0 ]; }; then
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
has_version_sync=$has_version_sync
has_exec_bit=$has_exec_bit
has_sha_pinned_ci=$has_sha_pinned_ci
has_zizmor=$has_zizmor
has_actionlint=$has_actionlint
suggests_fnox=$suggests_fnox
has_devcontainer=$has_devcontainer
devcontainer_mise_driven=$devcontainer_mise_driven
repo_version=$repo_version
current_version=$current_version
stack=$stack
status=$status
EOF

case "$status" in
  not-applicable) echo "# Not applicable: no recognized stack or scripts in $DIR." ;;
  needs-setup) echo "# Needs setup ($stack): missing mise=$((1 - has_mise)) hk=$((1 - has_hk)) ci=$((1 - has_ci)). Run the dev-hooks:dev-env-setup skill." ;;
  needs-upgrade) echo "# Needs upgrade ($stack): repo v$repo_version < standard v$current_version, or gitleaks missing (has_gitleaks=$has_gitleaks), or .gitleaks.toml missing (has_gitleaks_config=$has_gitleaks_config), or mise.lock missing (has_lockfile=$has_lockfile), or project docs missing (has_readme=$has_readme has_claude=$has_claude), or uv cooldown missing (has_cooldown=$has_cooldown), or scripts/run-jscpd.sh missing (has_jscpd_runner=$has_jscpd_runner), or scripts/check_version_sync.sh missing (has_version_sync=$has_version_sync), or exec-bit gate missing (has_exec_bit=$has_exec_bit), or actions not SHA-pinned (has_sha_pinned_ci=$has_sha_pinned_ci), or zizmor missing (has_zizmor=$has_zizmor), or actionlint missing (has_actionlint=$has_actionlint). See references/upgrade-guide.md." ;;
  compliant) echo "# Compliant ($stack) at v$repo_version." ;;
esac

if [ "$suggests_fnox" = 1 ]; then
  echo "# Advisory: plaintext secrets detected and no fnox.toml — consider the env-to-fnox skill to migrate them out of the repo."
fi

if [ "$has_devcontainer" = 1 ] && [ "$devcontainer_mise_driven" = 0 ]; then
  echo "# Advisory: .devcontainer/ has drifted from the mise toolchain ($devcontainer_drift) — a mise-driven devcontainer installs only mise + OS libs and lets 'mise install' provision the toolchain. See the 'Dev container' section in references/standard.md."
fi

exit 0

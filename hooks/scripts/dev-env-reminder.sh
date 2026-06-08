#!/bin/bash
# SessionStart hook: if this looks like Mick's repo, the dev-env standard applies, and the
# repo doesn't meet it (missing mise/hk/CI/gitleaks, or behind the version stamp), nudge
# Claude to flag the gap and offer to run the dev-hooks:dev-env-setup skill. Advisory only —
# it never edits anything. SessionStart fires once per session, so no sentinel is needed.
#
# Gates (any failure → silent exit 0):
#   1. git repo
#   2. not opted out (env override DEV_HOOKS_DEVENV_OWNED=false, or `dev-env: skip` in CLAUDE.md)
#   3. owned by Mick (override =true, OR origin owner in allowlist, OR >=80% of last-month commits)
#   4. applicable + non-compliant per scripts/dev_env_check.sh
#
# Tunables (env): DEV_HOOKS_DEVENV_OWNED (true/false), DEV_HOOKS_DEVENV_OWNERS (extra GitHub
# owners, space/comma separated), DEV_HOOKS_DEVENV_EMAIL (default mickzijdel@live.nl).

# Resolve the plugin root from the script's own location BEFORE we cd into the target repo
# (a relative $0 would otherwise resolve against the wrong directory).
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SELF_DIR/../.." && pwd)}"

INPUT=$(cat 2>/dev/null)
DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$DIR" ] && DIR="$PWD"

cd "$DIR" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# ── Gate 2: opt-out ──────────────────────────────────────────────────────────────
OVERRIDE="${DEV_HOOKS_DEVENV_OWNED:-}"
case "$OVERRIDE" in
  false | 0 | no | FALSE | False) exit 0 ;;
esac
for f in CLAUDE.md .claude/CLAUDE.md; do
  [ -f "$DIR/$f" ] && grep -qiE '(^|[[:space:]<!-]*)dev-env:[[:space:]]*skip' "$DIR/$f" && exit 0
done

# ── Gate 3: ownership ────────────────────────────────────────────────────────────
is_owned() {
  case "$OVERRIDE" in
    true | 1 | yes | TRUE | True) return 0 ;;
  esac

  # Owner allowlist (default: mickzijdel; extend via DEV_HOOKS_DEVENV_OWNERS).
  local owners="mickzijdel ${DEV_HOOKS_DEVENV_OWNERS:-}"
  owners="${owners//,/ }"
  local remote owner
  remote=$(git config --get remote.origin.url 2>/dev/null)
  if [ -n "$remote" ]; then
    owner=$(printf '%s' "$remote" | sed -E 's#\.git$##; s#^.*[:/]([^/]+)/[^/]+$#\1#')
    for o in $owners; do
      [ "$owner" = "$o" ] && return 0
    done
  fi

  # Commit-share heuristic: >=80% of last-month commits are mine.
  local email="${DEV_HOOKS_DEVENV_EMAIL:-mickzijdel@live.nl}"
  local total mine
  total=$(git log --since="1 month ago" --pretty=%ae 2>/dev/null | grep -c . )
  if [ "${total:-0}" -gt 0 ]; then
    mine=$(git log --since="1 month ago" --pretty=%ae 2>/dev/null | grep -cFx "$email")
    [ $((mine * 100)) -ge $((total * 80)) ] && return 0
  fi
  return 1
}
is_owned || exit 0

# ── Gate 4: applicable + non-compliant ───────────────────────────────────────────
CHECKER="$ROOT/skills/dev-env-setup/scripts/dev_env_check.sh"
[ -f "$CHECKER" ] || exit 0

applicable=0 status="" repo_version=0 current_version=0
eval "$(bash "$CHECKER" "$DIR" 2>/dev/null | grep -E '^(applicable|status|repo_version|current_version)=')"

[ "$applicable" = 1 ] || exit 0

NAME="${DIR##*/}"
case "$status" in
  needs-setup)
    MSG="[dev-env] This looks like your repo (${NAME}) and it's missing your standard dev-env setup (mise + hk pre-commit + CI + gitleaks). Flag this to Mick and offer to run the dev-hooks:dev-env-setup skill to set it up. Do NOT set it up silently — it writes commit-tracked config. If this repo should be exempt, set DEV_HOOKS_DEVENV_OWNED=false in .claude/settings.local.json or add a 'dev-env: skip' line to its CLAUDE.md."
    ;;
  needs-upgrade)
    MSG="[dev-env] This looks like your repo (${NAME}); it has a dev-env setup but is behind the current standard (repo v${repo_version} < v${current_version}, or gitleaks is missing). Flag this to Mick and offer to run the dev-hooks:dev-env-setup skill to upgrade it (it applies references/upgrade-guide.md and re-stamps DEV_ENV_VERSION)."
    ;;
  *)
    exit 0
    ;;
esac

jq -cn --arg msg "$MSG" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $msg}}'
exit 0

#!/bin/bash
# PostToolUse(Write|Edit): when Claude writes a Dockerfile/Containerfile, lint it with
# hadolint and report the findings back to Claude. Advisory only — emits additionalContext
# and always exits 0, never blocks the write (Claude decides whether to fix).
#
# - hadolint installed: run it on the file EVERY time and report the results (pass or the
#   exact findings), plus a one-line layer-ordering nudge.
# - hadolint missing: fall back to a layer-ordering/gotchas reminder (once per session) and
#   suggest installing hadolint.
#
# Opt out per repo/user with DEV_HOOKS_DOCKERFILE=false (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
# Sets INPUT, FILE, SESSION, BASE (or exits 0 on opt-out / missing file_path).
reminder_init DEV_HOOKS_DOCKERFILE

# Match Dockerfiles by basename: Dockerfile, Dockerfile.prod, app.dockerfile, Containerfile.
case "$BASE" in
  Dockerfile | Dockerfile.* | *.Dockerfile | *.dockerfile | Containerfile | Containerfile.*) ;;
  *) exit 0 ;;
esac

ORDERING="Order instructions least- to most-frequently-changed for cache reuse: base image -> system packages -> dependency manifests (COPY package.json/Gemfile/requirements.txt) -> RUN install -> THEN COPY . . (source) -> build -> CMD. See the \`dockerfile\` skill for the full gotchas list (pinning, multi-stage, .dockerignore, non-root USER, exec-form CMD)."

emit() {
  jq -cn --arg msg "$1" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
  exit 0
}

# --- hadolint present + file on disk: lint every time and report the results ------------
if command -v hadolint >/dev/null 2>&1; then
  if [ -f "$FILE" ]; then
    OUT=$(hadolint "$FILE" 2>&1)
    if [ -z "$OUT" ]; then
      emit "hadolint passed clean on $BASE. $ORDERING"
    else
      emit "hadolint found issues in $BASE — review and fix before finalizing:"$'\n'"$OUT"$'\n\n'"$ORDERING"
    fi
  fi
  # hadolint present but file not on disk (rare): no install hint, just the reminder below.
  HADOLINT_HINT=""
else
  HADOLINT_HINT=" (hadolint is not installed — install it to lint Dockerfiles automatically: https://github.com/hadolint/hadolint)"
fi

# --- fall back to a once-per-session reminder ------------------------------------------
MARKER_DIR="${TMPDIR:-/tmp}/dev-hooks-dockerfile"
mkdir -p "$MARKER_DIR" 2>/dev/null
MARKER="$MARKER_DIR/${SESSION}"
[ -e "$MARKER" ] && exit 0
: >"$MARKER" 2>/dev/null

emit "You just wrote $BASE. $ORDERING$HADOLINT_HINT"

#!/bin/bash
# PostToolUse(Write|Edit): when Claude writes/edits a GitHub Actions workflow (a YAML file
# pinning `uses: owner/repo@ref`), remind it to verify every action ref actually resolves
# on the remote — the floating-major trap (`@v8` when only `@v1`…`@v7` are published) only
# surfaces when CI runs, so catch it locally first.
#
# Reminder-only by design: the hook does NOT hit the network. It points Claude at the
# bundled `check_action_refs.sh`, which does the actual `git ls-remote` resolution; Claude
# runs it. (Same split as latest-deps-reminder: the hook nudges, the tool checks.)
#
# Opt out per repo/user with DEV_HOOKS_CI_ACTION_REFS=false (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
# Sets INPUT, FILE, SESSION, BASE (or exits 0 on opt-out / missing file_path).
reminder_init DEV_HOOKS_CI_ACTION_REFS

# Only YAML files, and only those that actually pin a remote action (`uses: owner/repo@ref`).
# Content-matched so it covers real workflows AND the dev-env CI templates, and stays silent
# on unrelated YAML.
case "$BASE" in
  *.yml | *.yaml) ;;
  *) exit 0 ;;
esac
[ -f "$FILE" ] || exit 0
grep -qE 'uses:[[:space:]]*["'"'"']?[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@' "$FILE" || exit 0

# Fire at most once per (session x file) so repeated edits don't re-nag.
MARKER_DIR="${TMPDIR:-/tmp}/dev-hooks-ci-action-refs"
mkdir -p "$MARKER_DIR" 2>/dev/null
MARKER="$MARKER_DIR/${SESSION}-$(printf '%s' "$FILE" | cksum | cut -d' ' -f1)"
[ -e "$MARKER" ] && exit 0
: >"$MARKER" 2>/dev/null

# Absolute path to the bundled checker (CLAUDE_PLUGIN_ROOT when the plugin sets it, else
# derive from this script's location).
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SELF_DIR/../.." && pwd)}/skills/dev-env-setup/scripts/check_action_refs.sh"

MSG="You edited $BASE, which pins GitHub Actions with \`uses: owner/repo@ref\`. Verify every ref actually resolves on the remote before finishing — an action can ship release tags (v8.0.0, v8.1.0) without floating a \`@v8\` major tag, so a wrong pin looks fine locally but breaks CI at \"Prepare all required actions\". Run: \`bash \"$SCRIPT\" \"$FILE\"\` (exits non-zero and lists any unresolved refs). Fix FAILs by pinning a ref that exists (often the exact release tag, e.g. @v8.2.0)."

jq -cn --arg msg "$MSG" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
exit 0

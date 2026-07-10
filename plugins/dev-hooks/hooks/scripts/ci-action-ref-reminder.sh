#!/bin/bash
# bet: none (L5 — points at Mick's post-cutoff SHA-pin-with-version-comment standard)
# sunset: never (personal standard)
# PostToolUse(Write|Edit): when Claude writes/edits a GitHub Actions workflow (a YAML file
# pinning `uses: owner/repo@ref`), point it at the `github-actions` skill (supply-chain
# security checklist — SHA-pin actions, read-only token, no untrusted input in `run:`) and
# remind it to verify every pin with `check_action_refs.sh` before finishing.
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
reminder_fire_once ci-action-refs "$(printf '%s' "$FILE" | cksum | cut -d' ' -f1)" || exit 0

# Absolute path to the bundled checker (CLAUDE_PLUGIN_ROOT when the plugin sets it, else
# derive from this script's location).
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SELF_DIR/../.." && pwd)}/skills/dev-env-setup/scripts/check_action_refs.sh"

MSG="You edited $BASE, a GitHub Actions workflow. Apply the \`github-actions\` skill's security checklist — most importantly SHA-pin every \`uses:\` to a full commit SHA with the tag in a trailing comment (\`owner/repo@<sha> # vX.Y.Z\`; mutable tags are the tj-actions/Trivy supply-chain vector), default the workflow's \`GITHUB_TOKEN\` to read-only (\`permissions: { contents: read }\`), and never interpolate \`\${{ github.* }}\` straight into \`run:\`. Then verify the pins: \`bash \"$SCRIPT\" \"$FILE\"\` — it resolves each pin's \`# vX.Y.Z\` comment on the remote and FAILs on a missing tag, a SHA that doesn't match its comment, or a ref left as a mutable tag."

reminder_emit "$MSG"

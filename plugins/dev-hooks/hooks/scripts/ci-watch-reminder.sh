#!/bin/bash
# PostToolUse(Bash) hook: after a `git push`, remind Claude to watch the CI run to
# completion (or background the watch / schedule a check-in if it has more work) so a red
# pipeline comes back to it instead of going unnoticed. Advisory only — never blocks.
#
# Fires only when the command actually ran a `git push` AND the repo has GitHub Actions
# workflows (there is a run to watch). It only nudges — Claude picks the mechanism and runs
# `gh run watch`; the hook itself hits nothing.
#
# First PostToolUse(Bash) consumer, so — like prompt-log.sh for UserPromptSubmit — it reads
# `.tool_input.command` / `.cwd` inline rather than through a lib init helper. Promote a
# `reminder_post_bash_init` to reminder-common.sh when a second PostToolUse(Bash) hook lands.
#
# Opt out per repo/user with DEV_HOOKS_CI_WATCH=false (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
reminder_opt_out DEV_HOOKS_CI_WATCH

INPUT=$(cat 2>/dev/null)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only a real `git push` invocation: `git` (optionally env-prefixed / flagged) walking tokens
# to a `push` subcommand — matches `git push`, `git push origin main`, `git -C dir push`, and
# `… && git push`, while skipping `git config …pushurl`, `git switch`, and `git pushall`.
printf '%s' "$COMMAND" |
  grep -Eq '(^|[^[:alnum:]_])git([[:space:]]+[^[:space:]]+)*[[:space:]]+push([^[:alnum:]_]|$)' || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
[ -z "$CWD" ] && CWD=$PWD

# Only nudge when there's actually a GitHub Actions run to watch.
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
shopt -s nullglob
workflows=("$ROOT"/.github/workflows/*.yml "$ROOT"/.github/workflows/*.yaml)
[ ${#workflows[@]} -gt 0 ] || exit 0

reminder_emit "You just pushed — watch its CI run so a red pipeline comes back to you instead of going unnoticed. Idle now? Watch it to completion (\`gh run watch --exit-status\` on the run this push triggered) and fix any failure with full context. More work queued? Start that watch in the background so you're pinged when it finishes, then keep going — don't push and forget the run. (Optional: hand the watch to a background sub-agent if you want failure-triage running in parallel.)"

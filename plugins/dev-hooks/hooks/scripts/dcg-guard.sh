#!/bin/bash
# bet: none (L4 — consent boundary on destructive commands, delegated to dcg's rule packs)
# sunset: never (safety)
# PreToolUse(Bash): run destructive_command_guard (`dcg`,
# https://github.com/Dicklesworthstone/destructive_command_guard) on the command when the
# binary is installed, so installing this plugin is enough to get its protection without
# a hand-written hook in ~/.claude/settings.json on each machine.
#
# dcg covers the risky-but-legitimate layer that dangerous-command-guard.sh deliberately
# leaves alone — `DROP`/`TRUNCATE` in Postgres, `gcloud … delete`, `docker compose down -v`
# and the rest — through packs chosen in ~/.config/dcg/config.toml. The two stay separate:
# that guard keeps the catastrophic few and the secret-printing check, dcg owns the rest.
#
# dcg's verdict is re-emitted through reminder_emit_decision so the fire is logged like any
# other guard's; only `deny` and `ask` are relayed, never `allow`. dcg fails open on its own
# (set DCG_FAIL_CLOSED=1 to change that), so this hook does too: no dcg on PATH, or a dcg
# that exits oddly, lets the command through to the normal permission flow.
#
# dcg runs with DCG_NO_SELF_HEAL=1: its self-heal (on by default) re-adds dcg's own hook to
# ~/.claude/settings.json on every run, and every command would then be checked twice.
# Running `dcg install` adds that second copy anyway; drop the settings.json entry, or opt out
# of this one with DEV_HOOKS_DCG=false (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
reminder_opt_out DEV_HOOKS_DCG
DCG=$(command -v dcg) || exit 0
# Sets INPUT, COMMAND, CWD, SESSION (or exits 0 when there is no command).
reminder_pre_init DEV_HOOKS_DCG

OUT=$(printf '%s' "$INPUT" | DCG_NO_SELF_HEAL=1 "$DCG")
rc=$?
[ "$rc" -eq 0 ] || exit "$rc"
[ -n "$OUT" ] || exit 0

# Only a verdict reaches here, so the two jq spawns cost nothing on the common path.
VERDICT='[.[]? | objects | select(.permissionDecision)][0] // {}'
DECISION=$(printf '%s' "$OUT" | jq -r "$VERDICT | .permissionDecision // \"\"" 2>/dev/null)
case "$DECISION" in
  deny | ask)
    REASON=$(printf '%s' "$OUT" | jq -r "$VERDICT | .permissionDecisionReason // \"\"")
    reminder_emit_decision "$DECISION" "${REASON:-Blocked by dcg}"
    ;;
esac
exit 0

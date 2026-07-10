#!/bin/bash
# bet: none (L2 — data capture feeding the weekly automation-review meta-loop)
# sunset: never (data capture, not a capability gap)
# UserPromptSubmit hook: append one JSONL line per user prompt to the global
# automation-review log, so thinking-tools' weekly-automation-review can cluster
# repeated requests across repos and suggest what to automate. Local-only —
# nothing leaves the machine.
#
# CRITICAL: on exit 0 a UserPromptSubmit hook's stdout is injected into Claude's
# context (unlike PostToolUse, where plain stdout is shown to the user). So this
# hook NEVER prints — all writes go to the log file, every command's stderr is
# discarded, and it always exits 0 so it can never block or pollute a prompt.
#
# Opt out per repo/user with DEV_HOOKS_PROMPT_LOG=false (in .claude settings env).
# Rotation threshold: DEV_HOOKS_PROMPT_LOG_MAX_BYTES (default 10 MiB; one .1 kept).

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
reminder_opt_out DEV_HOOKS_PROMPT_LOG

INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

# One jq spawn: validate JSON, require a non-empty prompt, build the log line.
# `// ""` fallbacks mean any payload-schema drift degrades to a silent no-op.
LINE=$(printf '%s' "$INPUT" | jq -c --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  (.prompt // "") as $p | select($p != "")
  | {ts: $ts, cwd: (.cwd // ""), session_id: (.session_id // "nosession"),
     len: ($p | length), prompt: ($p[0:500])}' 2>/dev/null)
[ -z "$LINE" ] && exit 0

DIR="$HOME/.claude/automation-review"
LOG="$DIR/prompts.jsonl"
mkdir -p "$DIR" 2>/dev/null || exit 0

# Size-guard rotation: one generation kept, total bounded at ~2× the cap.
MAX=${DEV_HOOKS_PROMPT_LOG_MAX_BYTES:-10485760}
if [ -f "$LOG" ] && [ "$(wc -c <"$LOG" 2>/dev/null || echo 0)" -gt "$MAX" ]; then
  mv -f "$LOG" "$LOG.1" 2>/dev/null
fi

printf '%s\n' "$LINE" >>"$LOG" 2>/dev/null
exit 0

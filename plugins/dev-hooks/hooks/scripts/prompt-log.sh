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
# Credential-shaped values are redacted before the line is written (reminder_redact_secrets
# in the lib): tokens get pasted into prompts mid-incident, and this hook is the one place in
# the suite whose job is to persist user text. `len` stays the PRE-redaction length so
# prompt-size signals remain comparable across the log. The file is created 0600.
#
# Opt out per repo/user with DEV_HOOKS_PROMPT_LOG=false (in .claude settings env).
# Rotation threshold: DEV_HOOKS_PROMPT_LOG_MAX_BYTES (default 10 MiB; one .1 kept).

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
# Shared UserPromptSubmit preamble: opt-out (DEV_HOOKS_PROMPT_LOG), read stdin, require a
# non-empty .prompt, and set INPUT/PROMPT/CWD/SESSION. Silent no-op on drift/empty.
reminder_prompt_init DEV_HOOKS_PROMPT_LOG

# Strip credential-shaped values before anything is written. Redact first, truncate after,
# so a token near the 500-char boundary can't survive as a fragment.
reminder_redact_secrets "$PROMPT"
SAFE=$REPLY

# Build the log line from the extracted fields; jq handles JSON-escaping and truncation.
LINE=$(jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg cwd "$CWD" --arg sid "$SESSION" --arg p "$SAFE" --argjson len "${#PROMPT}" \
  '{ts: $ts, cwd: $cwd, session_id: $sid, len: $len, prompt: ($p[0:500])}' 2>/dev/null)
[ -z "$LINE" ] && exit 0

DIR="$HOME/.claude/automation-review"
LOG="$DIR/prompts.jsonl"
mkdir -p "$DIR" 2>/dev/null || exit 0

# Owner-only: the log holds verbatim prompt text, so it should never be world-readable even
# after redaction. Create it before the append so the mode is right from the first line.
[ -f "$LOG" ] || : >>"$LOG" 2>/dev/null
chmod 600 "$LOG" 2>/dev/null

# Size-guard rotation: one generation kept, total bounded at ~2× the cap.
MAX=${DEV_HOOKS_PROMPT_LOG_MAX_BYTES:-10485760}
if [ -f "$LOG" ] && [ "$(wc -c <"$LOG" 2>/dev/null || echo 0)" -gt "$MAX" ]; then
  mv -f "$LOG" "$LOG.1" 2>/dev/null
  chmod 600 "$LOG.1" 2>/dev/null
  : >>"$LOG" 2>/dev/null
  chmod 600 "$LOG" 2>/dev/null
fi

printf '%s\n' "$LINE" >>"$LOG" 2>/dev/null
exit 0

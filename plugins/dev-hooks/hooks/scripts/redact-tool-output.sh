#!/bin/bash
# bet: none (L5 — output-side half of the secret guard: a command guard cannot see what a
#   file, an API, a script's print or an MCP call will return)
# sunset: never (safety)
# PostToolUse(every tool): mask credential-shaped values (reminder_redact_secrets' rules) in
# the tool result before Claude sees it, string by string, keeping the result's shape.
# Claude Code keeps the original output when a PostToolUse hook fails, so when masking
# cannot run every string is withheld instead. Images are left alone.
#
# Opt out with DEV_HOOKS_REDACT_OUTPUT=false in settings env.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

reminder_opt_out DEV_HOOKS_REDACT_OUTPUT
INPUT=$(cat 2>/dev/null)
printf '%s' "$INPUT" | grep -Eq "$REMINDER_SECRET_HINT_RE" || exit 0
reminder_cwd_session

reminder_mktemp
RESPONSE=$REPLY
printf '%s' "$INPUT" | jq '.tool_response // empty' >"$RESPONSE" 2>/dev/null || exit 0
[ -s "$RESPONSE" ] || exit 0
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)

# Every string outside an image block, in path order, joined by a record separator on a
# line of its own (so a private-key rule, which replaces whole lines, never eats one) and
# closed by a unit separator (command substitution would strip a trailing newline). The
# masked text is split back on them, so a changed count (or a string that holds either
# byte itself) withholds rather than misplacing a string.
# shellcheck disable=SC2016  # jq programs, not shell expansions
DEFS='def text_paths: . as $r | [paths(strings)] | map(. as $p | select(
  [range(0; $p | length) as $i | $r | getpath($p[:$i]) | objects | select(.type == "image")]
  | length == 0));'
reminder_mktemp
MASKED=$REPLY
if TEXT=$(jq -j "$DEFS"' . as $r | text_paths | map(. as $p | $r | getpath($p))
    | join("\n\u001e\n") + "\n\u001f"' "$RESPONSE" 2>/dev/null) &&
  reminder_redact_secrets "$TEXT" && [ "${REPLY: -1}" = $'\037' ] &&
  [ "$(printf '%s' "$REPLY" | tr -cd '\036\037' | wc -c)" = "$(printf '%s' "$TEXT" | tr -cd '\036\037' | wc -c)" ] &&
  jq --arg m "${REPLY%$'\n\037'}" "$DEFS"' . as $r | ($m | split("\n\u001e\n")) as $v
    | reduce (text_paths | to_entries[]) as $e ($r; setpath($e.value; $v[$e.key]))' \
    "$RESPONSE" >"$MASKED" 2>/dev/null; then
  [ "$TEXT" = "$REPLY" ] && exit 0
else
  jq 'reduce paths(strings) as $p (.; if $p[-1] == "type" then . else
    setpath($p; "[output withheld: the dev-hooks secret redactor failed; fix it and rerun]") end)' \
    "$RESPONSE" >"$MASKED" 2>/dev/null || exit 0
fi
reminder_emit_tool_output "$TOOL" "$MASKED"

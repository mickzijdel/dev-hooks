#!/bin/bash
# bet: none (L5 — output-side half of the secret guard: a command guard cannot see what a
#   file, an API, a script's print or an MCP call will return)
# sunset: never (safety)
# PostToolUse(every tool): mask credential-shaped values in each string of the result.
# A failed hook keeps the original output, so when masking can't run every string is withheld.
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

# separators on lines of their own: the private-key rule replaces whole lines.
# \x1f closes the text, since $() strips a trailing newline. A changed count withholds.
# shellcheck disable=SC2016  # jq programs, not shell expansions
DEFS='def text_paths: . as $r | ((if type == "string" then [[]] else [] end) + [paths(strings)]) | map(. as $p | select(
  [range(0; $p | length) as $i | $r | getpath($p[:$i]) | objects | select(.type == "image")]
  | length == 0));'
reminder_mktemp
MASKED=$REPLY
reminder_mktemp
REDACTED=$REPLY
if TEXT=$(jq -j "$DEFS"' . as $r | text_paths | map(. as $p | $r | getpath($p))
    | join("\n\u001e\n") + "\n\u001f"' "$RESPONSE" 2>/dev/null) &&
  reminder_redact_secrets "$TEXT" && [ "${REPLY: -1}" = $'\037' ] &&
  [ "$(printf '%s' "$REPLY" | tr -cd '\036\037' | wc -c)" = "$(printf '%s' "$TEXT" | tr -cd '\036\037' | wc -c)" ] &&
  printf '%s' "${REPLY%$'\n\037'}" >"$REDACTED" &&
  jq --rawfile m "$REDACTED" "$DEFS"' . as $r | ($m | split("\n\u001e\n")) as $v
    | if ($v | length) != (text_paths | length) then error("string count changed") else
      reduce (text_paths | to_entries[]) as $e ($r; setpath($e.value; $v[$e.key])) end' \
    "$RESPONSE" >"$MASKED" 2>/dev/null; then
  [ "$TEXT" = "$REPLY" ] && exit 0
else
  jq 'reduce paths(strings) as $p (.; if $p[-1] == "type" then . else
    setpath($p; "[output withheld: the dev-hooks secret redactor failed; fix it and rerun]") end)' \
    "$RESPONSE" >"$MASKED" 2>/dev/null || exit 0
fi
reminder_emit_tool_output "$TOOL" "$MASKED"

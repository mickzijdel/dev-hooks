#!/bin/bash
# bet: none (L5 — companion of redact-tool-output.sh: a masked read written back into a
#   file replaces the real value with the marker)
# sunset: never (safety)
# PreToolUse(Write|Edit|MultiEdit|NotebookEdit): ask before new text carries the redactor's
# marker into a file that lacks it; writing masked text back destroys the real value.
#
# Opt out with DEV_HOOKS_REDACT_OUTPUT=false (the redactor's own switch) in settings env.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

reminder_pre_init DEV_HOOKS_REDACT_OUTPUT \
  '[.tool_input.content, .tool_input.new_string, (.tool_input.edits // [] | .[].new_string), .tool_input.new_source] | map(strings) | join("\n")'
MARK_RE='\[REDACTED|\[output withheld: the dev-hooks secret redactor'
printf '%s' "$COMMAND" | grep -Eq "$MARK_RE" || exit 0
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null)
[ -f "$FILE" ] && grep -Eq "$MARK_RE" "$FILE" 2>/dev/null && exit 0

reminder_emit_decision ask "dev-hooks guard — please confirm: this text puts the secret redactor's marker ([REDACTED…]) into ${FILE:-a file}, which does not hold it yet. Claude read that part masked, so writing it back would replace the real value (or a line of code that only looked like a secret). Allow only if the marker is meant literally, as in docs or tests of the redactor; otherwise Claude should edit around those lines."

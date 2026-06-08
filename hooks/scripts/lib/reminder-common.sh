#!/bin/bash
# Shared preamble for the PostToolUse(Write|Edit) "reminder" hooks (latest-deps,
# dockerfile, …). Source it, then call `reminder_init <OPT_OUT_ENV_VAR>`.
#
# On any gate miss it exits 0 (silent). On success it sets these in the caller's scope:
#   INPUT   — raw hook stdin
#   FILE    — .tool_input.file_path
#   SESSION — .session_id (or "nosession")
#   BASE    — basename of FILE
#
# Sourced, not executed: `exit` here terminates the hook, exactly as the inline code did.

reminder_init() {
  local opt_var="$1"
  # Per-repo/user opt-out via the named env var (indirect expansion).
  case "${!opt_var:-}" in
    false | 0 | no | off) exit 0 ;;
  esac

  INPUT=$(cat 2>/dev/null)
  FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  [ -z "$FILE" ] && exit 0
  # SESSION/BASE are consumed by the sourcing hook, not here.
  # shellcheck disable=SC2034
  SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // "nosession"' 2>/dev/null)
  # shellcheck disable=SC2034
  BASE=$(basename "$FILE")
}

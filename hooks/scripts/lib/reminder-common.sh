#!/bin/bash
# Shared preamble + helpers for the PostToolUse(Write|Edit|MultiEdit) "reminder" hooks
# (latest-deps, dockerfile, inline-svg, …). Source it, then call
# `reminder_init <OPT_OUT_ENV_VAR>`; reach for the other helpers as needed.
#
# On any gate miss reminder_init exits 0 (silent). On success it sets these in the
# caller's scope:
#   INPUT   — raw hook stdin
#   FILE    — .tool_input.file_path
#   SESSION — .session_id (or "nosession")
#   TOOL    — .tool_name (Write / Edit / MultiEdit / …)
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
  # One jq spawn for all three scalars. A file path containing a newline would mis-split;
  # accepted edge — such paths don't occur in practice and only cost a silent exit.
  local _ri
  mapfile -t _ri < <(printf '%s' "$INPUT" |
    jq -r '(.tool_input.file_path // ""), (.session_id // "nosession"), (.tool_name // "")' 2>/dev/null)
  FILE=${_ri[0]:-}
  [ -z "$FILE" ] && exit 0
  # SESSION/TOOL/BASE are consumed by the sourcing hook, not here.
  # shellcheck disable=SC2034
  SESSION=${_ri[1]:-nosession}
  # shellcheck disable=SC2034
  TOOL=${_ri[2]:-}
  # shellcheck disable=SC2034
  BASE=${FILE##*/}
}

# Sets CONTENT to everything the tool call writes: Write's content, Edit's new_string,
# and every MultiEdit edits[].new_string. The single source of payload-schema knowledge —
# extend HERE when the schema grows, so all content-reading hooks stay in sync.
reminder_content() {
  # shellcheck disable=SC2034
  CONTENT=$(printf '%s' "$INPUT" | jq -r '(.tool_input.content // "")
    + "\n" + (.tool_input.new_string // "")
    + "\n" + ([.tool_input.edits[]?.new_string // ""] | join("\n"))' 2>/dev/null)
}

# Sets OLD to the text the tool call replaces (Edit old_string, MultiEdit edits[].old_string)
# — the "was it already there?" side of reminder_content.
reminder_old_content() {
  # shellcheck disable=SC2034
  OLD=$(printf '%s' "$INPUT" | jq -r '(.tool_input.old_string // "")
    + "\n" + ([.tool_input.edits[]?.old_string // ""] | join("\n"))' 2>/dev/null)
}

# Composable temp files: result in $REPLY (a command substitution would run the array
# append in a subshell and lose it). The lib owns ONE cleanup trap over the array, so
# hooks needing several temp files don't clobber each other's `trap … EXIT`.
declare -a REMINDER_TMPFILES
reminder_mktemp() {
  local f
  f=$(mktemp) || exit 0
  REMINDER_TMPFILES+=("$f")
  trap 'rm -f "${REMINDER_TMPFILES[@]}"' EXIT
  REPLY=$f
}

# Frontend markup/script/style files where inline-UI hooks apply. One list for every hook
# (*.html.erb ends in .erb).
reminder_is_frontend_file() {
  case "$1" in
    *.js | *.mjs | *.cjs | *.ts | *.jsx | *.tsx | *.vue | *.svelte | *.astro | *.html | *.htm | *.erb | *.haml | *.slim | *.php | *.twig | *.heex | *.css | *.scss) return 0 ;;
    *) return 1 ;;
  esac
}

# Test files/dirs. Keep in sync with is_test_path() in lib/hook_helpers.py — same
# semantics, two languages.
reminder_is_test_path() {
  case "$1" in
    */test/* | */tests/* | */spec/* | */__tests__/* | *.test.* | *.spec.* | *_test.* | *_spec.* | test_*.py | */test_*.py) return 0 ;;
    *) return 1 ;;
  esac
}

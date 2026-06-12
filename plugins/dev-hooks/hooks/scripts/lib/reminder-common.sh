#!/bin/bash
# Shared preamble + helpers for the "reminder" hooks. PostToolUse(Write|Edit|MultiEdit)
# hooks source it and call `reminder_init <OPT_OUT_ENV_VAR>`; Stop hooks source it and
# call `reminder_opt_out` / `reminder_stop_init` instead (reminder_init's payload schema
# is PostToolUse-specific). Reach for the other helpers as needed.
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

# Exit 0 (silent) when the named env var opts the hook out — the per-repo/user
# opt-out documented in each hook's header ("DEV_HOOKS_X=false in settings env").
reminder_opt_out() {
  # Indirect expansion: $1 is the *name* of the opt-out var.
  case "${!1:-}" in
    false | 0 | no | off) exit 0 ;;
  esac
}

reminder_init() {
  reminder_opt_out "$1"

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

# Stop-hook preamble: read hook stdin into INPUT, resolve TRANSCRIPT, and exit 0
# (silent) when the given sentinel string already appears in the transcript — the
# once-per-session guard: the sentinel is embedded in the hook's own reminder, so
# finding it means we already prompted, and a re-fire would loop the Stop hook.
reminder_stop_init() {
  INPUT=$(cat 2>/dev/null)
  TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
  if [ -n "$1" ] && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    grep -qF "$1" "$TRANSCRIPT" 2>/dev/null && exit 0
  fi
}

# ── PreToolUse(Bash) helpers ─────────────────────────────────────────────────────
# PreToolUse preamble for Bash-command guards: opt-out, read stdin, and set in the
# caller's scope:
#   INPUT    — raw hook stdin
#   COMMAND  — .tool_input.command (the bash command about to run; may be multi-line)
#   CWD      — .cwd (where it will run; falls back to $PWD)
#   SESSION  — .session_id (or "nosession")
# Exits 0 (silent → normal permission flow) on opt-out or when there's no command.
# COMMAND is read on its own (not via mapfile) so a multi-line command isn't truncated.
reminder_pre_init() {
  reminder_opt_out "$1"
  INPUT=$(cat 2>/dev/null)
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
  [ -z "$COMMAND" ] && exit 0
  local _pi
  mapfile -t _pi < <(printf '%s' "$INPUT" |
    jq -r '(.cwd // ""), (.session_id // "nosession")' 2>/dev/null)
  # shellcheck disable=SC2034
  CWD=${_pi[0]:-$PWD}
  [ -z "$CWD" ] && CWD=$PWD
  # shellcheck disable=SC2034
  SESSION=${_pi[1]:-nosession}
}

# Emit a PreToolUse permission decision ("deny" | "ask") with a reason, then exit 0.
# Safe commands never call this — the hook stays silent and the normal permission flow
# proceeds. We never emit "allow": that would bypass the user's own allowlist.
reminder_emit_decision() {
  jq -cn --arg decision "$1" --arg reason "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $decision, permissionDecisionReason: $reason}}'
  exit 0
}

# Fire-at-most-once guard, keyed on hook name + $SESSION (+ an optional extra key,
# e.g. a manifest category or file hash). Marker files live under ${TMPDIR}. Needs
# $SESSION, i.e. reminder_init must have run. Callers:
#   reminder_fire_once <name> [extra] || exit 0
reminder_fire_once() {
  local dir="${TMPDIR:-/tmp}/dev-hooks-$1"
  mkdir -p "$dir" 2>/dev/null
  local marker="$dir/${SESSION}${2:+-$2}"
  [ -e "$marker" ] && return 1
  : >"$marker" 2>/dev/null
  return 0
}

# Emit an advisory PostToolUse reminder (additionalContext) and exit 0 — never blocks.
reminder_emit() {
  jq -cn --arg msg "$1" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
  exit 0
}

# Emit Stop-hook feedback (continue:false + additionalContext) and exit 2, feeding the
# message back to Claude so it acts before finishing.
reminder_emit_stop() {
  jq -cn --arg msg "$1" '{continue: false, hookSpecificOutput: {hookEventName: "Stop", additionalContext: $msg}}'
  exit 2
}

# Changed files (staged + unstaged + untracked) from porcelain status, one per line,
# into CHANGED — the "did Claude touch code this session?" gate for Stop hooks.
reminder_changed_files() {
  # shellcheck disable=SC2034
  CHANGED=$(git status --porcelain 2>/dev/null | awk '{print $NF}')
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

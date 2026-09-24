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

# Stop-hook preamble: read hook stdin into INPUT, resolve TRANSCRIPT and SESSION, and
# exit 0 (silent) when the given sentinel string already appears in the transcript — the
# once-per-session guard: the sentinel is embedded in the hook's own reminder, so
# finding it means we already prompted, and a re-fire would loop the Stop hook.
# Pass "" as the sentinel to skip the guard (a hook managing its own re-arm state).
reminder_stop_init() {
  INPUT=$(cat 2>/dev/null)
  local _si
  mapfile -t _si < <(printf '%s' "$INPUT" |
    jq -r '(.transcript_path // ""), (.session_id // "nosession")' 2>/dev/null)
  TRANSCRIPT=${_si[0]:-}
  # shellcheck disable=SC2034
  SESSION=${_si[1]:-nosession}
  if [ -n "$1" ] && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    grep -qF "$1" "$TRANSCRIPT" 2>/dev/null && exit 0
  fi
}

# Session start as a `git log --since` argument, in $REPLY (empty when unknown).
# It is the transcript's first-line timestamp — git parses that ISO fractional-Z form
# as-is. Needs $TRANSCRIPT, i.e. reminder_stop_init must have run first.
#
# Why every Stop hook that looks at "this session's work" needs it: CLAUDE.md mandates
# incremental commits, so by the time Stop fires the tree is usually clean and
# `git status --porcelain` / `git diff HEAD` see nothing. Without this, such a hook
# measures only the sessions that forgot to commit.
#
# Cached per session: the first line never changes, and without the cache the Stop hooks
# started python 7 times per Stop to re-derive it. The cache stores the transcript path
# beside the stamp and is used only for a real session id, so a reused id or a transcript
# rewritten in place (test_jq_stamp_mirror_agrees_with_python) is recomputed. Only a
# non-empty answer is cached; "unknown" is cheap to ask again and may be a partial write.
reminder_session_since() {
  REPLY=""
  [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || return 0
  if [ -z "${SESSION:-}" ] || [ "$SESSION" = nosession ]; then
    _reminder_session_since_compute
    return 0
  fi
  local _cache _path _stamp
  reminder_state_file session-since
  _cache=$REPLY
  if { IFS= read -r _path && IFS= read -r _stamp; } <"$_cache" 2>/dev/null &&
    [ "$_path" = "$TRANSCRIPT" ] && [ -n "$_stamp" ]; then
    REPLY=$_stamp
    return 0
  fi
  _reminder_session_since_compute
  [ -n "$REPLY" ] || return 0
  # Written whole then renamed: the Stop hooks run concurrently and may race to fill it.
  printf '%s\n%s\n' "$TRANSCRIPT" "$REPLY" >"$_cache.$$" 2>/dev/null &&
    mv -f "$_cache.$$" "$_cache" 2>/dev/null
  return 0
}

_reminder_session_since_compute() {
  REPLY=""
  # hook_helpers.session_start is the single implementation, so this cannot drift from the
  # python side that untracked_since uses.
  # Gate on the call SUCCEEDING, not on a non-empty answer: an empty answer is python
  # rejecting the stamp, and falling through on it would let jq re-supply the very value
  # session_start threw out.
  if REPLY=$(
    python3 - "$REMINDER_LIB_DIR" "$TRANSCRIPT" <<'PYEOF' 2>/dev/null
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
from hook_helpers import session_start

sys.stdout.write(session_start(sys.argv[2]))
PYEOF
  ); then
    return 0
  fi
  # No python3: jq, plus a shape check mirroring hook_helpers.session_start.
  #
  # Why the check is this thorough: `git log --since=` never rejects a malformed stamp, it
  # reinterprets it (measured: 63 commits against 297 for "2026-01-32T00:00:00.000Z"), so
  # anything let through is a wrong answer rather than an error — and anything wrongly
  # REJECTED blanks REPLY, which hides the session's commits just as quietly. The rules
  # below each cost a round of that.
  REPLY=$(head -n1 "$TRANSCRIPT" | jq -r 'if (.timestamp | type) == "string" then .timestamp else empty end' 2>/dev/null)
  # Anchored, with every field checked numerically: character classes cannot express month
  # lengths and leap years, or a UTC offset whose TOTAL must be under 24h (+02:99 is valid,
  # normalising to +03:39; +23:99 is not). Hour 24 is rejected, as session_start_epoch does.
  # test_jq_stamp_mirror_agrees_with_python sweeps generated stamps through this and
  # hook_helpers.session_start, and mutation-tests every branch below.
  local _iso _y _m _d _hh _mm _ss _sign _offbody _oh _om _os _max
  _iso='^([0-9]{4})-([0-9]{2})-([0-9]{2})'
  _iso="$_iso"'([T ]([0-9]{2}):([0-9]{2})(:([0-9]{2})(\.[0-9]+)?)?'
  # The offset body is captured whole and parsed separately: one pattern with each colon
  # independently optional accepts mixed separators like "+0000:30", which python rejects.
  # No length cap: datetime.isoformat() emits +00:00:00.123456, fifteen characters. The
  # two alternatives below do the real validation, so an open capture admits nothing.
  _iso="$_iso"'(Z|([+-])([0-9:.]{2,}))?)?$'
  if [[ ! $REPLY =~ $_iso ]]; then
    REPLY=""
    return 0
  fi
  _y=$((10#${BASH_REMATCH[1]}))
  _m=$((10#${BASH_REMATCH[2]}))
  _d=$((10#${BASH_REMATCH[3]}))
  _hh=${BASH_REMATCH[5]:-00}
  _mm=${BASH_REMATCH[6]:-00}
  _ss=${BASH_REMATCH[8]:-00}
  _sign=${BASH_REMATCH[11]:-}
  _offbody=${BASH_REMATCH[12]:-}
  _oh=00
  _om=00
  _os=00
  if [ -n "$_sign" ]; then
    # One separator style throughout, or none — never a mix.
    if [[ $_offbody =~ ^([0-9]{2})(:([0-9]{2})(:([0-9]{2})(\.[0-9]+)?)?)?$ ]]; then
      _oh=${BASH_REMATCH[1]}
      _om=${BASH_REMATCH[3]:-00}
      _os=${BASH_REMATCH[5]:-00}
    elif [[ $_offbody =~ ^([0-9]{2})([0-9]{2})(([0-9]{2})(\.[0-9]+)?)?$ ]]; then
      _oh=${BASH_REMATCH[1]}
      _om=${BASH_REMATCH[2]}
      _os=${BASH_REMATCH[4]:-00}
    else
      REPLY=""
      return 0
    fi
  fi
  _hh=$((10#$_hh))
  _mm=$((10#$_mm))
  _ss=$((10#$_ss))

  case $_m in
    2) _max=28 ;;
    4 | 6 | 9 | 11) _max=30 ;;
    *) _max=31 ;;
  esac
  if [ "$_m" -eq 2 ] &&
    { [ $((_y % 4)) -eq 0 ] && { [ $((_y % 100)) -ne 0 ] || [ $((_y % 400)) -eq 0 ]; }; }; then
    _max=29
  fi

  # Deliberate divergence: session_start also needs .timestamp() to succeed, which
  # underflows within the local UTC offset of datetime.min — here 0001-01-01 alone, and
  # which instants qualify is timezone-dependent, so no portable shell check expresses it.
  # The mirror over-accepts it, the recoverable direction.
  if [ "$_y" -lt 1 ] || [ "$_m" -lt 1 ] || [ "$_m" -gt 12 ] ||
    [ "$_d" -lt 1 ] || [ "$_d" -gt "$_max" ] ||
    [ "$_hh" -gt 23 ] || [ "$_mm" -gt 59 ] || [ "$_ss" -gt 59 ]; then
    REPLY=""
    return 0
  fi
  if [ -n "$_sign" ] &&
    [ $((10#$_oh * 3600 + 10#$_om * 60 + 10#$_os)) -ge 86400 ]; then
    REPLY=""
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
  reminder_cwd_session
}

# PostToolUse(Bash) preamble: opt-out, then from stdin set INPUT and COMMAND
# (.tool_input.command, read here rather than via reminder_init so a multi-line command
# isn't truncated); exits 0 when there is no command. Deliberately does NOT set CWD/SESSION
# — see reminder_cwd_session, which the caller runs after its command-shape match.
reminder_post_bash_init() {
  reminder_opt_out "$1"
  INPUT=$(cat 2>/dev/null)
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
  [ -z "$COMMAND" ] && exit 0
}

# From INPUT set CWD (.cwd, → $PWD) and SESSION (.session_id), in one jq pass.
# The tail of the PreToolUse(Bash)/UserPromptSubmit/SessionStart preambles, and public
# because the PostToolUse(Bash) hooks call it *themselves*, after their command-shape
# match: those run on every Bash tool call, so the second jq spawn is deliberately not
# paid by a `git status` that the hook is going to ignore anyway. Call it before any
# reminder_emit_* — SESSION is what makes the fire log attributable to a repo (a session
# id resolves to its transcript under ~/.claude/projects/<dir>/<session>.jsonl), and a
# hook that emits without it logs "nosession" and cannot be evaluated by the Retire pass.
reminder_cwd_session() {
  local _cs
  mapfile -t _cs < <(printf '%s' "$INPUT" |
    jq -r '(.cwd // ""), (.session_id // "nosession")' 2>/dev/null)
  # shellcheck disable=SC2034
  CWD=${_cs[0]:-$PWD}
  [ -z "$CWD" ] && CWD=$PWD
  # shellcheck disable=SC2034
  SESSION=${_cs[1]:-nosession}
}

# Emit a PreToolUse permission decision ("deny" | "ask") with a reason, then exit 0.
# Safe commands never call this — the hook stays silent and the normal permission flow
# proceeds. We never emit "allow": that would bypass the user's own allowlist.
reminder_emit_decision() {
  _reminder_log_fire "${BASH_SOURCE[1]##*/}"
  jq -cn --arg decision "$1" --arg reason "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $decision, permissionDecisionReason: $reason}}'
  exit 0
}

# Per-session state file, keyed on hook name + $SESSION (+ an optional extra key), under
# ${TMPDIR}. Sets REPLY to the path. reminder_fire_once tracks bare existence through it;
# hooks that must re-arm (compress-comments-reminder) read/write a value there instead.
reminder_state_file() {
  local dir="${TMPDIR:-/tmp}/dev-hooks-$1"
  mkdir -p "$dir" 2>/dev/null
  REPLY="$dir/${SESSION:-nosession}${2:+-$2}"
}

# Fire-at-most-once guard. Needs $SESSION, i.e. reminder_init/reminder_stop_init must
# have run. Callers:
#   reminder_fire_once <name> [extra] || exit 0
reminder_fire_once() {
  reminder_state_file "$1" "$2"
  [ -e "$REPLY" ] && return 1
  : >"$REPLY" 2>/dev/null
  return 0
}

# Opt-in fire telemetry: when DEV_HOOKS_FIRE_LOG is explicitly enabled, append one JSONL line
# per emitted reminder to ~/.claude/automation-review/hook-fires.jsonl, so weekly-automation-
# review's Retire pass can see which hooks actually fire (and which never do). OFF by default —
# no surprise writes, and the test suite (which shares $HOME) stays clean. Best-effort: never
# fails the hook. $1 = firing hook's basename.
_reminder_log_fire() {
  case "${DEV_HOOKS_FIRE_LOG:-}" in 1 | true | yes | on) ;; *) return 0 ;; esac
  local dir="$HOME/.claude/automation-review"
  [ -d "$dir" ] || return 0
  printf '{"hook":"%s","session":"%s","ts":%s}\n' \
    "$1" "${SESSION:-nosession}" "$(date +%s 2>/dev/null || echo 0)" \
    >>"$dir/hook-fires.jsonl" 2>/dev/null || true
}

# Emit an advisory PostToolUse reminder (additionalContext) and exit 0 — never blocks.
reminder_emit() {
  _reminder_log_fire "${BASH_SOURCE[1]##*/}"
  jq -cn --arg msg "$1" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
  exit 0
}

# SessionStart preamble: read hook stdin into INPUT and set in the caller's scope:
#   DIR     — .cwd, the project directory the session opened in (falls back to $PWD)
#   SESSION — .session_id (or "nosession")
# No opt-out argument: SessionStart hooks gate differently from one another (a plain env
# var, a CLAUDE.md marker, an ownership heuristic), so each calls reminder_opt_out itself.
reminder_session_init() {
  INPUT=$(cat 2>/dev/null)
  reminder_cwd_session
  # SessionStart hooks name the project directory DIR; CWD is reminder_cwd_session's.
  # shellcheck disable=SC2034
  DIR=$CWD
}

# Emit a SessionStart advisory (additionalContext is injected into Claude's context at the
# start of the session) and exit 0 — never blocks.
reminder_emit_session() {
  _reminder_log_fire "${BASH_SOURCE[1]##*/}"
  jq -cn --arg msg "$1" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $msg}}'
  exit 0
}

# ── UserPromptSubmit helpers ─────────────────────────────────────────────────────
# UserPromptSubmit preamble: opt-out, read stdin, and set in the caller's scope:
#   INPUT   — raw hook stdin
#   PROMPT  — .prompt (the submitted prompt; may be multi-line)
#   CWD     — .cwd (→ $PWD)   SESSION — .session_id (or "nosession")
# Exits 0 (silent) on opt-out or empty prompt. PROMPT is read on its own (not via
# mapfile) so a multi-line prompt isn't truncated — mirrors reminder_pre_init.
reminder_prompt_init() {
  reminder_opt_out "$1"
  INPUT=$(cat 2>/dev/null)
  # shellcheck disable=SC2034
  PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)
  [ -z "$PROMPT" ] && exit 0
  reminder_cwd_session
}

# Emit a UserPromptSubmit advisory (additionalContext is injected into Claude's context
# before it acts on the prompt) and exit 0 — never blocks.
reminder_emit_prompt() {
  _reminder_log_fire "${BASH_SOURCE[1]##*/}"
  jq -cn --arg msg "$1" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $msg}}'
  exit 0
}

# Emit a PostToolUse correction on stderr and exit 2 — the write already landed, so the
# message is fed back to Claude to fix it now. Louder than reminder_emit's advisory
# additionalContext; use it only for a hook that fires on every occurrence.
reminder_emit_correction() {
  _reminder_log_fire "${BASH_SOURCE[1]##*/}"
  printf '%s\n' "$1" >&2
  exit 2
}

# Emit a plain Stop-hook note on stdout and exit 0 — shown to the user, NOT fed back to
# Claude (that's reminder_emit_stop). The quietest emit path; use it when the session
# should end regardless and the message is just a heads-up.
reminder_emit_note() {
  _reminder_log_fire "${BASH_SOURCE[1]##*/}"
  printf '%s\n' "$1"
  exit 0
}

# Emit Stop-hook feedback (continue:false + additionalContext) and exit 2, feeding the
# message back to Claude so it acts before finishing.
reminder_emit_stop() {
  _reminder_log_fire "${BASH_SOURCE[1]##*/}"
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

# Replace credential-shaped substrings in $1 with [REDACTED]; result in $REPLY. For the
# logging path (prompt-log.sh), so a token pasted mid-incident is never persisted to disk.
# Two rule classes: known vendor prefixes (zero false positives, and they caught every real
# leak found in the log), then one assignment rule reusing the secret-name vocabulary from
# dangerous-command-guard.sh. The assignment rule requires the value to start with an
# alphanumeric, which is what keeps "$(cat …)" command substitutions and ../relative paths
# readable — the log is only useful to the weekly review if ordinary text survives intact.
# The vendor prefixes deliberately carry NO leading \b: a real leak in the log was typed
# glued to the previous word ("…here api key to fix" + "ptr_845Hk…"), so requiring a word
# boundary there silently missed it. Only the loose generic sk- rule keeps its \b.
reminder_redact_secrets() {
  REPLY=$(printf '%s' "$1" | sed -E \
    -e '/-----BEGIN [A-Z ]*PRIVATE KEY-----/,/-----END [A-Z ]*PRIVATE KEY-----/c\[REDACTED PRIVATE KEY]' \
    -e 's|(github_pat_)[A-Za-z0-9_]{20,}|\1[REDACTED]|g' \
    -e 's|(gh[pousr]_)[A-Za-z0-9]{20,}|\1[REDACTED]|g' \
    -e 's|(ptr_)[A-Za-z0-9+/=_-]{20,}|\1[REDACTED]|g' \
    -e 's|(sk-ant-)[A-Za-z0-9_-]{20,}|\1[REDACTED]|g' \
    -e 's|\b(sk-)[A-Za-z0-9]{20,}|\1[REDACTED]|g' \
    -e 's|(xox[baprs]-)[A-Za-z0-9-]{10,}|\1[REDACTED]|g' \
    -e 's|AKIA[0-9A-Z]{16}\b|AKIA[REDACTED]|g' \
    -e 's|(glpat-)[A-Za-z0-9_-]{20,}|\1[REDACTED]|g' \
    -e 's|(bws_)[A-Za-z0-9._-]{20,}|\1[REDACTED]|g' \
    -e 's|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|[REDACTED JWT]|g' \
    -e 's#([A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|APIKEY|API_KEY|_KEY|KEY_)[A-Za-z0-9_]*)([[:space:]]*[=:][[:space:]]*)['"'"'"]?[A-Za-z0-9_+][A-Za-z0-9_+/=.~-]{19,}['"'"'"]?#\1\3[REDACTED]#g' \
    2>/dev/null)
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

# ── "This session's work" helpers (Stop hooks) ───────────────────────────────────
# Absolute path to this lib dir, resolved at source time, so helpers can hand it to an
# embedded-python heredoc without every caller recomputing $SELF_DIR/lib.
REMINDER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# The code extensions every Stop hook agrees on. ONE list: review-reminder's regex and
# compress-comments-reminder's glob array were separate copies and had already drifted
# (*.sh counted as code for one hook and not the other).
REMINDER_CODE_EXTS=(rb erb rake py js ts jsx tsx vue mjs cjs sh)

reminder_code_globs() {
  CODE_GLOBS=()
  local ext
  for ext in "${REMINDER_CODE_EXTS[@]}"; do CODE_GLOBS+=("*.$ext"); done
}

reminder_is_code_file() {
  local ext
  for ext in "${REMINDER_CODE_EXTS[@]}"; do
    [ "${1##*.}" = "$ext" ] && return 0
  done
  return 1
}

# True when any line of $1 (newline-separated paths) names a code file.
reminder_has_code_file() {
  local path
  while IFS= read -r path; do
    [ -n "$path" ] && reminder_is_code_file "$path" && return 0
  done <<<"$1"
  return 1
}

# Every file this session touched — uncommitted (porcelain) AND committed since the
# session started — one per line, into SESSION_FILES. Needs $TRANSCRIPT, so
# reminder_stop_init must have run.
#
# Prefer this over reminder_changed_files for any "did Claude do work this session?" gate.
# CLAUDE.md mandates commit-as-you-go, so by the time Stop fires the tree is usually clean
# and a porcelain-only gate exits silently on exactly the sessions that did the most work.
# Untracked files modified since the session started, one per line; optional pathspecs
# narrow it as `git ls-files -- <spec>` would.
#
# hook_helpers.untracked_since does the work, not shell. `date -d`, `find -newermt`,
# `find -size` and xargs each behave differently across platforms, and each failure mode
# returns nothing — indistinguishable from "this session did no work".
# shellcheck disable=SC2120  # pathspecs are optional; reminder_session_files passes none.
reminder_untracked_since() {
  local _out
  reminder_session_since
  if _out=$(
    python3 - "$REMINDER_LIB_DIR" "$REPLY" "$@" <<'PYEOF' 2>/dev/null
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
from hook_helpers import untracked_since

for path in untracked_since(sys.argv[2], tuple(sys.argv[3:])):
    print(path)
PYEOF
  ); then
    printf '%s' "$_out"
    [ -n "$_out" ] && printf '\n'
    return 0
  fi
  # python3 missing or broken: skip the filter and list everything. Over-reporting is
  # recoverable; an empty result reads as "the session did no work".
  git ls-files -z --others --exclude-standard -- "$@" 2>/dev/null | tr '\0' '\n'
}

# Contents of this session's untracked files, size-capped, on stdout. Same reasoning as
# reminder_untracked_since: one python implementation rather than a per-platform pipeline.
reminder_untracked_text() {
  local _out _f _size
  reminder_session_since
  if _out=$(
    python3 - "$REMINDER_LIB_DIR" "$REPLY" "$@" <<'PYEOF' 2>/dev/null
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
from hook_helpers import untracked_text

sys.stdout.write(untracked_text(sys.argv[2], tuple(sys.argv[3:])))
PYEOF
  ); then
    printf '%s' "$_out"
    return 0
  fi
  # Same invariant as reminder_untracked_since. `wc -c` keeps the size cap portable:
  # `find -size -1M` rounds up, so it matches only empty files.
  while IFS= read -r _f; do
    [ -f "$_f" ] || continue
    _size=$(wc -c <"$_f" 2>/dev/null) || continue
    [ "$_size" -le 1048576 ] && cat "$_f" 2>/dev/null
  done < <(git ls-files -z --others --exclude-standard -- "$@" 2>/dev/null | tr '\0' '\n')
}

reminder_session_files() {
  reminder_changed_files
  local committed="" untracked=""
  reminder_session_since
  [ -n "$REPLY" ] && committed=$(git log --name-only --format= --since="$REPLY" 2>/dev/null)
  # Enumerated separately because porcelain collapses an untracked *directory* into one
  # entry, hiding every file inside it — and restricted to files touched since the session
  # started, or a long-standing untracked tree (a scratch dir, a vendored dump) would count
  # as this session's work in every session and trip the size gates on its own.
  # shellcheck disable=SC2119  # no pathspecs = every untracked file, by design.
  untracked=$(reminder_untracked_since)
  # shellcheck disable=SC2034
  SESSION_FILES=$(printf '%s\n%s\n%s\n' "$CHANGED" "$committed" "$untracked" |
    grep -v '^$' | sort -u)
}

# Lines of code this session added — added lines in `git diff HEAD`, in commits since the
# session started, and every line of an untracked code file — into $REPLY. The growth
# signal reminder_rearm compares against, and the shared half of compress-comments-
# reminder's comment count (which filters these lines further).
# Pass pathspecs to widen beyond code (big-change-reminder counts every file); with no
# arguments it uses REMINDER_CODE_EXTS.
reminder_session_added_lines() {
  if [ "$#" -gt 0 ]; then
    CODE_GLOBS=("$@")
  else
    reminder_code_globs
  fi
  local since
  reminder_session_since
  since=$REPLY
  REPLY=$(
    {
      {
        git diff HEAD --no-color -- "${CODE_GLOBS[@]}" 2>/dev/null
        [ -n "$since" ] && git log -p --no-color --format= --since="$since" -- "${CODE_GLOBS[@]}" 2>/dev/null
      } | grep -E '^\+' | grep -vE '^\+\+\+' | cut -c2-
      reminder_untracked_text "${CODE_GLOBS[@]}"
    } | cat
  )
}

# Did this session actually *invoke* one of the named skills/agents/slash-commands?
# $REPLY = 1|0. $1 is a sentinel string ("" for none — a hook's own prior reminder text);
# the rest are needles. Wraps hook_helpers.transcript_invoked, which walks tool_use blocks
# rather than grepping: the transcript carries a skill_listing attachment naming every
# installed skill, so a bare-name grep matches in EVERY session and would suppress the
# caller forever. Needs $TRANSCRIPT.
reminder_transcript_invoked() {
  local sentinel=$1
  shift
  REPLY=0
  [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  REPLY=$(
    python3 - "$TRANSCRIPT" "$sentinel" "$REMINDER_LIB_DIR" "$@" <<'PYEOF'
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[3])
from hook_helpers import transcript_invoked

print(
    1
    if transcript_invoked(
        sys.argv[1], tuple(sys.argv[4:]), sentinel=sys.argv[2] or None
    )
    else 0
)
PYEOF
  )
  [ "$REPLY" = "1" ] || REPLY=0
}

# ── Re-arming baselines ──────────────────────────────────────────────────────────
# Why every "before you finish" Stop hook wants one: a once-per-session sentinel fires
# once and then goes quiet for the rest of the session, however little of the work the
# single nudge actually got done. The fire log bears this out — compress-comments-reminder
# (re-arming) averages ~3.9 fires per session it speaks in; review-reminder (sentinel)
# averages exactly 1.0.
#
# Current baseline for $1 into $REPLY ("" when the hook has not fired yet this session).
reminder_rearm_baseline() {
  reminder_state_file "$1"
  REPLY=$(cat "$REPLY" 2>/dev/null)
  case "$REPLY" in *[!0-9]* | "") REPLY="" ;; esac
}

# Record $2 as the baseline for $1 without firing — "this much is already handled".
reminder_rearm_seed() {
  reminder_state_file "$1"
  printf '%s' "$2" >"$REPLY" 2>/dev/null
}

# Decide whether to fire, given state name $1, current count $2 and growth threshold $3.
# Sets REPLY to one of:
#   first   — no baseline yet and count >= threshold
#   growth  — count grew by >= threshold since the last fire
#   silent  — below threshold, or unchanged (which is what keeps Stop from looping)
# A count that DROPPED means the work was done: rebase the baseline and stay silent rather
# than nag. REMINDER_REARM_DELTA carries the growth the decision was made on.
reminder_rearm() {
  local stored
  reminder_rearm_baseline "$1"
  stored=$REPLY
  REMINDER_REARM_DELTA=$2
  if [ -z "$stored" ]; then
    if [ "$2" -lt "$3" ]; then
      REPLY=silent
      return 0
    fi
    reminder_rearm_seed "$1" "$2"
    REPLY=first
    return 0
  fi
  if [ "$2" -lt "$stored" ]; then
    reminder_rearm_seed "$1" "$2"
    REPLY=silent
    return 0
  fi
  REMINDER_REARM_DELTA=$(($2 - stored))
  if [ "$REMINDER_REARM_DELTA" -lt "$3" ]; then
    REPLY=silent
    return 0
  fi
  reminder_rearm_seed "$1" "$2"
  REPLY=growth
}

#!/bin/bash
# Shared preamble + helpers for the `writing` plugin's hooks.
#
# Scope: this plugin only. The writing plugin installs WITHOUT dev-hooks, so these hooks
# still must not source dev-hooks' lib/reminder-common.sh or import hook_helpers.py — a
# cross-plugin source would break that standalone install. Sharing *within* the plugin is
# fine (the four hooks always ship together) and is what keeps the profile lookup, the
# prose-file list and the opt-out from drifting apart across them; they previously lived as
# `# jscpd:ignore`-wrapped copies in each script.
#
# Sourced, not executed: `exit` here terminates the hook.

# Exit 0 (silent) when the named env var opts the hook out. Defaults to WRITING_VOICE, the
# one switch for every voice hook; readme-reminder.sh passes its own WRITING_README.
voice_opt_out() {
  # Indirect expansion: $1 is the *name* of the opt-out var.
  local var=${1:-WRITING_VOICE}
  case "${!var:-}" in
    false | 0 | no | off) exit 0 ;;
  esac
}

# Read hook stdin into INPUT; exits 0 when jq is unavailable or the payload is empty.
voice_payload() {
  command -v jq >/dev/null 2>&1 || exit 0
  INPUT=$(cat 2>/dev/null)
  [ -z "$INPUT" ] && exit 0
}

# Echo one jq field from INPUT ("" when absent).
voice_field() {
  printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null
}

# Resolve a voice profile into PROFILE; exits 0 (silent) when none is discoverable, which
# is what keeps installs without a profile from seeing anything at all. First hit wins:
# $WRITING_VOICE_PROFILE, <cwd>/.claude/voice_profile.md, ~/.claude/voice_profile.md.
voice_profile() {
  local cwd cand
  cwd=$(voice_field '.cwd')
  PROFILE=""
  for cand in "${WRITING_VOICE_PROFILE:-}" "${cwd:+$cwd/.claude/voice_profile.md}" "$HOME/.claude/voice_profile.md"; do
    [ -n "$cand" ] && [ -f "$cand" ] && PROFILE="$cand" && break
  done
  [ -z "$PROFILE" ] && exit 0
}

# Files whose content is prose a voice profile applies to. Markup and templating languages
# count: webcopy, marketing pages and Rails views carry the sentences a reader actually
# reads, and they were the gap that let drafts through unchecked.
#
# ONE list, shared with the transcript scan below by argv — a second copy inside the python
# heredoc would drift silently, and a drifted copy does not error, it just stops seeing files.
VOICE_PROSE_EXTS=(
  md mdx markdown rmd qmd tex txt rst org adoc asciidoc textile
  html htm xhtml erb haml slim liquid njk hbs mustache ejs jinja jinja2 j2
)

voice_is_prose_file() {
  local lower=${1,,} ext
  for ext in "${VOICE_PROSE_EXTS[@]}"; do
    [ "${lower##*.}" = "$ext" ] && return 0
  done
  return 1
}

# Prose files that are repo scaffolding, not writing a voice profile applies to. Mick's
# CLAUDE.md scopes the voice to "newsletters, blog posts, essays, emails, website copy,
# reports, academic writing — not code". A SKILL.md, a CHANGELOG or a plans/ note sits with
# the code, and with a global ~/.claude/voice_profile.md present every ordinary coding
# session touches one — which would have the blocking Stop hook refuse to end three times
# over a skill manifest. READMEs have their own hook (readme-reminder) and skill.
VOICE_SKIP_BASENAMES=(
  readme readme.* changelog* license* contributing* code_of_conduct*
  agents.md claude.md skill.md
)
VOICE_SKIP_DIRS=(.claude .github node_modules vendor plans .worktrees)

voice_is_scaffolding_file() {
  local lower=${1,,} base=${1##*/} pat dir
  base=${base,,}
  for pat in "${VOICE_SKIP_BASENAMES[@]}"; do
    # shellcheck disable=SC2053
    [[ $base == $pat ]] && return 0
  done
  for dir in "${VOICE_SKIP_DIRS[@]}"; do
    case "$lower" in */$dir/*) return 0 ;; esac
  done
  return 1
}

# Walk the session transcript and print "<prose files written>\t<voice skill invoked 0|1>".
# Needs $1 = transcript path. The skill check walks tool_use blocks rather than grepping for
# the name: a transcript carries a skill_listing attachment naming every installed skill, so
# a bare grep matches in every session and would suppress the hook permanently.
voice_transcript_scan() {
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$1" "${#VOICE_PROSE_EXTS[@]}" "${VOICE_PROSE_EXTS[@]}" \
    "${#VOICE_SKIP_BASENAMES[@]}" "${VOICE_SKIP_BASENAMES[@]}" "${VOICE_SKIP_DIRS[@]}" <<'PYEOF'
import json
import sys

import fnmatch
import posixpath

path = sys.argv[1]
n_ext = int(sys.argv[2])
exts = tuple("." + e for e in sys.argv[3 : 3 + n_ext])
rest = sys.argv[3 + n_ext :]
n_base = int(rest[0])
skip_bases = rest[1 : 1 + n_base]
skip_dirs = rest[1 + n_base :]


def scaffolding(fp):
    low = fp.lower()
    base = posixpath.basename(low)
    if any(fnmatch.fnmatch(base, pat) for pat in skip_bases):
        return True
    return any(f"/{d}/" in low for d in skip_dirs)

written, skill = set(), 0
try:
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            content = (rec.get("message") or {}).get("content")
            for block in content if isinstance(content, list) else []:
                if not isinstance(block, dict) or block.get("type") != "tool_use":
                    continue
                inp = block.get("input") or {}
                name = inp.get("skill") or inp.get("subagent_type") or ""
                if isinstance(name, str) and "voice-profile" in name:
                    skill = 1
                if block.get("name") in ("Write", "Edit", "MultiEdit"):
                    fp = inp.get("file_path")
                    if (
                        isinstance(fp, str)
                        and fp.lower().endswith(exts)
                        and not scaffolding(fp)
                    ):
                        written.add(fp)
except OSError:
    pass
print(f"{len(written)}\t{skill}")
PYEOF
}

# Per-session marker under ${TMPDIR}; path in $REPLY. Needs SESSION.
voice_state_file() {
  local dir="${TMPDIR:-/tmp}/writing-$1"
  mkdir -p "$dir" 2>/dev/null
  REPLY="$dir/${SESSION:-nosession}${2:+-$2}"
}

# Fire-at-most-once guard: `voice_fire_once <name> [extra] || exit 0`.
voice_fire_once() {
  voice_state_file "$1" "$2"
  [ -e "$REPLY" ] && return 1
  : >"$REPLY" 2>/dev/null
  return 0
}

# Opt-in fire telemetry, mirroring dev-hooks' DEV_HOOKS_FIRE_LOG so weekly-automation-review
# can see these hooks at all. They previously hand-rolled their own jq emit and so never
# reached hook-fires.jsonl — their "0 fires" was undecidable rather than informative.
# OFF by default; best-effort, never fails the hook.
_voice_log_fire() {
  case "${DEV_HOOKS_FIRE_LOG:-}" in 1 | true | yes | on) ;; *) return 0 ;; esac
  local dir="$HOME/.claude/automation-review"
  [ -d "$dir" ] || return 0
  printf '{"hook":"%s","session":"%s","ts":%s}\n' \
    "$1" "${SESSION:-nosession}" "$(date +%s 2>/dev/null || echo 0)" \
    >>"$dir/hook-fires.jsonl" 2>/dev/null || true
}

# Advisory: inject additionalContext for the given event and exit 0 — never blocks.
# $1 = hookEventName (PostToolUse / UserPromptSubmit / PreToolUse), $2 = message.
voice_emit() {
  _voice_log_fire "${BASH_SOURCE[1]##*/}"
  jq -cn --arg event "$1" --arg msg "$2" \
    '{hookSpecificOutput: {hookEventName: $event, additionalContext: $msg}}'
  exit 0
}

# Stop-hook feedback: continue:false + exit 2, so Claude acts before the turn ends rather
# than after the user has already read the draft.
voice_emit_stop() {
  _voice_log_fire "${BASH_SOURCE[1]##*/}"
  jq -cn --arg msg "$1" \
    '{continue: false, hookSpecificOutput: {hookEventName: "Stop", additionalContext: $msg}}'
  exit 2
}

#!/bin/bash
# Stop hook: if this session's work added a noticeable number of code comments, remind
# Claude once to run the dev-hooks `compress-comments` skill before finishing, so
# comments that restate the code (narration, code-echo, planning forensics) get deleted
# and the rest compressed.
#
# Signal: added comment lines in (a) `git diff HEAD` (uncommitted work), (b) untracked
# code files (all their lines are new), and (c) commits made since the session started —
# the transcript's first-line timestamp — so commit-as-you-go sessions with a clean tree
# still trigger. Shebangs and directive comments (shellcheck/eslint/noqa/...) don't count;
# docstrings aren't counted either — the skill still reviews them; this hook only needs a
# cheap "wrote comments" signal, not full coverage. Fires at ≥3 comment lines.
#
# Once per session: our own bracketed sentinel, plus a tool_use scan for an actual skill
# invocation. Neither check may plain-grep the skill's name: the transcript records a
# skill_listing attachment naming every installed skill, so a bare "compress-comments"
# grep matches in every session and would permanently suppress the hook.
#
# Opt out with DEV_HOOKS_COMPRESS_COMMENTS=false in settings env.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

reminder_opt_out DEV_HOOKS_COMPRESS_COMMENTS

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

SENTINEL="[compress-comments-reminder]"

# Sets INPUT/TRANSCRIPT; exits 0 when our sentinel shows we already prompted.
reminder_stop_init "$SENTINEL"

# Skill already invoked this session (Skill tool_use / slash command)? Then stay silent.
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  RAN=$(
    python3 - "$TRANSCRIPT" "$SELF_DIR/lib" <<'PYEOF'
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[2])
from hook_helpers import transcript_invoked

print(1 if transcript_invoked(sys.argv[1], ("compress-comments",)) else 0)
PYEOF
  )
  [ "$RAN" = "1" ] && exit 0
fi

# ── Count comment lines this session added ──────────────────────────────────────
CODE_GLOBS=('*.rb' '*.erb' '*.rake' '*.py' '*.js' '*.ts' '*.jsx' '*.tsx' '*.vue' '*.mjs' '*.cjs' '*.sh')
# `*` needs trailing space/EOL: a bare `^\s*\*` would count Python's `*args,` lines.
COMMENT_RE='^[[:space:]]*(#|//|/\*|\*([[:space:]]|$))'
NOISE_RE='^[[:space:]]*#!|shellcheck|eslint|noqa|biome-ignore|jscpd:|rubocop:|type:[[:space:]]*ignore|frozen_string_literal'

# Session start = the transcript's first-line timestamp (git parses the ISO form as-is).
# Commits after it count as this session's work; a commit by the user in a parallel
# terminal can slip in, but for an advisory once-per-session nudge that's acceptable.
SINCE=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  SINCE=$(head -n1 "$TRANSCRIPT" | jq -r '.timestamp // empty' 2>/dev/null)
fi

COUNT=$(
  {
    {
      git diff HEAD --no-color -- "${CODE_GLOBS[@]}" 2>/dev/null
      if [ -n "$SINCE" ]; then
        git log -p --no-color --format= --since="$SINCE" -- "${CODE_GLOBS[@]}" 2>/dev/null
      fi
    } | grep -E '^\+' | grep -vE '^\+\+\+' | cut -c2-
    git ls-files -z --others --exclude-standard -- "${CODE_GLOBS[@]}" 2>/dev/null |
      xargs -0 -r cat 2>/dev/null
  } | grep -E "$COMMENT_RE" | grep -cvE "$NOISE_RE"
)
[ "${COUNT:-0}" -ge 3 ] || exit 0

# ── Emit the reminder ────────────────────────────────────────────────────────────
MSG="${SENTINEL} This session added ${COUNT} comment lines. Before finishing, review the comments you wrote: run the dev-hooks compress-comments skill on this session's diff. Delete comments that restate the code (code-echo, change narration, planning forensics, reviewer justification); compress the rest. A comment survives only if it states something the code cannot show."

reminder_emit_stop "$MSG"

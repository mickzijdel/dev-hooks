#!/bin/bash
# bet: model over-narrates in comments and won't prune them before finishing
# sunset: model writes minimal comments and self-prunes redundant ones
# Stop hook: if this session's work added a noticeable number of code comments, remind
# Claude to run the dev-hooks `compress-comments` skill before finishing, so comments
# that restate the code (narration, code-echo, planning forensics) get deleted and the
# rest compressed.
#
# Signal: added comment lines in (a) `git diff HEAD` (uncommitted work), (b) untracked
# code files (all their lines are new), and (c) commits made since the session started —
# the transcript's first-line timestamp — so commit-as-you-go sessions with a clean tree
# still trigger. Shebangs and directive comments (shellcheck/eslint/noqa/...) don't count;
# docstrings aren't counted either — the skill still reviews them; this hook only needs a
# cheap "wrote comments" signal, not full coverage.
#
# Re-arm instead of once-per-session: the session's comment-line total is stored in a
# reminder_state_file at each fire, and the hook fires again whenever the total has grown
# by ≥3 since — one large commit, three small ones, or purely uncommitted edits alike.
# An unchanged total stays silent (no Stop loop); a total that DROPPED (comments were
# cleaned up) rebases the baseline; a skill run before any reminder seeds the baseline,
# detected via a tool_use scan — never a bare-name transcript grep, which would match the
# skill_listing attachment naming every installed skill and permanently suppress the hook.
#
# Opt out with DEV_HOOKS_COMPRESS_COMMENTS=false in settings env.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

reminder_opt_out DEV_HOOKS_COMPRESS_COMMENTS

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Sets INPUT/TRANSCRIPT/SESSION; empty sentinel — re-arm state replaces the guard.
reminder_stop_init ""

# ── Count comment lines this session added ──────────────────────────────────────
CODE_GLOBS=('*.rb' '*.erb' '*.rake' '*.py' '*.js' '*.ts' '*.jsx' '*.tsx' '*.vue' '*.mjs' '*.cjs' '*.sh')
# `*` needs trailing space/EOL: a bare `^\s*\*` would count Python's `*args,` lines.
COMMENT_RE='^[[:space:]]*(#|//|/\*|\*([[:space:]]|$))'
NOISE_RE='^[[:space:]]*#!|shellcheck|eslint|noqa|biome-ignore|jscpd:|rubocop:|type:[[:space:]]*ignore|frozen_string_literal'

reminder_session_since
SINCE=$REPLY

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
COUNT=${COUNT:-0}

# ── Compare against the last-fired baseline ─────────────────────────────────────
reminder_state_file compress-comments
MARKER=$REPLY
STORED=$(cat "$MARKER" 2>/dev/null)
case "$STORED" in *[!0-9]* | "") STORED="" ;; esac

SENTINEL="[compress-comments-reminder]"
if [ -z "$STORED" ]; then
  # No reminder yet this session. A skill run that already happened seeds the baseline:
  # the current comments are considered handled, only growth beyond them re-arms.
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
    if [ "$RAN" = "1" ]; then
      printf '%s' "$COUNT" >"$MARKER" 2>/dev/null
      exit 0
    fi
  fi
  [ "$COUNT" -ge 3 ] || exit 0
  MSG="${SENTINEL} This session added ${COUNT} comment lines."
else
  if [ "$COUNT" -lt "$STORED" ]; then
    # Comments were cleaned up since the last reminder: rebase, don't nag.
    printf '%s' "$COUNT" >"$MARKER" 2>/dev/null
    exit 0
  fi
  [ $((COUNT - STORED)) -ge 3 ] || exit 0
  MSG="${SENTINEL} $((COUNT - STORED)) more comment lines since the last reminder (session total ${COUNT})."
fi

printf '%s' "$COUNT" >"$MARKER" 2>/dev/null
MSG="${MSG} Before finishing, review the comments you wrote: run the dev-hooks compress-comments skill on this session's diff. Delete comments that restate the code (code-echo, change narration, planning forensics, reviewer justification); compress the rest. A comment survives only if it states something the code cannot show."

reminder_emit_stop "$MSG"

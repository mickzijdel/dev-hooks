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
# reminder_session_added_lines supplies the shared half (added lines in the working tree,
# in commits since the session started, and every line of an untracked code file, over the
# lib's one code-extension list); this hook only filters them down to comments.
# `*` needs trailing space/EOL: a bare `^\s*\*` would count Python's `*args,` lines.
COMMENT_RE='^[[:space:]]*(#|//|/\*|\*([[:space:]]|$))'
NOISE_RE='^[[:space:]]*#!|shellcheck|eslint|noqa|biome-ignore|jscpd:|rubocop:|type:[[:space:]]*ignore|frozen_string_literal'

reminder_session_added_lines
COUNT=$(printf '%s\n' "$REPLY" | grep -E "$COMMENT_RE" | grep -cvE "$NOISE_RE")
COUNT=${COUNT:-0}

# ── Compare against the last-fired baseline ─────────────────────────────────────
SENTINEL="[compress-comments-reminder]"

reminder_rearm_baseline compress-comments
if [ -z "$REPLY" ]; then
  # No reminder yet this session. A skill run that already happened seeds the baseline:
  # the current comments count as handled, and only growth beyond them re-arms.
  reminder_transcript_invoked "" compress-comments
  if [ "$REPLY" = "1" ]; then
    reminder_rearm_seed compress-comments "$COUNT"
    exit 0
  fi
fi

reminder_rearm compress-comments "$COUNT" 3
case "$REPLY" in
  silent) exit 0 ;;
  first) MSG="${SENTINEL} This session added ${COUNT} comment lines." ;;
  *) MSG="${SENTINEL} ${REMINDER_REARM_DELTA} more comment lines since the last reminder (session total ${COUNT})." ;;
esac

MSG="${MSG} Before finishing, review the comments you wrote: run the dev-hooks compress-comments skill on this session's diff. Delete comments that restate the code (code-echo, change narration, planning forensics, reviewer justification); compress the rest. A comment survives only if it states something the code cannot show."

reminder_emit_stop "$MSG"

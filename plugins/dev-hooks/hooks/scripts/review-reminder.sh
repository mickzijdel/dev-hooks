#!/bin/bash
# bet: none (L1 — Mick's review-before-finishing preference)
# sunset: never (preference)
# Stop hook: if this session changed code and no code review has run since, remind Claude
# to review before finishing — and to keep iterating until the review comes back clean.
#
# Two things make this land where the earlier once-per-session version did not. The fire
# log is unambiguous about both: this hook used to average exactly 1.0 fires per session
# it spoke in, and stayed silent entirely in 43 of the 72 sessions that wrote enough code
# to trip compress-comments-reminder.
#
#   Committed work counts. The gate is reminder_session_files (porcelain + commits since
#   the session started), not porcelain alone. CLAUDE.md mandates commit-as-you-go, so by
#   the time Stop fires the tree is usually clean — a porcelain-only gate went silent on
#   exactly the sessions that had done the most work.
#
#   It re-arms. A sentinel fires once and then stays quiet for the rest of the session,
#   however little that single nudge got done. Instead: while no review has run at all the
#   hook speaks at every Stop (capped, so a Claude that cannot review still terminates);
#   once one has, the session's added code lines become a baseline and the hook speaks
#   again when they grow past it — code written *after* a review makes that review stale.
#
# "Already reviewed" is a tool_use walk for actual review invocations, never a bare-name
# transcript grep, which would match the skill_listing attachment in every session.
#
# Opt out with DEV_HOOKS_REVIEW=false in settings env.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

reminder_opt_out DEV_HOOKS_REVIEW

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Sets INPUT/TRANSCRIPT/SESSION; empty sentinel — the re-arm state replaces that guard.
reminder_stop_init ""

# ── Gate: this session touched code ─────────────────────────────────────────────
reminder_session_files
[ -z "$SESSION_FILES" ] && exit 0
reminder_has_code_file "$SESSION_FILES" || exit 0

reminder_session_added_lines
COUNT=$(printf '%s\n' "$REPLY" | grep -c .)
COUNT=${COUNT:-0}

# How much new code makes a finished review stale enough to ask for another pass.
GROWTH=20
# Below this much new code a single nudge is enough — re-blocking Stop three times over a
# one-line change is noise. Above it, keep asking.
SUBSTANTIAL=10

SENTINEL="[review-reminder]"

reminder_transcript_invoked "" code-review code_review requesting-code-review code-reviewer
REVIEWED=$REPLY

if [ "$REVIEWED" = "1" ]; then
  # A review ran. Seed the baseline on first sight, then speak only when code written
  # since has grown past it — the stale-review path.
  reminder_rearm_baseline review
  if [ -z "$REPLY" ]; then
    reminder_rearm_seed review "$COUNT"
    exit 0
  fi
  reminder_rearm review "$COUNT" "$GROWTH"
  [ "$REPLY" = "silent" ] && exit 0
  MSG="${SENTINEL} ${REMINDER_REARM_DELTA} more lines of code since the last review — that review is now stale."
else
  # Nudge once for a small change; keep asking (bounded, so a Claude that genuinely cannot
  # review still gets to stop) once the session has written a substantial amount of code.
  MAX_NUDGES=1
  [ "$COUNT" -ge "$SUBSTANTIAL" ] && MAX_NUDGES=3
  reminder_state_file review-nudges
  NUDGES=$(cat "$REPLY" 2>/dev/null)
  case "$NUDGES" in *[!0-9]* | "") NUDGES=0 ;; esac
  [ "$NUDGES" -ge "$MAX_NUDGES" ] && exit 0
  printf '%s' "$((NUDGES + 1))" >"$REPLY" 2>/dev/null
  MSG="${SENTINEL} You changed code this session (${COUNT} added lines) and have not run a code review."
fi

MSG="${MSG} Run a code review now — the /code-review skill, or a code-reviewer agent such as superpowers:requesting-code-review. IMPORTANT: keep iterating — run the review, address every finding, then re-run the review, repeating until it comes back entirely clean. Do not stop after a single pass."

reminder_emit_stop "$MSG"

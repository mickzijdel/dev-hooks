#!/bin/bash
# bet: none (L1 — Mick's review-before-finishing preference)
# sunset: never (preference)
# Stop hook: if Claude changed code this session but never ran a code review,
# remind it to do one before finishing — and to keep iterating until the review
# comes back entirely clean.
#
# "Already reviewed" is detected by scanning the session transcript for actual
# review *tool invocations* (the /code-review skill, the superpowers code-reviewer
# agent, or requesting-code-review) — not casual prose — so a session that merely
# talks about code review does not suppress the reminder. The reminder is emitted
# at most once per session (its own sentinel string acts as the guard), so there
# is no infinite Stop loop.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

# ── Gate: must be a git repo with changed code files (mirrors verify-work.sh) ───
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

reminder_changed_files # sets CHANGED
[ -z "$CHANGED" ] && exit 0
echo "$CHANGED" | grep -qE '\.(rb|erb|rake|py|js|ts|jsx|tsx|vue|mjs|cjs)$' || exit 0

# Sentinel embedded in our reminder; finding it in the transcript means we already
# prompted this session, so we stay silent thereafter.
SENTINEL="[review-reminder] code review not yet run this session"

# Sets INPUT/TRANSCRIPT; exits 0 on the sentinel fast path (the python pass below
# re-checks it line-by-line while walking the tool_use blocks).
reminder_stop_init "$SENTINEL"

# ── Decide whether a review (or a prior reminder) already happened ──────────────
# python3 is already a dependency of verify-work.sh. Inspect tool_use blocks for
# review invocations rather than grepping raw text, to avoid false positives.
ALREADY=0
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  ALREADY=$(
    python3 - "$TRANSCRIPT" "$SENTINEL" "$SELF_DIR/lib" <<'PYEOF'
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[3])
from hook_helpers import transcript_invoked

ran = transcript_invoked(
    sys.argv[1], ("code-review", "code_review"), sentinel=sys.argv[2]
)
print(1 if ran else 0)
PYEOF
  )
fi

[ "$ALREADY" = "1" ] && exit 0

# ── Emit the reminder ──────────────────────────────────────────────────────────
MSG="${SENTINEL}. You changed code this session but have not run a code review yet. Before finishing, run a code review now — use the /code-review skill (or a code-reviewer agent such as superpowers:requesting-code-review / the code-reviewer subagent). IMPORTANT: keep iterating — run the review, address every finding, then re-run the review, repeating until it comes back entirely clean with no remaining issues. Do not stop after a single review pass."

reminder_emit_stop "$MSG"

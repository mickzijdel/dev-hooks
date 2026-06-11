#!/bin/bash
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
    python3 - "$TRANSCRIPT" "$SENTINEL" <<'PYEOF'
import sys, json

path, sentinel = sys.argv[1], sys.argv[2]


def has_review(value):
    """True if a string value names a code-review tool/skill/agent."""
    return isinstance(value, str) and ("code-review" in value or "code_review" in value)


found = False
try:
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            # Fast path: our own reminder sentinel already present.
            if sentinel in line:
                found = True
                break
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue

            # Walk message content blocks looking for review tool invocations.
            msg = rec.get("message", rec)
            content = msg.get("content") if isinstance(msg, dict) else None
            blocks = content if isinstance(content, list) else []
            for block in blocks:
                if not isinstance(block, dict):
                    continue
                if block.get("type") != "tool_use":
                    continue
                inp = block.get("input") or {}
                # Skill tool: {"skill": "code-review"} / "superpowers:requesting-code-review"
                if has_review(inp.get("skill")):
                    found = True
                # Agent/Task tool: {"subagent_type": "...code-reviewer"}
                if has_review(inp.get("subagent_type")):
                    found = True
                if found:
                    break
            if found:
                break

            # Slash-command marker: <command-name>code-review</command-name>
            if "command-name" in line and "code-review" in line:
                found = True
                break
except OSError:
    pass

print(1 if found else 0)
PYEOF
  )
fi

[ "$ALREADY" = "1" ] && exit 0

# ── Emit the reminder ──────────────────────────────────────────────────────────
MSG="${SENTINEL}. You changed code this session but have not run a code review yet. Before finishing, run a code review now — use the /code-review skill (or a code-reviewer agent such as superpowers:requesting-code-review / the code-reviewer subagent). IMPORTANT: keep iterating — run the review, address every finding, then re-run the review, repeating until it comes back entirely clean with no remaining issues. Do not stop after a single review pass."

reminder_emit_stop "$MSG"

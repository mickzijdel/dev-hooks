#!/bin/bash
# Stop hook: once per substantial session, remind Claude to review the session for
# durable, non-obvious facts worth saving to its file-based memory — then stop.
#
# A shell script can't judge what is memory-worthy; that judgment lives in Claude's
# CLAUDE.md memory rules. So this hook only *prompts* Claude to apply that judgment.
# It writes nothing itself and is constrained (in the reminder text) to the memory dir,
# never CLAUDE.md.
#
# Three gates, all must pass or we stay silent (exit 0):
#   1. Memory system in use — DEV_HOOKS_MEMORY=1 (opt-in) OR any ~/.claude/projects/*/memory
#      dir exists (global signal). Keeps the plugin a no-op for installers who don't use
#      the memory feature, while avoiding a per-project cold start.
#   2. Substantial session — >= DEV_HOOKS_MEMORY_MIN_TURNS (default 6) human turns.
#   3. Once per session — a sentinel embedded in the reminder; if already in the
#      transcript we've prompted already, so stay silent. Prevents any Stop loop.

MIN_TURNS="${DEV_HOOKS_MEMORY_MIN_TURNS:-6}"

# Sentinel embedded in our reminder; finding it in the transcript means we already
# prompted this session.
SENTINEL="[memory-reminder] session learnings not yet captured this session"

# ── Gate 1: memory system in use (opt-in OR global signal) ──────────────────────
if [ "$DEV_HOOKS_MEMORY" != "1" ]; then
  found_memory=$(find "$HOME/.claude/projects" -maxdepth 2 -mindepth 2 \
    -name memory -type d -print -quit 2>/dev/null)
  [ -z "$found_memory" ] && exit 0
fi

# ── Read hook input ──────────────────────────────────────────────────────────────
INPUT=$(cat 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

# Without a transcript we can't judge substance or the once-per-session guard.
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

# ── Gates 2 & 3: one transcript pass ─────────────────────────────────────────────
# Prints "skip" if the sentinel is already present (already prompted), otherwise the
# integer count of human turns (user messages that aren't pure tool_result records).
RESULT=$(
  python3 - "$TRANSCRIPT" "$SENTINEL" <<'PYEOF'
import sys, json

path, sentinel = sys.argv[1], sys.argv[2]


def is_human_turn(rec):
    """True for a user message that carries real human input (not just a tool_result)."""
    msg = rec.get("message", rec)
    if not isinstance(msg, dict) or msg.get("role") != "user":
        return False
    content = msg.get("content")
    if isinstance(content, str):
        return content.strip() != ""
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") != "tool_result":
                return True
    return False


turns = 0
try:
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if sentinel in line:
                print("skip")
                sys.exit(0)
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if is_human_turn(rec):
                turns += 1
except OSError:
    pass

print(turns)
PYEOF
)

[ "$RESULT" = "skip" ] && exit 0
# Non-numeric (shouldn't happen) or below threshold → trivial session, stay silent.
case "$RESULT" in
  '' | *[!0-9]*) exit 0 ;;
esac
[ "$RESULT" -lt "$MIN_TURNS" ] && exit 0

# ── Emit the reminder ────────────────────────────────────────────────────────────
MSG="${SENTINEL}. Before finishing, review this session for durable, non-obvious facts worth saving to your file-based memory, following the memory instructions in your CLAUDE.md (one fact per file with frontmatter, plus a one-line pointer in MEMORY.md). Scope: write ONLY to your memory directory — do NOT edit CLAUDE.md. Dedupe first: check MEMORY.md and update an existing file rather than creating a duplicate. IMPORTANT escape hatch: if nothing here is durable and non-obvious — or it's already captured by the repo, git history, or CLAUDE.md — then save NOTHING. Say 'nothing worth saving' in one line and stop. Do not invent memories to satisfy this reminder."

jq -cn --arg msg "$MSG" '{continue: false, hookSpecificOutput: {hookEventName: "Stop", additionalContext: $msg}}'
exit 2

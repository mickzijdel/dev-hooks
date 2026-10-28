#!/bin/bash
# bet: model won't stop to ask whether a session's work should become, or improve, a skill
# sunset: model proposes skill changes unprompted after working out a repeatable procedure
# Stop hook: once per substantial session, ask Claude whether the session worked out a
# repeatable procedure or hit a mistake an existing skill should have prevented, and if so
# to append a proposal to the skill-candidate queue, which weekly-automation-review triages.
# It only proposes: creating or editing the skill is the weekly review's call, so the queue
# collects candidates without piling up untested skills.
#
# Gates, all must pass or we stay silent (exit 0):
#   1. The automation-review dir exists (~/.claude/automation-review: the prompt log and
#      weekly review are in use; the queue lives there beside them).
#   2. Substantial session: >= DEV_HOOKS_SKILL_CANDIDATE_MIN_TURNS (default 6) human turns.
#   3. Once per session: the sentinel embedded in the reminder isn't in the transcript yet.
#   4. Nothing proposed yet: no Write/Edit to the queue this session (a subagent's via the
#      mod's DEV_HOOKS_FACTS_FILE).
# Opt out with DEV_HOOKS_SKILL_CANDIDATES=false.

MIN_TURNS="${DEV_HOOKS_SKILL_CANDIDATE_MIN_TURNS:-6}"

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

reminder_opt_out DEV_HOOKS_SKILL_CANDIDATES
[ -d "$HOME/.claude/automation-review" ] || exit 0

SENTINEL="[skill-candidate-reminder] skill candidates not yet reviewed this session"
reminder_stop_init "$SENTINEL"
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

# "skip" when already asked or already proposed, else the human-turn count.
RESULT=$(
  python3 - "$TRANSCRIPT" "$SENTINEL" "$REMINDER_LIB_DIR" "${DEV_HOOKS_FACTS_FILE:-}" <<'PYEOF'
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[3])
from hook_helpers import SKILL_QUEUE_RE, human_turns, path_written

n = human_turns(sys.argv[1], sys.argv[2])
queued = path_written(sys.argv[1], sys.argv[4] or None, SKILL_QUEUE_RE)
print("skip" if n is None or queued else n)
PYEOF
)
case "$RESULT" in
  '' | *[!0-9]*) exit 0 ;;
esac
[ "$RESULT" -lt "$MIN_TURNS" ] && exit 0

MSG="${SENTINEL}. Before finishing, ask: did this session work out a repeatable multi-step procedure, or hit a mistake that an existing skill should have prevented? If so, append one entry per candidate to ~/.claude/automation-review/skill-candidates.md with the Write or Edit tool (create the file if it's missing), in this shape:

## <YYYY-MM-DD> · <repo or folder> · amend <plugin:skill> | new <name>
- Trigger: <when it should fire, in the words a user would type>
- Should fire: \"<prompt>\", \"<prompt>\", \"<prompt>\"
- Should not fire: \"<prompt>\", \"<prompt>\", \"<prompt>\"
- Evidence: <what this session did or got wrong that the skill would capture>
- Status: open

Prefer amending an existing skill to a new one. Propose only: do NOT create or edit a skill now, the weekly review decides. If nothing qualifies, say 'nothing to propose' in one line and stop."

reminder_emit_stop "$MSG"

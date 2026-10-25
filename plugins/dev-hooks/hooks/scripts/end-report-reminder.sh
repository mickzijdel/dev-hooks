#!/bin/bash
# bet: model won't close a working turn with a message that stands alone: what changed, what the person must do
# sunset: work turns' last messages reliably carry Changed and Your move lines unprompted
# Stop: on a turn that did work (a file edit, or DEV_HOOKS_END_REPORT_TOOLS tool calls,
# default 10), block when Claude's last message has no Changed or Your move line: that
# message is what the person reads on coming back to the session. The footer
# reminder_emit_stop adds names the whole report. --when-active: it also checks the reply
# another Stop hook forced, still blocking at most once per natural stop. Skips headless
# runs (claude -p, the Agent SDK), whose end report nobody reads. Opt out with
# DEV_HOOKS_END_REPORT=false.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

reminder_opt_out DEV_HOOKS_END_REPORT
reminder_is_headless && exit 0
reminder_stop_init "" --when-active

# A natural stop clears the mark; a forced one honours it.
reminder_state_file end-report
MARK=$REPLY
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  [ -e "$MARK" ] && exit 0
else
  rm -f "$MARK"
fi

reminder_mktemp
printf '%s' "$INPUT" >"$REPLY"
MISSING=$(
  python3 - "$SELF_DIR/lib" "$REPLY" "${DEV_HOOKS_END_REPORT_TOOLS:-10}" <<'PYEOF'
import json, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
from hook_helpers import end_report_missing, turn_activity
with open(sys.argv[2], encoding="utf-8") as f:
    payload = json.load(f)
last = payload.get("last_assistant_message") or ""
calls, edits = turn_activity(payload.get("transcript_path") or "")
if last and (edits or calls >= int(sys.argv[3])):
    print(" or ".join(end_report_missing(last)))
PYEOF
)
[ -z "$MISSING" ] && exit 0

: >"$MARK"
reminder_emit_stop "[end-report] This turn did work, and your last message has no $MISSING line. That message is what the person reads when they come back to this session, so it has to stand alone."

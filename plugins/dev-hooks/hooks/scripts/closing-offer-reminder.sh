#!/bin/bash
# bet: model closes a turn by offering work it could undo ("Want me to…?") instead of doing it
# sunset: turns reliably end on finished work, or on an ask that says why it is the person's call
# Stop: block once when the close of Claude's last message (its last lines, or its Your
# move block) offers undone work: "Want me to…?", "Should I also…?", "Shall I…?", "Would
# you like me to…?", "Let me know if you want…", "Next steps could be…". Silent on an ask
# that is the person's call (merge, push, send, deploy, delete, spend, a message to a
# person, "Archive this session?") and on a message that names the rule that stopped the
# work. --when-active: it also checks the reply another Stop hook forced, the message the
# person reads last, still blocking at most once per natural stop. Runs headless too: an
# offer there is work left undone. Opt out with DEV_HOOKS_CLOSING_OFFER=false.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

reminder_opt_out DEV_HOOKS_CLOSING_OFFER
reminder_stop_init "" --when-active

# A natural stop clears the mark; a forced one honours it.
reminder_state_file closing-offer
MARK=$REPLY
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  [ -e "$MARK" ] && exit 0
else
  rm -f "$MARK"
fi

reminder_mktemp
printf '%s' "$INPUT" >"$REPLY"
OFFER=$(
  PYTHONUTF8=1 python3 - "$SELF_DIR/lib" "$REPLY" <<'PYEOF'
import json, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
from hook_helpers import closing_offer, last_turn_text
with open(sys.argv[2], encoding="utf-8") as f:
    payload = json.load(f)
last = payload.get("last_assistant_message") or last_turn_text(
    payload.get("transcript_path") or ""
)
print(closing_offer(last))
PYEOF
)
[ -z "$OFFER" ] && exit 0

: >"$MARK"
# jq --arg carries $OFFER, so its quotes and backslashes are data.
reminder_emit_stop "[closing-offer] Your last message ends on an offer instead of finished work: \"$OFFER\". If the offered work can be undone and your tools can do it, do it now and report it as done. If it can't, say which rule stops you: a one-way action, a write to production, a message to a person, spending money, or a step that needs the person's sign-in or decision."

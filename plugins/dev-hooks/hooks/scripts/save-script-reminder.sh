#!/bin/bash
# Stop hook: if Claude wrote one-off scripts this session, nudge it to keep the reusable
# ones — genericize them to the saved-script standard (PEP 723 + `uv run` shebang +
# `# short-description:` + chmod +x) and move them into ~/.local/bin, where they go on
# PATH and get surfaced next session by the script-index hook.
#
# "Wrote a script" = a Write tool call whose content begins with a shebang (`#!`), found
# by scanning the session transcript. Two locations are excluded as already-kept, not
# throwaways: the library dir itself, and the project working dir (committed repo work).
# What's left is the ephemeral one-offs (scratchpad, /tmp, …). Known limitation: a script
# created via a Bash heredoc rather than the Write tool isn't detected — Write is the
# common case.
#
# Fires at most once per session (its own sentinel guards against a Stop loop). Opt out
# with DEV_HOOKS_SAVE_SCRIPT=false. The library is DEV_HOOKS_SCRIPT_DIR — a colon-separated
# list of roots like PATH (default ~/.local/bin); every root is excluded from the nudge.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

reminder_opt_out DEV_HOOKS_SAVE_SCRIPT

SCRIPT_DIR="${DEV_HOOKS_SCRIPT_DIR:-$HOME/.local/bin}"

# Sentinel embedded in the reminder; finding it in the transcript means we already prompted.
SENTINEL="[save-script-reminder] reusable one-off scripts not yet saved this session"

# Sets INPUT/TRANSCRIPT; exits 0 on the sentinel fast path.
reminder_stop_init "$SENTINEL"
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

# The project working dir (committed work is excluded from the nudge).
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"

# List the ephemeral scripts Claude wrote this session (one path per line). The colon-list of
# library roots and the project cwd are all excluded. argv, not stdin (heredocs can't read
# piped stdin — see CLAUDE.md).
SCRIPTS=$(
  python3 - "$SELF_DIR/lib" "$TRANSCRIPT" "$SCRIPT_DIR" "$CWD" <<'PYEOF'
import sys

sys.path.insert(0, sys.argv[1])
from hook_helpers import authored_scripts

exclude = [r for r in sys.argv[3].split(":") if r] + [sys.argv[4]]
for path in authored_scripts(sys.argv[2], exclude):
    print(path)
PYEOF
)

[ -z "$SCRIPTS" ] && exit 0

# Suggest the first library root as the destination (subdirectories are fine).
PRIMARY="${SCRIPT_DIR%%:*}"
LIST=$(printf '%s' "$SCRIPTS" | sed 's/^/  - /')
MSG="${SENTINEL}. You wrote these one-off script(s) this session:
${LIST}
If any is reusable beyond this task, don't throw it away: genericize it to the saved-script standard (PEP 723 inline metadata, a '#!/usr/bin/env -S uv run --script' shebang, a '# short-description:' line, an argparse --help, and chmod +x) and move it into your script library (${PRIMARY}, or a subdirectory of it) so it is surfaced next session by the script-index hook. Follow the script-library skill. If nothing here is reusable beyond this task, say so in one line and stop — don't save throwaways."

reminder_emit_stop "$MSG"

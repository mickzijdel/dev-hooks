#!/bin/bash
# bet: model leaves TODO/FIXME markers in when finishing
# sunset: model reliably resolves or consciously flags its own markers
# Stop hook: list TODO/FIXME/XXX/HACK markers Claude *newly introduced* this session so they
# get resolved (or consciously kept) before finishing. Advisory — feeds the findings back via
# exit 2; never edits or hard-blocks.
#
# Only NEW lines count: added lines in `git diff HEAD` plus the full contents of untracked
# files (the shared walker in lib/hook_helpers.py). Pre-existing markers (already committed,
# unchanged) are ignored, so committing or removing the marker clears the nudge. Test
# files/dirs are excluded — leftover-marker hygiene is about shipped code.
#
# Fires at most once per session: its own sentinel string, once emitted, lands in the
# transcript, and finding it there on a later Stop suppresses a re-fire (no Stop loop).
#
# Opt out per repo/user with DEV_HOOKS_TODO_LEFTOVER=false (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
reminder_opt_out DEV_HOOKS_TODO_LEFTOVER

# Must be a git repo (diff-based detection needs one).
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

SENTINEL="[todo-leftover] new TODO/FIXME markers added this session"

# Sets INPUT/TRANSCRIPT; exits 0 if the sentinel is already in the transcript
# (already nudged this session — prevents a Stop loop).
reminder_stop_init "$SENTINEL"

FINDINGS=$(
  python3 - "$SELF_DIR/lib" <<'PYEOF'
import re
import sys

sys.dont_write_bytecode = True  # no __pycache__ in the plugin's lib dir
sys.path.insert(0, sys.argv[1])
from hook_helpers import collect_new_line_hits, is_test_path

# Uppercase markers only, on a word boundary that isn't a longer identifier — so a `todoList`
# variable or the word "hack" in prose doesn't match, but `TODO:`, `# FIXME`, `XXX(name)` do.
MARKER = re.compile(r"(?<![A-Za-z])(TODO|FIXME|XXX|HACK)(?![A-Za-z])")

shown = collect_new_line_hits(
    lambda path, text: not is_test_path(path) and bool(MARKER.search(text))
)
if shown:
    print("\n".join(shown))
PYEOF
)

[ -z "$FINDINGS" ] && exit 0

MSG="${SENTINEL}. You added these markers this session — resolve them before finishing, or, if one is a deliberate tracked follow-up, keep it and ignore this:"$'\n'"$FINDINGS"

reminder_emit_stop "$MSG"

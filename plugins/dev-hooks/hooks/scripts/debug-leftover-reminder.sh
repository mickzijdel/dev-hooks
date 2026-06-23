#!/bin/bash
# Stop hook: flag debug statements Claude *newly introduced* this session (console.log,
# debugger, binding.pry, breakpoint(), pdb, Ruby `p`, ...) so they get stripped before
# finishing. Advisory — feeds the findings back via exit 2; never edits or hard-blocks.
#
# Only NEW lines are considered: added lines in `git diff HEAD` plus the full contents of
# untracked files. Pre-existing debug lines (already committed, unchanged) are ignored, so
# committing or removing the lines clears the nudge. Test files/dirs are excluded.
#
# Fires at most once per session: its own sentinel string, once emitted, lands in the
# transcript, and finding it there on a later Stop suppresses a re-fire (no Stop loop).
#
# Opt out per repo/user with DEV_HOOKS_DEBUG_LEFTOVER=false (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
reminder_opt_out DEV_HOOKS_DEBUG_LEFTOVER

# Must be a git repo (diff-based detection needs one).
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

SENTINEL="[debug-leftover] new debug statements detected this session"

# Sets INPUT/TRANSCRIPT; exits 0 if the sentinel is already in the transcript
# (already nudged this session — prevents a Stop loop).
reminder_stop_init "$SENTINEL"

FINDINGS=$(
  python3 - "$SELF_DIR/lib" <<'PYEOF'
import os
import re
import sys

sys.dont_write_bytecode = True  # no __pycache__ in the plugin's lib dir
sys.path.insert(0, sys.argv[1])
from hook_helpers import collect_new_line_hits, is_test_path

JS_EXT = {".js", ".ts", ".jsx", ".tsx", ".vue", ".mjs", ".cjs"}
PY_EXT = {".py"}
RB_EXT = {".rb", ".erb", ".rake"}

JS_PAT = re.compile(r"console\.(?:log|debug)\(|(?<![\w.])debugger\b")
PY_PAT = re.compile(r"\bbreakpoint\(\)|(?:^|[^\w.])i?pdb\.set_trace\(\)|^\s*import\s+i?pdb\b")
# Ruby debuggers, plus `p` used as a call: non-word/non-dot char before `p`, space/( after.
RB_PAT = re.compile(r"binding\.(?:pry|irb)|\bbyebug\b|(?<![\w.])debugger\b|(?:^|[^\w.])p[ (]")

PAT_FOR_EXT = {}
for e in JS_EXT:
    PAT_FOR_EXT[e] = JS_PAT
for e in PY_EXT:
    PAT_FOR_EXT[e] = PY_PAT
for e in RB_EXT:
    PAT_FOR_EXT[e] = RB_PAT


def keep(path, text):
    pat = PAT_FOR_EXT.get(os.path.splitext(path)[1])
    return pat is not None and not is_test_path(path) and bool(pat.search(text))


shown = collect_new_line_hits(keep)
if shown:
    print("\n".join(shown))
PYEOF
)

[ -z "$FINDINGS" ] && exit 0

MSG="${SENTINEL}. You introduced these debug statements this session — remove them before finishing (or, if one is intentional, keep it and ignore this):"$'\n'"$FINDINGS"

reminder_emit_stop "$MSG"

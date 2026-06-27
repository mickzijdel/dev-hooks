#!/bin/bash
# Stop hook: if Claude wrote a script this session, nudge it to DECIDE what the script
# deserves rather than leaving it where it landed — is it a broadly useful tool worth
# promoting to the saved-script library (genericized to the standard: PEP 723 + `uv run`
# shebang + `# short-description:` + chmod +x, moved into a library root or a subdirectory,
# surfaced next session by the script-index hook), or is it genuinely specific to this
# task/repo (leave it)? A script written *into a project repo* is included on purpose —
# being committed somewhere doesn't mean it shouldn't ALSO be a general tool. Claude makes
# the call per script.
#
# "Wrote a script" = a Write tool call whose content begins with a shebang (`#!`), found by
# scanning the session transcript. Only scripts already living in a library root are
# excluded (they're already saved). Known limitation: a script created via a Bash heredoc
# rather than the Write tool isn't detected — Write is the common case.
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
SENTINEL="[save-script-reminder] scripts written this session not yet triaged for the library"

# Sets INPUT/TRANSCRIPT; exits 0 on the sentinel fast path.
reminder_stop_init "$SENTINEL"
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

# List the scripts Claude wrote this session (one path per line). Only scripts already in a
# library root are excluded — in-repo scripts ARE listed, so Claude can decide whether each is
# project-specific or a general tool worth promoting. argv, not stdin (heredocs can't read
# piped stdin — see CLAUDE.md).
SCRIPTS=$(
  python3 - "$SELF_DIR/lib" "$TRANSCRIPT" "$SCRIPT_DIR" <<'PYEOF'
import sys

sys.path.insert(0, sys.argv[1])
from hook_helpers import authored_scripts

roots = [r for r in sys.argv[3].split(":") if r]
for path in authored_scripts(sys.argv[2], roots):
    print(path)
PYEOF
)

[ -z "$SCRIPTS" ] && exit 0

# Suggest the first library root as the destination (subdirectories are fine).
PRIMARY="${SCRIPT_DIR%%:*}"
LIST=$(printf '%s' "$SCRIPTS" | sed 's/^/  - /')
MSG="${SENTINEL}. You wrote these script(s) this session:
${LIST}
For each, decide what it deserves — don't just leave it where it happened to land:
- A broadly useful tool (you'd plausibly want it in another project or session)? Genericize it to the saved-script standard (PEP 723 inline metadata, a '#!/usr/bin/env -S uv run --script' shebang, a '# short-description:' line, an argparse --help, and chmod +x) and add it to your script library (${PRIMARY}, or a subdirectory of it) so it is reusable and shareable. A script already committed to a project repo can still be worth promoting to a general tool.
- Genuinely specific to this task/repo, or a throwaway? Leave it where it is.
Follow the script-library skill. If none here is worth promoting, say so in one line and stop."

reminder_emit_stop "$MSG"

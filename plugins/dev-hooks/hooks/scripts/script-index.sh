#!/bin/bash
# SessionStart hook: advertise the user's saved CLI script library (~/.local/bin by
# default) so Claude knows which custom tools already exist — a lightweight skill-style
# index. Lists each executable shebang script with its `# short-description:` line.
# Scripts lacking that marker are listed under a placeholder telling Claude to run
# `<name> --help` for detail and ask the user to add a description (see the
# script-library skill).
#
# The hook never EXECUTES any script — running every tool's --help at session start would
# be slow and could have side effects. It only reads the first lines for the description
# and tells Claude it may run --help itself when it decides to use one.
#
# Opt out with DEV_HOOKS_SCRIPT_INDEX=false. Override the scanned dir with
# DEV_HOOKS_SCRIPT_DIR (defaults to ~/.local/bin; used mainly by the tests).

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

reminder_opt_out DEV_HOOKS_SCRIPT_INDEX

SCRIPT_DIR="${DEV_HOOKS_SCRIPT_DIR:-$HOME/.local/bin}"
[ -d "$SCRIPT_DIR" ] || exit 0

# python3 builds the message from the directory inventory (scan_script_dir). It prints
# nothing — and exits 0 — when there are no shebang scripts, so we stay silent. Pass the
# lib dir and target dir as argv (heredocs can't read piped stdin — see CLAUDE.md).
MSG=$(
  python3 - "$SELF_DIR/lib" "$SCRIPT_DIR" <<'PYEOF'
import sys

sys.path.insert(0, sys.argv[1])
from hook_helpers import scan_script_dir

script_dir = sys.argv[2]
described, undescribed = scan_script_dir(script_dir)
if not described and not undescribed:
    sys.exit(0)

out = [
    f"Custom CLI tools available in {script_dir} (the user's saved script library, on PATH). "
    "Reach for one before re-solving a problem it already handles; run `<name> --help` for "
    "usage before using it."
]
for name, desc in described:
    out.append(f"- {name} — {desc}")
if undescribed:
    out.append(
        "No `# short-description:` line, so no summary for: "
        + ", ".join(undescribed)
        + ". If you use one of these, run `<name> --help` for detail and tell the user to add "
        "a `# short-description:` line so it is described next time (see the script-library skill)."
    )
print("\n".join(out))
PYEOF
)

[ -z "$MSG" ] && exit 0
reminder_emit_session "$MSG"

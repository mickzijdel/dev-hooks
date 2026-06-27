#!/bin/bash
# SessionStart hook: advertise the user's saved CLI script library so Claude knows which
# custom tools already exist — a lightweight skill-style index. Lists each executable
# shebang script (recursively, so a script repo organised into subdirectories works) with
# its `# short-description:` line. Scripts lacking that marker are listed under a placeholder
# telling Claude to run `<path> --help` for detail and ask the user to add a description
# (see the script-library skill).
#
# The library is one or more roots in DEV_HOOKS_SCRIPT_DIR — a colon-separated list like
# PATH (default ~/.local/bin), so you can keep personal scripts AND a cloned, shareable
# scripts repo, e.g. ~/.local/bin:~/code/team-scripts. Each root is scanned recursively.
#
# The hook never EXECUTES any script — running every tool's --help at session start would
# be slow and could have side effects. It only reads the first lines for the description
# and tells Claude it may run --help itself when it decides to use one.
#
# Hide scripts you don't want indexed (installed/third-party tools, app launchers) with
# DEV_HOOKS_SCRIPT_IGNORE — a colon-separated list of globs matched against each script's
# basename or full path, e.g. "*vocalinux*:gext:gnome-extensions-cli".
#
# Opt out entirely with DEV_HOOKS_SCRIPT_INDEX=false.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

reminder_opt_out DEV_HOOKS_SCRIPT_INDEX

SCRIPT_DIR="${DEV_HOOKS_SCRIPT_DIR:-$HOME/.local/bin}"

# python3 builds the message from the library inventory (scan_script_dirs). It prints nothing
# — and exits 0 — when no root holds a shebang script, so we stay silent. The colon-separated
# root list, $HOME (for ~-collapsing the displayed paths), and the colon-separated ignore
# globs are passed as argv; heredocs can't read piped stdin (see CLAUDE.md).
MSG=$(
  python3 - "$SELF_DIR/lib" "$SCRIPT_DIR" "$HOME" "${DEV_HOOKS_SCRIPT_IGNORE:-}" <<'PYEOF'
import sys

sys.path.insert(0, sys.argv[1])
from hook_helpers import scan_script_dirs

roots = [r for r in sys.argv[2].split(":") if r]
home = sys.argv[3]
ignore = [p for p in sys.argv[4].split(":") if p]
described, undescribed = scan_script_dirs(roots, ignore)
if not described and not undescribed:
    sys.exit(0)


def show(path):
    """Collapse $HOME to ~ for a compact display path."""
    return "~" + path[len(home) :] if home and path.startswith(home + "/") else path


out = [
    "Custom CLI tools in the user's saved script library. Reach for one before re-solving a "
    "problem it already handles; run `<path> --help` for usage first. A script in a PATH "
    "directory (e.g. ~/.local/bin) also runs by bare name; others run by their full path or "
    "via `uv run <path>`."
]
for path, desc in described:
    out.append(f"- {show(path)} — {desc}")
if undescribed:
    out.append(
        "No `# short-description:` line, so no summary for: "
        + ", ".join(show(p) for p in undescribed)
        + ". If you use one of these, run `<path> --help` for detail and tell the user to add "
        "a `# short-description:` line so it is described next time (see the script-library skill)."
    )
print("\n".join(out))
PYEOF
)

[ -z "$MSG" ] && exit 0
reminder_emit_session "$MSG"

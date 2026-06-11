#!/bin/bash
# PostToolUse(Write|Edit): when Claude writes popover/tooltip/dropdown/menu UI, nudge it to
# use a collision-aware positioner (flip + shift) rendered in the top layer / a portal, and
# point at the `popovers-tooltips` skill. Advisory only — emits additionalContext and always
# exits 0, never blocks the write.
#
# Detection is deliberately broad (per-project choice): a frontend file (.js/.ts/.erb/.html/
# .vue/.svelte/.haml/.slim) AND any popover/tooltip signal — a popover/tooltip/dropdown
# controller filename, role="tooltip"/the popover attribute, an @floating-ui/popper/tippy
# import, a data-controller naming one, OR a tooltip/popover/dropdown class or data-attribute.
#
# Fires at most once per session (marker under ${TMPDIR}).
# Opt out per repo/user with DEV_HOOKS_POPOVER=false (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
# Sets INPUT, FILE, SESSION, BASE (or exits 0 on opt-out / missing file_path).
reminder_init DEV_HOOKS_POPOVER

# File gate: only frontend markup/script/style files (shared list in the lib).
reminder_is_frontend_file "$BASE" || exit 0

# Content gate: a popover/tooltip signal in the filename or the file body.
SIGNAL=""
case "$BASE" in
  *popover* | *tooltip* | *dropdown* | *popper* | *floating*) SIGNAL=1 ;;
esac

if [ -z "$SIGNAL" ] && [ -f "$FILE" ]; then
  if grep -Eiq \
    -e 'role=["'\'']?tooltip' \
    -e '(^|[[:space:]<])popover([[:space:]=>"'\'']|$)|popovertarget' \
    -e '@floating-ui|popper\.js|popperjs|tippy' \
    -e 'data-controller=["'\''][^"'\'']*(popover|tooltip|dropdown|menu)' \
    -e 'class=["'\''][^"'\'']*(tooltip|popover|dropdown)' \
    -e 'data-[a-z-]*(tooltip|popover)' \
    "$FILE"; then
    SIGNAL=1
  fi
fi

[ -z "$SIGNAL" ] && exit 0

# Fire at most once per session.
MARKER_DIR="${TMPDIR:-/tmp}/dev-hooks-popover"
mkdir -p "$MARKER_DIR" 2>/dev/null
MARKER="$MARKER_DIR/${SESSION}"
[ -e "$MARKER" ] && exit 0
: >"$MARKER" 2>/dev/null

MSG="You just edited $BASE, which looks like popover/tooltip/dropdown UI. Tailwind styles but does NOT position — don't hand-roll top/left math, or it'll open off-screen or get clipped. Use a collision-aware positioner (offset + flip + shift) and render in the top layer / a portal so an overflow/transform/z-index ancestor can't clip it. See the \`popovers-tooltips\` skill: in Rails/Hotwire that's Floating UI (@floating-ui/dom) in a Stimulus controller with autoUpdate — and clean up in disconnect() (the Turbo gotcha). Simpler options: Tippy.js, or your Tailwind kit's component (Flowbite/Preline/daisyUI)."

jq -cn --arg msg "$MSG" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
exit 0

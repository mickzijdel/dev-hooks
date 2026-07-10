#!/bin/bash
# bet: model writes silent error swallows (bare except / empty catch / empty rescue)
# sunset: model reliably avoids blanket/empty exception handlers
# PostToolUse(Write|Edit|MultiEdit): when Claude writes an exception handler that silently
# swallows the error — a Python bare `except:` (or `except ...: pass`), an empty JS/TS
# `catch {}`, or an empty Ruby `rescue ... end` — nudge it to handle, log, or re-raise rather
# than discard. Advisory only — emits additionalContext and always exits 0, never blocks.
#
# Scans only what this call ADDS (Write content + Edit/MultiEdit new_strings), so it nudges
# on newly written handlers, not pre-existing ones. Detection is heuristic regex, not a
# parser; it's a reminder, not a gate.
#
# Fires at most once per session (marker under ${TMPDIR}).
# Opt out per repo/user with DEV_HOOKS_ERROR_SWALLOW=false (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
# Sets INPUT, FILE, SESSION, TOOL, BASE (or exits 0 on opt-out / missing file_path).
reminder_init DEV_HOOKS_ERROR_SWALLOW

reminder_content # sets CONTENT (Write content + Edit/MultiEdit new_strings)
[ -z "$CONTENT" ] && exit 0

reminder_mktemp
CONTENT_FILE=$REPLY
printf '%s' "$CONTENT" >"$CONTENT_FILE"

FOUND=$(
  python3 - "$CONTENT_FILE" <<'PYEOF'
import re
import sys

with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    content = fh.read()

hits = []

# Python: bare `except:`  OR  `except SomeError:` whose only body statement is `pass`.
if re.search(r"(?m)^\s*except\s*:", content):
    hits.append("a bare `except:` in Python")
elif re.search(r"(?ms)^[ \t]*except\b[^\n:]*:\s*(?:#.*)?\n[ \t]+pass\b", content):
    hits.append("an `except ...: pass` that swallows the error in Python")

# JS/TS: empty `catch { }` (whitespace/comments only between the braces).
if re.search(r"(?s)\bcatch\s*(?:\([^)]*\))?\s*\{\s*(?://[^\n]*|/\*.*?\*/|\s)*\}", content):
    hits.append("an empty `catch {}` block in JS/TS")

# Ruby: a `rescue` clause with nothing before the closing `end`/next clause.
if re.search(r"(?m)^\s*rescue\b[^\n]*\n\s*(?:end|ensure|else)\b", content):
    hits.append("an empty `rescue` in Ruby")

for h in hits:
    print(h)
PYEOF
)

[ -z "$FOUND" ] && exit 0

# Fire at most once per session.
reminder_fire_once error_swallow || exit 0

MSG="You just wrote an exception handler that silently swallows the error in $BASE:"$'\n'"$FOUND"$'\n\n'"A swallowed error hides real failures and makes bugs invisible. Instead: catch the *specific* exception you expect, then log it (with context) and/or re-raise — or let it propagate. If you genuinely must ignore it, narrow the catch to the exact exception and leave a comment saying why it's safe to ignore. Avoid bare \`except:\` (it also catches KeyboardInterrupt/SystemExit)."

reminder_emit "$MSG"

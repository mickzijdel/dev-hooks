#!/bin/bash
# PostToolUse(Write|Edit|MultiEdit): when Claude writes frontend markup with common
# accessibility gaps — an <img> without alt, an icon-only <button>/<a> with no accessible
# name, a click handler on a non-interactive <div>/<span>, or an unlabeled form <input> —
# flag them and point at the `accessibility` skill. Advisory only — emits additionalContext
# and always exits 0, never blocks the write.
#
# Scans only what this call ADDS (Write content + Edit/MultiEdit new_strings), so it nudges
# on new markup rather than re-flagging the whole file. Detection is heuristic (regex over
# markup, not a real parser) so it can over- or under-fire; it's a reminder, not a gate.
#
# Fires at most once per session (marker under ${TMPDIR}).
# Opt out per repo/user with DEV_HOOKS_A11Y=false (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
# Sets INPUT, FILE, SESSION, TOOL, BASE (or exits 0 on opt-out / missing file_path).
reminder_init DEV_HOOKS_A11Y

# File gate: only frontend markup/script/style files (shared list in the lib).
reminder_is_frontend_file "$BASE" || exit 0

reminder_content # sets CONTENT (Write content + Edit/MultiEdit new_strings)
[ -z "$CONTENT" ] && exit 0

reminder_mktemp
CONTENT_FILE=$REPLY
printf '%s' "$CONTENT" >"$CONTENT_FILE"

ISSUES=$(
  python3 - "$CONTENT_FILE" <<'PYEOF'
import re
import sys

with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    content = fh.read()

issues = []


def has_attr(tag, *names):
    return any(re.search(r"(?i)\b" + n + r"\b", tag) for n in names)


# <img> without alt (alt="" is allowed — it's the decorative-image opt-out).
for m in re.finditer(r"(?is)<img\b[^>]*>", content):
    if not has_attr(m.group(0), "alt"):
        issues.append("an <img> with no alt attribute (use alt=\"\" only for decorative images)")
        break

# Icon-only <button>/<a>: an element whose content is only an icon (<svg>/<i>/<img>) with no
# text and no accessible name (aria-label / aria-labelledby / title).
for tag in ("button", "a"):
    for m in re.finditer(r"(?is)<" + tag + r"\b([^>]*)>(.*?)</" + tag + r">", content):
        attrs, inner = m.group(1), m.group(2)
        if has_attr(attrs, "aria-label", "aria-labelledby", "title"):
            continue
        text = re.sub(r"(?s)<[^>]+>", "", inner).strip()
        if text:
            continue
        if re.search(r"(?is)<(svg|i|img|use|span)\b", inner):
            issues.append(f"an icon-only <{tag}> with no accessible name (add aria-label)")
            break

# Click handler on a non-interactive element (div/span) — not keyboard-reachable.
if re.search(
    r"(?is)<(?:div|span)\b[^>]*\b(?:onclick|@click|v-on:click|\(click\)|data-action\s*=\s*[\"'][^\"']*click)",
    content,
):
    issues.append("a click handler on a non-interactive <div>/<span> (use a <button>, or add role + tabindex + key handling)")

# Form <input> (not hidden/submit/button) with no label association and no aria-label/id.
for m in re.finditer(r"(?is)<input\b[^>]*>", content):
    tag = m.group(0)
    tm = re.search(r"(?i)\btype\s*=\s*[\"']?([a-z]+)", tag)
    if tm and tm.group(1).lower() in ("hidden", "submit", "button", "reset", "image"):
        continue
    if not has_attr(tag, "aria-label", "aria-labelledby", "id", "title"):
        issues.append("an <input> with no label association (add a <label for>, aria-label, or aria-labelledby)")
        break

for line in issues:
    print(line)
PYEOF
)

[ -z "$ISSUES" ] && exit 0

# Fire at most once per session.
reminder_fire_once a11y || exit 0

MSG="You just edited $BASE and it has likely accessibility gaps:"$'\n'"$ISSUES"$'\n\n'"See the \`accessibility\` skill for the WCAG 2.2 / ARIA checklist and framework-specific fixes (Rails/Hotwire + React). Quick rules: every image needs alt text (empty alt for decorative), interactive controls need an accessible name, only real interactive elements (button/a/input) should handle clicks, and every input needs an associated label. If a flag is a false positive, ignore it."

reminder_emit "$MSG"

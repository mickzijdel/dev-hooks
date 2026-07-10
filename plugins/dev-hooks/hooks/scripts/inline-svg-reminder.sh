#!/bin/bash
# bet: model hand-rolls inline SVG instead of the project's icon library
# sunset: model reliably prefers an icon library / sprite in app source
# PostToolUse(Write|Edit|MultiEdit): when Claude hand-writes inline SVG markup (an <svg> blob with
# real drawing content, or a data:image/svg+xml URI) into a source file, feed a correction
# back via exit 2: use the project's icon library, or extract the markup to a dedicated
# .svg file and reference it. The write has already landed — the feedback tells Claude to
# refactor it now. Unlike the advisory reminders, this fires on EVERY occurrence.
#
# Good patterns stay silent: <svg><use href="sprite.svg#id"> references, writing actual
# .svg files, <img src="x.svg">, markdown/docs, test files, and data-driven SVG (drawing
# tags with JSX-expression attributes like <rect x={scale(d)}> — charts, not icons).
# Pre-existing SVG doesn't re-fire: Writes are deduped against the file at HEAD, Edits
# against old_string, keyed on the drawing data so attribute tweaks on an approved icon
# stay silent.
#
# Opt out per repo/user with DEV_HOOKS_SVG_INLINE=false (in .claude settings "env").

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"
# Sets INPUT, FILE, SESSION, TOOL, BASE (or exits 0 on opt-out / missing file_path).
reminder_init DEV_HOOKS_SVG_INLINE

# Only frontend-ish files where inline icons end up. Everything else — notably .svg files
# themselves (writing one is the desired refactor outcome, which lets the refactor
# converge) and markdown/docs — stays silent.
reminder_is_frontend_file "$BASE" || exit 0

# SVG fixtures in tests are legitimate; an every-occurrence exit-2 hook must stay quiet there.
reminder_is_test_path "$FILE" && exit 0

reminder_content # sets CONTENT (Write content + Edit/MultiEdit new_strings)

# Cheap pre-filter: stay python-free unless there is any svg-ish substring at all.
# nocasematch keeps it in sync with the case-insensitive python regexes below.
shopt -s nocasematch
case "$CONTENT" in
  *'<svg'* | *'<path'* | *'data:image/svg+xml'*) ;;
  *) exit 0 ;;
esac
shopt -u nocasematch

reminder_old_content # sets OLD (Edit/MultiEdit old_strings) for the dedup pass

reminder_mktemp
CONTENT_FILE=$REPLY
reminder_mktemp
OLD_FILE=$REPLY
printf '%s' "$CONTENT" >"$CONTENT_FILE"
printf '%s' "$OLD" >"$OLD_FILE"

FOUND=$(
  python3 - "$CONTENT_FILE" "$OLD_FILE" "$TOOL" "$FILE" "$SELF_DIR/lib" <<'PYEOF'
import os
import re
import sys

sys.dont_write_bytecode = True  # no __pycache__ in the plugin's lib dir
sys.path.insert(0, sys.argv[5])
from hook_helpers import git

with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    content = fh.read()
with open(sys.argv[2], encoding="utf-8", errors="replace") as fh:
    old_string = fh.read()
tool = sys.argv[3] if len(sys.argv) > 3 else ""
file_path = sys.argv[4] if len(sys.argv) > 4 else ""

SVG_BLOCK = re.compile(r"<svg\b[^>]*>.*?</svg\s*>", re.I | re.S)
# (?=[\s/>]) keeps custom elements like <line-chart> from matching; [^>]* grabs the
# attributes so literal_draw can tell static markup from JSX expressions.
DRAW_TAG = re.compile(r"<(?:path|circle|rect|polygon|polyline|ellipse|line)(?=[\s/>])[^>]*", re.I)
# Real path data: a path command followed by enough payload to rule out stubs. The
# leading command char rules out non-SVG d= attributes, and the lookbehind keeps bound
# attributes (:d="lineGenerator(...)", data-d=) from counting as literal data.
PATH_DATA = re.compile(
    r"""(?<![\w:.-])d\s*=\s*["'][MmLlHhVvCcSsQqTtAaZz][^"']{15,}["']""", re.I
)
# Any d= attribute — for dedup keys, where PATH_DATA's anti-stub length floor would
# wrongly re-key short icons on attribute tweaks.
D_ATTR = re.compile(r"""(?<![\w:.-])d\s*=\s*["'][^"']+["']""", re.I)
# Expression-bound attributes: JSX/Svelte x={...}, Vue :x="..."/v-bind:x, Angular [attr.x].
DYNAMIC_ATTR = re.compile(r"=\{|[\s\"'](?::[\w.-]+|v-bind:[\w.-]+|\[[\w.-]+\])=")
# Captures through the URI body so the dedup key is the URI itself, not its surroundings.
DATA_URI = re.compile(r"""data:image/svg\+xml[;,][^"'()\s]*""", re.I)
# Hand-written icons are tiny; skip generated bundles (also bounds the regex scans).
MAX_SCAN = 500_000


def literal_draw(text):
    """First drawing tag whose attributes are literal markup, not bound expressions.

    <rect x={scale(d)}> / <rect :x="scale(d)"> is a chart, not an icon — an icon
    library can't replace it."""
    for m in DRAW_TAG.finditer(text):
        if not DYNAMIC_ATTR.search(m.group(0)):
            return m
    return None


def findings(text):
    """Snippets of hand-written SVG. <use>/<title>-only blocks (sprite refs) pass."""
    if len(text) > MAX_SCAN:
        return []
    out = []
    spans = []
    for m in SVG_BLOCK.finditer(text):
        spans.append(m.span())
        block = m.group(0)
        if literal_draw(block) or PATH_DATA.search(block):
            out.append(block)
    # Partial fragments (an Edit often has no closing </svg>, or adds a <path> into an
    # existing svg): look at the text minus the complete blocks. A lone drawing tag only
    # counts alongside an opening <svg or literal path data.
    prev, parts = 0, []
    for start, end in spans:
        parts.append(text[prev:start])
        prev = end
    parts.append(text[prev:])
    rest = "".join(parts)
    draw = literal_draw(rest)
    open_svg = re.search(r"<svg\b", rest, re.I)
    path_data = PATH_DATA.search(rest)
    # Literal path data is hand-written even on an expression-bound tag; a lone literal
    # drawing tag needs an opening <svg for context.
    if path_data or (draw and open_svg):
        anchor = open_svg or draw or path_data
        out.append(rest[anchor.start():anchor.start() + 300])
    out.extend(m.group(0) for m in DATA_URI.finditer(text))
    return out


def key(snippet):
    """Dedup key: the drawing data (d= attrs, else the drawing tags) when present, so
    editing a class/viewBox on an already-approved icon doesn't re-flag it; the whole
    snippet (e.g. a data URI) otherwise."""
    parts = D_ATTR.findall(snippet) or [m.group(0) for m in DRAW_TAG.finditer(snippet)]
    return re.sub(r"\s+", " ", " ".join(parts) if parts else snippet).strip()[:300]


new = [(key(s), s) for s in findings(content)]
if not new:
    sys.exit(0)

# Pre-existing SVG isn't a new offence. For Edits the prior text is old_string; for
# full-file Writes (which re-send pre-existing content) it's the file at HEAD.
# Untracked file / no repo / git error -> no prior content, everything counts as new.
prior = old_string
if tool == "Write" and file_path:
    top = git(["-C", os.path.dirname(file_path) or ".", "rev-parse", "--show-toplevel"]).strip()
    if top:
        # realpath both sides: a symlinked checkout otherwise yields a ../ relpath.
        rel = os.path.relpath(os.path.realpath(file_path), os.path.realpath(top))
        prior = git(["-C", top, "show", f"HEAD:{rel}"])
old_keys = {key(s) for s in findings(prior)}

fresh = [s for k, s in new if k not in old_keys]
if fresh:
    print(re.sub(r"\s+", " ", fresh[0]).strip()[:120])
PYEOF
)

[ -z "$FOUND" ] && exit 0

# Name the project's icon library when one is already a dependency (best effort).
LIB_HINT="check package.json / Gemfile for one (lucide, heroicons, tabler, font-awesome, ...) before hand-rolling icons"
TOP=$(git -C "${FILE%/*}" rev-parse --show-toplevel 2>/dev/null)
if [ -n "$TOP" ]; then
  LIB=$(grep -Eohs \
    'lucide[a-z-]*|heroicons?|@tabler/icons[a-z-]*|react-icons|@fortawesome/[a-z-]+|font-?awesome[a-z_-]*|phosphor-[a-z-]+|@iconify/[a-z-]+|feather-icons|bootstrap-icons|@mui/icons-material|primeicons|inline_svg|rails_icons' \
    "$TOP/package.json" "$TOP/Gemfile" | head -n1)
  [ -n "$LIB" ] && LIB_HINT="this project already uses \"$LIB\" — use it"
fi

MSG="[inline-svg] You just wrote inline SVG markup into ${BASE}:
  ${FOUND}
Don't hand-write <svg>/<path> blobs (or data:image/svg+xml URIs) in source files — they're inconsistent, unmaintainable, and often render badly. Refactor, in order of preference:
1. Use the project's icon library — ${LIB_HINT}.
2. Otherwise extract the markup to a dedicated .svg file (or the existing sprite) and reference it: <img src>, <svg><use href=\"sprite.svg#id\"/></svg>, or the framework's icon helper.
3. Keep it inline only if the user explicitly asked for inline SVG — say so and continue.
The write already landed; fix the file now."

printf '%s\n' "$MSG" >&2
exit 2

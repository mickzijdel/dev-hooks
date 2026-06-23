#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Heuristic accessibility audit for web markup.

Scans HTML / ERB / HAML / Slim / JSX / TSX / Vue / Svelte files for the high-signal,
mechanically-detectable WCAG issues and prints `file:line: issue` for each. It is a regex
scanner, not a DOM/parser — it catches the common mistakes but can't judge contrast, focus
order, or whether an alt text is *good*. See ../references/checklist.md for the full review.

Usage: a11y_audit.py <file> [<file> ...]
Exit code: 0 = no issues found, 1 = issues found, 2 = no readable files given.
"""

import re
import sys
from pathlib import Path

MARKUP_EXT = {
    ".html",
    ".htm",
    ".erb",
    ".haml",
    ".slim",
    ".php",
    ".twig",
    ".heex",
    ".jsx",
    ".tsx",
    ".vue",
    ".svelte",
    ".astro",
}

IMG = re.compile(r"(?is)<img\b[^>]*>")
HTML_TAG = re.compile(r"(?is)<html\b[^>]*>")
INPUT = re.compile(r"(?is)<input\b[^>]*>")
TABINDEX = re.compile(r"""(?i)\btabindex\s*=\s*["']?\s*([1-9][0-9]*)""")
CLICK_ON_DIV = re.compile(
    r"(?is)<(?:div|span)\b[^>]*\b(?:onclick|@click|v-on:click|\(click\)"
    r"|data-action\s*=\s*[\"'][^\"']*click)[^>]*>"
)
NAMED = ("aria-label", "aria-labelledby", "title")


def has_attr(tag, *names):
    return any(re.search(r"(?i)\b" + re.escape(n) + r"\b", tag) for n in names)


def line_of(text, pos):
    return text.count("\n", 0, pos) + 1


def audit_text(text):
    """Return a sorted list of (lineno, message) issues for one file's text."""
    issues = []

    def add(pos, msg):
        issues.append((line_of(text, pos), msg))

    # <html> without lang
    for m in HTML_TAG.finditer(text):
        if not has_attr(m.group(0), "lang"):
            add(m.start(), "<html> is missing a lang attribute")

    # <img> without alt
    for m in IMG.finditer(text):
        if not has_attr(m.group(0), "alt"):
            add(m.start(), '<img> has no alt attribute (use alt="" if decorative)')

    # Icon-only <button>/<a> with no accessible name
    for tag in ("button", "a"):
        pat = re.compile(r"(?is)<" + tag + r"\b([^>]*)>(.*?)</" + tag + r">")
        for m in pat.finditer(text):
            attrs, inner = m.group(1), m.group(2)
            if has_attr(attrs, *NAMED):
                continue
            visible = re.sub(r"(?s)<[^>]+>", "", inner).strip()
            if visible:
                continue
            if re.search(r"(?is)<(svg|i|img|use|span)\b", inner):
                add(
                    m.start(),
                    f"icon-only <{tag}> has no accessible name (add aria-label)",
                )

    # Click/key handler on a non-interactive element
    for m in CLICK_ON_DIV.finditer(text):
        if not has_attr(m.group(0), "role"):
            add(
                m.start(),
                "click handler on a non-interactive <div>/<span> "
                "(use <button>, or add role + tabindex + key handler)",
            )

    # Unlabeled form input
    for m in INPUT.finditer(text):
        tag = m.group(0)
        tm = re.search(r"(?i)\btype\s*=\s*[\"']?([a-z]+)", tag)
        if tm and tm.group(1).lower() in (
            "hidden",
            "submit",
            "button",
            "reset",
            "image",
        ):
            continue
        if not has_attr(tag, *NAMED, "id"):
            add(
                m.start(),
                "<input> has no label association (add <label for>, aria-label, or id)",
            )

    # Positive tabindex
    for m in TABINDEX.finditer(text):
        add(m.start(), f"positive tabindex ({m.group(1)}) — use only 0 or -1")

    # <button> without explicit type — only checked when the file has a <form>, since a
    # type-less button defaults to submit. File-level (not form-scoped), so it may flag a
    # button outside the form too; the message stays honest about that.
    if re.search(r"(?is)<form\b", text):
        for m in re.finditer(r"(?is)<button\b([^>]*)>", text):
            if not has_attr(m.group(1), "type"):
                add(
                    m.start(),
                    "<button> has no explicit type — defaults to submit inside a <form>",
                )

    issues.sort()
    return issues


def main(argv):
    paths = [Path(a) for a in argv]
    scanned = 0
    total = 0
    for path in paths:
        if path.suffix.lower() not in MARKUP_EXT:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError as e:
            print(f"{path}: cannot read ({e})", file=sys.stderr)
            continue
        scanned += 1
        for lineno, msg in audit_text(text):
            print(f"{path}:{lineno}: {msg}")
            total += 1

    if scanned == 0:
        print("a11y_audit: no readable markup files given", file=sys.stderr)
        return 2
    if total:
        print(
            f"\n{total} accessibility issue(s) in {scanned} file(s).", file=sys.stderr
        )
        return 1
    print(f"No accessibility issues found in {scanned} file(s).", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

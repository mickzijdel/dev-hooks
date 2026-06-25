#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Scan prose for the banned words listed in a voice profile.

Reads the profile's "Banned words" section, collects every `backtick-quoted` term in it,
and prints `file:line: avoid "term"` for each occurrence in the content files. Terms match
case-insensitively on word boundaries; whitespace inside a term matches any whitespace, and
`...` inside a term matches any text on the same line (so `converts ... into` flags
"converts the score into a number"). Fenced code blocks and inline `code` spans are skipped.

This is a backstop, not a judge: some banned words have legitimate technical uses, so read
each hit rather than mass-replacing. Rewrites and nuance live in the profile and the
voice-profile skill.

Usage: voice_audit.py --profile PROFILE FILE [FILE ...]
Exit code: 0 = clean, 1 = banned words found, 2 = no profile terms or no readable files.
"""

import argparse
import re
import sys
from pathlib import Path

ARROW = re.compile(r"\s*(?:->|→|—>|=>)\s*")
BACKTICK = re.compile(r"`([^`]+)`")
HEADING = re.compile(r"^\s{0,3}#{1,6}\s+(.*)$")
FENCE = re.compile(r"^\s*(```|~~~)")


def parse_banned(profile_text):
    """Return {term: rewrite_or_None} from the profile's "Banned words" section."""
    terms = {}
    in_section = False
    for line in profile_text.splitlines():
        heading = HEADING.match(line)
        if heading:
            in_section = "banned" in heading.group(1).lower()
            continue
        if not in_section:
            continue
        spans = BACKTICK.findall(line)
        if not spans:
            continue
        # A single term on a list line may carry a "-> rewrite" hint after it.
        rewrite = None
        if len(spans) == 1:
            tail = line.split("`" + spans[0] + "`", 1)[-1]
            parts = ARROW.split(tail, 1)
            if len(parts) == 2 and parts[1].strip():
                rewrite = parts[1].strip()
        for term in spans:
            terms.setdefault(term.strip(), rewrite)
    return terms


def compile_term(term):
    """Build a case-insensitive line-scoped regex for one banned term.

    Whitespace -> \\s+; literal `...` -> `.*?`; word-char edges get \\b boundaries.
    """
    chunks = re.split(r"\.{3,}", term)
    compiled = []
    for chunk in chunks:
        words = chunk.split()
        compiled.append(r"\s+".join(re.escape(w) for w in words))
    body = r".*?".join(c for c in compiled if c)
    if not body:
        return None
    prefix = r"\b" if term[:1].isalnum() else ""
    suffix = r"\b" if term[-1:].isalnum() else ""
    return re.compile(prefix + body + suffix, re.IGNORECASE)


def scan_text(text, patterns):
    """Yield (lineno, matched_text, term) for each banned hit, skipping code."""
    in_fence = False
    for lineno, raw in enumerate(text.splitlines(), 1):
        if FENCE.match(raw):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        line = re.sub(r"`[^`]*`", lambda m: " " * len(m.group(0)), raw)
        for term, pattern in patterns:
            for m in pattern.finditer(line):
                if m.group(0).strip():
                    yield lineno, m.group(0), term


def main(argv):
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--profile", required=True)
    parser.add_argument("files", nargs="*")
    options = parser.parse_args(argv)

    profile_path = Path(options.profile)
    if not profile_path.exists():
        print(f"voice_audit: profile not found: {options.profile}", file=sys.stderr)
        return 2

    banned = parse_banned(profile_path.read_text(encoding="utf-8", errors="replace"))
    patterns = [(t, p) for t in banned if (p := compile_term(t))]
    if not patterns:
        print(
            "voice_audit: no banned terms in profile (add `backtick` terms under a "
            '"Banned words" heading)',
            file=sys.stderr,
        )
        return 2

    scanned = 0
    total = 0
    for arg in options.files:
        path = Path(arg)
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError as e:
            print(f"{path}: cannot read ({e})", file=sys.stderr)
            continue
        scanned += 1
        for lineno, matched, term in scan_text(text, patterns):
            rewrite = banned.get(term)
            hint = f" (use: {rewrite})" if rewrite else ""
            print(f'{path}:{lineno}: avoid "{matched}"{hint}')
            total += 1

    if scanned == 0:
        print("voice_audit: no readable files given", file=sys.stderr)
        return 2
    if total:
        print(f"\n{total} voice issue(s) in {scanned} file(s).", file=sys.stderr)
        return 1
    print(f"No banned words found in {scanned} file(s).", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

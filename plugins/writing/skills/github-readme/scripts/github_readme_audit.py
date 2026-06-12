#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""GitHub README audit.

Usage: github_readme_audit.py <README.md> [--strict]
"""

import argparse
import re
import sys
from collections import namedtuple
from pathlib import Path

Result = namedtuple("Result", ["status", "label", "details"])

SECTION_PATTERNS = {
    "installation": [
        r"^#{1,6}\s+installation\b",
        r"^#{1,6}\s+install\b",
        r"^#{1,6}\s+setup\b",
    ],
    "usage": [
        r"^#{1,6}\s+usage\b",
        r"^#{1,6}\s+quick\s*start\b",
        r"^#{1,6}\s+getting\s+started\b",
    ],
    "license": [r"^#{1,6}\s+license\b"],
}

SETUP_COMMAND_HINTS = [
    r"\b(?:npm|pnpm|yarn|bundle|pip|cargo|go|uv|mise)\s+(?:install|add|get|sync)\b",
    r"\bgit\s+clone\b",
    r"\b(?:make|rake|just)\s+\w+",
    r"\b(?:docker|docker-compose|compose)\b",
    r"/plugin\s+(?:marketplace\s+add|install)\b",
    r"\./bin/[\w-]+\b",
]

USAGE_COMMAND_HINTS = [
    r"\b(?:npm|pnpm|yarn|bundle|pip|cargo|go|ruby|python|uv|mise)\s+(?:run|exec|test|start|serve)\b",
    r"\b(?:make|rake|just)\s+\w+",
    r"\./bin/[\w-]+\b",
    r"^\$\s+.+",
]


def usage_error(message):
    print(message, file=sys.stderr)
    print("Usage: github_readme_audit.py <README.md> [--strict]", file=sys.stderr)
    sys.exit(1)


def heading_lines(text):
    return [
        line for line in text.splitlines(keepends=True) if re.match(r"#{1,6}\s+", line)
    ]


def heading_match(headings, patterns):
    return any(
        any(re.search(pattern, heading, re.IGNORECASE) for heading in headings)
        for pattern in patterns
    )


def first_non_heading_paragraph(text):
    body = "".join(
        line
        for line in text.splitlines(keepends=True)
        if not re.match(r"#{1,6}\s+", line)
    )
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n+", body)]
    paragraphs = [p for p in paragraphs if p]
    return paragraphs[0] if paragraphs else ""


def words(text):
    return re.findall(r"[A-Za-z0-9']+", text)


def fenced_code_blocks(text):
    return re.findall(r"```(?:[^\n]*)\n(.*?)```", text, flags=re.DOTALL)


def has_command_block(code_blocks, hints):
    return any(
        any(re.search(pattern, block, re.IGNORECASE) for pattern in hints)
        for block in code_blocks
    )


def check(status, label, details):
    return Result(status, label, details)


def main(argv):
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("file", nargs="?")
    parser.add_argument("--strict", action="store_true")
    options = parser.parse_args(argv)

    file = options.file
    if file is None:
        usage_error("Missing README path")
    if not Path(file).exists():
        usage_error(f"File not found: {file}")

    text = Path(file).read_text()
    if not text.strip():
        usage_error(f"File is empty: {file}")

    headings = heading_lines(text)
    code_blocks = fenced_code_blocks(text)
    first_paragraph = first_non_heading_paragraph(text)
    word_count = len(words(text))

    results = []

    h1_count = sum(1 for line in text.splitlines() if re.match(r"#\s+\S+", line))
    if h1_count == 1:
        results.append(check("pass", "Exactly one H1", "1 found"))
    elif h1_count == 0:
        results.append(check("fail", "Exactly one H1", "0 found"))
    else:
        results.append(check("fail", "Exactly one H1", f"{h1_count} found"))

    for name, patterns in SECTION_PATTERNS.items():
        if heading_match(headings, patterns):
            results.append(check("pass", f"{name.capitalize()} section", "Found"))
        else:
            results.append(check("fail", f"{name.capitalize()} section", "Missing"))

    lead_words = len(words(first_paragraph))
    if lead_words <= 80:
        results.append(check("pass", "Lead paragraph length", f"{lead_words} words"))
    elif lead_words <= 120:
        results.append(
            check(
                "warn",
                "Lead paragraph length",
                f"{lead_words} words (consider tightening)",
            )
        )
    else:
        results.append(
            check("fail", "Lead paragraph length", f"{lead_words} words (too long)")
        )

    if has_command_block(code_blocks, SETUP_COMMAND_HINTS):
        results.append(
            check("pass", "Setup command example", "Found in fenced code block")
        )
    else:
        results.append(
            check("fail", "Setup command example", "Missing in fenced code block")
        )

    if has_command_block(code_blocks, USAGE_COMMAND_HINTS):
        results.append(
            check("pass", "Usage command example", "Found in fenced code block")
        )
    else:
        results.append(
            check("fail", "Usage command example", "Missing in fenced code block")
        )

    if word_count > 1200:
        has_toc = any(
            re.search(
                r"^#{2,6}\s+(?:table\s+of\s+contents|contents)\b",
                heading,
                re.IGNORECASE,
            )
            for heading in headings
        )
        if has_toc:
            results.append(
                check("pass", "Table of contents for long README", "Present")
            )
        else:
            severity = "fail" if options.strict else "warn"
            results.append(
                check(
                    severity,
                    "Table of contents for long README",
                    f"Missing ({word_count} words)",
                )
            )

    if options.strict:
        has_contributing = any(
            re.search(r"^#{1,6}\s+contribut(?:e|ing)\b", heading, re.IGNORECASE)
            for heading in headings
        )
        has_features = any(
            re.search(r"^#{1,6}\s+(?:features?|capabilities)\b", heading, re.IGNORECASE)
            for heading in headings
        )

        results.append(
            check("pass", "Contributing section", "Found")
            if has_contributing
            else check("warn", "Contributing section", "Missing")
        )
        results.append(
            check("pass", "Features/capabilities section", "Found")
            if has_features
            else check("warn", "Features/capabilities section", "Missing")
        )

    print(f"GitHub README audit: {file}")
    print(f"Word count: {word_count}")
    print()

    labels = {"pass": "PASS", "warn": "WARN", "fail": "FAIL"}
    for result in results:
        print(f"[{labels[result.status]}] {result.label} — {result.details}")

    sys.exit(2 if any(result.status == "fail" for result in results) else 0)


if __name__ == "__main__":
    main(sys.argv[1:])

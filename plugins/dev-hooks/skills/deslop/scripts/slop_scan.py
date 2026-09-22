#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Flag mechanically-detectable AI-authored code slop.

Two passes over each file:

  line rules    high-precision patterns printed as `file:line: [rule] message` —
                narration and apology comments, chat artifacts, swallowed errors,
                type escapes, dead branches, debug residue.
  file metrics  the measurements that no single line is guilty of: comment density,
                comment register (em dashes, parentheticals, words per comment), and
                file size. A file can pass every line rule and still read as machine
                output because it carries five times the comments a human would write.

The metric budgets come from measuring four pre-2023 codebases (Django 4.0, Flask 2.0,
requests 2.27, git 2.34) — see ../references/measurements.md. They are defaults, not
laws: `--max-density` and friends move them, and a file with a real reason to be
comment-heavy (a reference table, a vendored algorithm) should be argued for, not
silently rewritten.

This is a regex scanner, not a parser. It sees comments by line shape and gives up on
anything exotic; it cannot judge whether a comment is *true*, only whether it is
plausible for a human to have bothered writing it. Everything it prints is a prompt to
look, not a verdict.

Usage: slop_scan.py [options] <file> [<file> ...]
Exit code: 0 = clean, 1 = findings, 2 = no readable files given.
"""

import argparse
import re
import statistics
import sys
from pathlib import Path

# --- comment syntax by extension -------------------------------------------------

HASH = ("#", None)
SLASH = ("//", ("/*", "*/"))
DASH = ("--", None)

COMMENT_SYNTAX = {
    ".py": HASH,
    ".sh": HASH,
    ".bash": HASH,
    ".zsh": HASH,
    ".rb": HASH,
    ".pl": HASH,
    ".r": HASH,
    ".tf": HASH,
    ".yml": HASH,
    ".yaml": HASH,
    ".toml": HASH,
    ".js": SLASH,
    ".mjs": SLASH,
    ".cjs": SLASH,
    ".jsx": SLASH,
    ".ts": SLASH,
    ".tsx": SLASH,
    ".go": SLASH,
    ".rs": SLASH,
    ".java": SLASH,
    ".kt": SLASH,
    ".cs": SLASH,
    ".c": SLASH,
    ".h": SLASH,
    ".cc": SLASH,
    ".cpp": SLASH,
    ".hpp": SLASH,
    ".swift": SLASH,
    ".php": SLASH,
    ".scala": SLASH,
    ".dart": SLASH,
    ".sql": DASH,
    ".lua": DASH,
    ".hs": DASH,
}

# Comments that exist to serve a tool, not a reader. Never counted, never flagged.
DIRECTIVE = re.compile(
    r"""(?ix)
    \b(?: noqa | type:\s*ignore | pragma | shellcheck | pylint | ruff | fmt:\s*(?:on|off)
        | isort | jscpd | eslint- | prettier- | mypy | nosec | depends-on | codespell
        | frozen_string_literal | coding[:=] | rubocop: | golangci | \$?Id\$ | SPDX-
    )\b
    """
)

# --- line rules ------------------------------------------------------------------
#
# Each entry is (rule name, compiled pattern, message). Patterns marked COMMENT_ONLY are
# applied to comment bodies; the rest are applied to the whole line. Precision beats
# recall everywhere: a rule that cries wolf gets ignored, which is worse than silence.

COMMENT_RULES = [
    # Deliberately narrow. The tempting rule — "comment opens with a verb naming what the
    # next line does" — fires on 222 Django comments, nearly all of them real why-comments
    # that happen to start "Set the ...". Narration is judged by whether the comment adds
    # anything the line does not, which a regex cannot see. That judgement belongs to the
    # reader; the scanner contributes density instead. Only the forms that are near-absent
    # from human code survive here.
    (
        "narration",
        re.compile(
            r"""(?ix)
            ^(?:
                this\s+(?:function|method|line|loop|variable|class|block|file|module)\s+
                   (?:does|handles|returns|creates|will|manages|performs)\b
              | (?:helper\s+)?function\s+(?:to|that)\b
              | (?:import|importing)\s+(?:the\s+|required\s+|necessary\s+)?
                   (?:libraries|modules|dependencies|packages)\b
            )
            """
        ),
        "narrating comment (restates the code it sits on)",
    ),
    (
        "apology",
        re.compile(
            r"""(?ix)
            \b(?:
                (?:this\s+is\s+a\s+)?(?:simplified|basic|naive|minimal|rudimentary)\s+
                   (?:implementation|version|example|approach)
              | for\s+(?:demonstration|illustration|simplicity)\s+purposes
              | in\s+(?:a\s+)?(?:real|production|actual)\s+
                   (?:implementation|app|system|scenario|environment|setting)
              | not\s+production[-\s]ready
              | (?:may|might|would|will)\s+need\s+(?:to\s+be\s+)?
                   (?:enhanced|improved|expanded|hardened|adjusted)
            )\b
            """
        ),
        "apologetic comment (the code apologizes for itself)",
    ),
    # Bare "for now" is ordinary human shorthand — 8 hits in Django, all legitimate. Only
    # the phrasings that sign off unfinished work stay.
    (
        "deferral",
        re.compile(
            r"""(?ix)
            \b(?:
                temporar(?:y|ily)\s+(?:fix|workaround|solution|hack|measure)
              | good\s+enough\s+for\s+now
              | this\s+should\s+(?:work|be\s+fine|be\s+enough)
              | leaving\s+this\s+as[-\s]is
              | proper\s+(?:fix|solution|implementation)\s+(?:would|will|is)\b
            )\b
            """
        ),
        "deferral comment (unfinished work signed off in prose)",
    ),
    (
        "placeholder",
        re.compile(
            r"""(?ix)
            (?: \.{2,}\s*(?:rest|the\s+rest|your|remaining|existing|previous|other)\b
              | (?:rest|remainder)\s+of\s+(?:your|the|my)?\s*
                    (?:code|implementation|logic|function|file|method)\b
              | (?:your|the)\s+(?:code|logic|implementation)\s+(?:goes\s+)?here\b
              | (?:add|insert|implement|put)\s+(?:your\s+)?
                    (?:code|logic|implementation)\s+here\b
              | (?:implementation|code|logic)\s+goes?\s+here\b
              | existing\s+code\s+(?:here|unchanged|stays|remains)\b
              | ^TODO:?\s*(?:implement|add|fill\s+in|finish)\s*$
            )
            """
        ),
        "placeholder stub (the file is unfinished — this is a bug, not a style nit)",
    ),
    (
        "chat-artifact",
        re.compile(
            r"""(?ix)
            \b(?:
                here'?s\s+the\s+(?:updated|complete|full|fixed|revised|new)\s+
                   (?:code|version|implementation|file)
              | as\s+an?\s+(?:ai|a\.i\.)\s+(?:language\s+)?model
              | you'?re\s+absolutely\s+right
              | (?:good|great)\s+catch!
              | i\s+hope\s+this\s+helps
              | let\s+me\s+know\s+if\s+you
            )\b
            """
        ),
        "leftover chat artifact (assistant voice in the source)",
    ),
    (
        "change-narration",
        re.compile(
            r"""(?ix)
            ^(?:
                (?:added|updated|changed|modified|refactored|fixed|removed|renamed)\s+
                   (?:this|for|to|the|in|so|because|after|when)\b
              | (?:new|changed)\s+in\s+this\s+(?:version|change|commit|pr)\b
              | previously[,\s]
              | (?:was|used\s+to\s+be)\s+\w+\s+before\b
            )
            """
        ),
        "change narration (git already records what changed)",
    ),
]

# Extension sets for rules that only make sense in one language family.
TS_JS = {".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs"}

# (rule, pattern, message, extensions the rule applies to — None means every language)
LINE_RULES = [
    (
        "swallowed-error",
        re.compile(
            r"""(?x)
            ^\s*except\s*:\s*$
          | ^\s*except\s+(?:Exception|BaseException)\s*(?:\s+as\s+\w+)?\s*:\s*
                (?:pass|\.\.\.)\s*$
          | \bcatch\s*\([^)]*\)\s*\{\s*\}
          | \bcatch\s*\{\s*\}
          | \bif\s+err\s*!=\s*nil\s*\{\s*\}
          | \brescue\s+(?:StandardError\s*)?(?:=>\s*\w+\s*)?$\s*\n\s*(?:nil|end)
            """
        ),
        "swallowed error (the failure is discarded, not handled) — a bug",
        None,
    ),
    # Scoped to TS/JS: an unscoped `:\s*any\b` matches `any(` calls and ordinary prose in
    # every other language (3 hits in Django, all spurious).
    (
        "type-escape",
        re.compile(
            r"""(?x)
            @ts-ignore\b | @ts-nocheck\b | \bas\s+any\b | :\s*any\b
          | \bas\s+unknown\s+as\b | \bcatch\s*\(\s*\w+\s*:\s*any\s*\)
            """
        ),
        "type escape (the checker is silenced where it was most needed)",
        TS_JS,
    ),
    (
        "type-suppression",
        re.compile(
            r"(?x) \#\s*type:\s*ignore\b | \binterface\{\} | @SuppressWarnings\b"
        ),
        "type suppression instead of a fix",
        None,
    ),
    (
        "dead-branch",
        re.compile(
            r"""(?x)
            \bif\s*\(\s*(?:true|false)\s*\)
          | \bwhile\s*\(\s*false\s*\)
          | ^\s*(?:if|elif)\s+(?:True|False)\s*:
          | ^\s*while\s+False\s*:
            """
        ),
        "dead branch scaffolding",
        None,
    ),
    (
        "debug-residue",
        re.compile(
            r"""(?ix)
            \bconsole\.(?:log|debug)\s*\(\s*['"`](?:\s*(?:DEBUG|HERE|TEST|XXX|\d+)\b|={3,})
          | ^\s*print\s*\(\s*f?['"](?:\s*(?:DEBUG|HERE|TEST|XXX)\b|={3,})
          | \bbinding\.pry\b | \bdebugger\s*;?\s*$ | \bbreakpoint\s*\(\s*\)
            """
        ),
        "debug residue left from the session",
        None,
    ),
    (
        "generic-name",
        re.compile(
            r"""(?x)
            \b(?:def|function|func|fn|fun|sub)\s+
            (?:process_?[Dd]ata|do_?[Ss]tuff|do_?[Ss]omething|my_?[Ff]unction
              |process_?[Ii]tem|helper_?[Ff]unction|main_?[Ff]unction)\b
            """
        ),
        "placeholder function name (says nothing about the domain)",
        None,
    ),
]

# --- metric budgets --------------------------------------------------------------
#
# See ../references/measurements.md. Pre-2023 reference codebases land at 9.9-12.1%
# comment density with a 7-8 word median; the budgets sit a little above the top of
# that range so that ordinary human-written code does not trip them.

DEFAULTS = {
    "max_density": 15.0,  # comment lines per 100 code lines
    "max_em_dash": 5.0,  # % of comments containing an em dash / " -- "
    "max_paren": 25.0,  # % of comments containing a parenthetical
    "max_words": 14.0,  # mean words per comment
    "max_lines": 600,  # file length before it counts as a god file
    "min_comments": 12,  # below this, register percentages are too noisy to judge
}


def syntax_for(path):
    return COMMENT_SYNTAX.get(path.suffix.lower())


def strip_quoted(line):
    """Blank out string literals so a `#` or `//` inside one is not read as a comment.

    Crude on purpose: it walks the line tracking quote state and ignores escapes, which
    is right often enough for comment detection and wrong only on lines that would
    confuse a human reader too.
    """
    out = []
    quote = None
    for ch in line:
        if quote:
            out.append(" ")
            if ch == quote:
                quote = None
            continue
        if ch in "\"'`":
            quote = ch
            out.append(" ")
            continue
        out.append(ch)
    return "".join(out)


def extract_comments(lines, syntax):
    """Yield (index, body, kind) for each comment, kind being "own" or "trailing"."""
    marker, block = syntax
    in_block = False
    for i, raw in enumerate(lines):
        stripped = raw.strip()
        if in_block:
            body = stripped.lstrip("*").strip()
            if block and block[1] in stripped:
                in_block = False
                body = stripped.split(block[1])[0].lstrip("*").strip()
            if body:
                yield i, body, "own"
            continue
        if block and stripped.startswith(block[0]):
            body = stripped[len(block[0]) :]
            if block[1] in body:
                body = body.split(block[1])[0]
            else:
                in_block = True
            body = body.strip()
            if body:
                yield i, body, "own"
            continue
        if stripped.startswith(marker):
            if i == 0 and stripped.startswith("#!"):
                continue
            body = stripped[len(marker) :].strip()
            if body:
                yield i, body, "own"
            continue
        masked = strip_quoted(raw)
        pos = masked.find(marker)
        if pos > 0:
            body = raw[pos + len(marker) :].strip()
            if body:
                yield i, body, "trailing"


def is_code(line, syntax):
    stripped = line.strip()
    if not stripped:
        return False
    marker, block = syntax
    if stripped.startswith(marker) or (block and stripped.startswith(block[0])):
        return False
    return not stripped.startswith("*")


def scan_file(path, budgets):
    """Return (findings, metrics) for one file. findings is a list of (line, rule, msg)."""
    syntax = syntax_for(path)
    if syntax is None:
        return None, None
    text = path.read_text(errors="ignore")
    lines = text.split("\n")

    findings = []
    comments = []
    for i, body, kind in extract_comments(lines, syntax):
        if DIRECTIVE.search(body):
            continue
        comments.append((i, body, kind))
        for rule, pattern, msg in COMMENT_RULES:
            if pattern.search(body):
                findings.append((i + 1, rule, msg))
                break

    ext = path.suffix.lower()
    for i, raw in enumerate(lines):
        if not is_code(raw, syntax):
            continue
        for rule, pattern, msg, langs in LINE_RULES:
            if langs is not None and ext not in langs:
                continue
            if pattern.search(raw):
                findings.append((i + 1, rule, msg))
                break

    code_lines = sum(1 for line in lines if is_code(line, syntax))
    bodies = [b for _, b, _ in comments]
    metrics = {
        "code": code_lines,
        "comments": len(comments),
        "lines": len(lines),
        "density": 100 * len(comments) / code_lines if code_lines else 0.0,
        "em_dash": pct(bodies, lambda b: "—" in b or " -- " in b),
        "paren": pct(bodies, lambda b: "(" in b),
        "words": statistics.mean([len(b.split()) for b in bodies]) if bodies else 0.0,
    }
    findings.extend(metric_findings(metrics, budgets))
    return sorted(findings), metrics


def pct(items, predicate):
    return 100 * sum(1 for i in items if predicate(i)) / len(items) if items else 0.0


def metric_findings(m, budgets):
    """File-level findings. Reported at line 0 — they belong to the file, not a line."""
    out = []

    def add(rule, msg):
        out.append((0, rule, msg))

    if m["code"] >= 40 and m["density"] > budgets["max_density"]:
        add(
            "comment-density",
            (
                f"{m['density']:.0f}% comment density against a "
                f"{budgets['max_density']:.0f}% budget ({m['comments']} comments / "
                f"{m['code']} code lines) — rank them and keep the few that carry a "
                "constraint"
            ),
        )
    if m["comments"] >= budgets["min_comments"]:
        if m["em_dash"] > budgets["max_em_dash"]:
            add(
                "comment-register",
                (
                    f"{m['em_dash']:.0f}% of comments use an em dash (human codebases: "
                    "under 1%) — write fragments that name identifiers, not sentences"
                ),
            )
        if m["paren"] > budgets["max_paren"]:
            add(
                "comment-register",
                (
                    f"{m['paren']:.0f}% of comments carry a parenthetical aside (budget "
                    f"{budgets['max_paren']:.0f}%) — say one thing per comment"
                ),
            )
        if m["words"] > budgets["max_words"]:
            add(
                "comment-register",
                (
                    f"{m['words']:.0f} words per comment on average (human codebases: "
                    "7-8) — the comment is explaining, not annotating"
                ),
            )
    if m["lines"] > budgets["max_lines"]:
        add(
            "god-file",
            (
                f"{m['lines']} lines — name the responsibilities and propose a split "
                "(Tier C: propose, do not restructure during cleanup)"
            ),
        )
    return out


def build_parser():
    p = argparse.ArgumentParser(
        description="Flag mechanically-detectable AI-authored code slop.",
        epilog="Exit code: 0 = clean, 1 = findings, 2 = no readable files given.",
    )
    p.add_argument("files", nargs="*", metavar="FILE")
    p.add_argument("--max-density", type=float, default=DEFAULTS["max_density"])
    p.add_argument("--max-em-dash", type=float, default=DEFAULTS["max_em_dash"])
    p.add_argument("--max-paren", type=float, default=DEFAULTS["max_paren"])
    p.add_argument("--max-words", type=float, default=DEFAULTS["max_words"])
    p.add_argument("--max-lines", type=int, default=DEFAULTS["max_lines"])
    p.add_argument(
        "--metrics-only",
        action="store_true",
        help="print the per-file measurement table and skip the line rules",
    )
    return p


def main(argv):
    args = build_parser().parse_args(argv)
    budgets = {
        "max_density": args.max_density,
        "max_em_dash": args.max_em_dash,
        "max_paren": args.max_paren,
        "max_words": args.max_words,
        "max_lines": args.max_lines,
        "min_comments": DEFAULTS["min_comments"],
    }

    scanned = 0
    total = 0
    table = []
    for name in args.files:
        path = Path(name)
        try:
            findings, metrics = scan_file(path, budgets)
        except OSError as e:
            print(f"{path}: cannot read ({e})", file=sys.stderr)
            continue
        if findings is None:
            print(f"{path}: unsupported file type, skipped", file=sys.stderr)
            continue
        scanned += 1
        table.append((name, metrics))
        if args.metrics_only:
            continue
        for line, rule, msg in findings:
            where = f"{path}:{line}" if line else f"{path}"
            print(f"{where}: [{rule}] {msg}")
            total += 1

    if not scanned:
        print("slop_scan: no readable supported files given", file=sys.stderr)
        return 2

    if args.metrics_only:
        print(
            f"{'file':<48} {'code':>6} {'cmts':>5} {'dens':>6} {'em—':>5} {'()':>5} {'w/c':>5}"
        )
        for name, m in table:
            print(
                f"{name[-48:]:<48} {m['code']:>6} {m['comments']:>5} "
                f"{m['density']:>5.1f}% {m['em_dash']:>4.0f}% {m['paren']:>4.0f}% "
                f"{m['words']:>5.1f}"
            )
        return 0

    if not total:
        print(f"No slop found in {scanned} file(s).", file=sys.stderr)
        return 0
    print(f"\n{total} finding(s) across {scanned} file(s).", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

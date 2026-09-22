"""Tests for the deslop skill's slop_scan.py.

Two halves. The positive tests assert each rule fires on the shape it names. The
regression tests pin the false positives that tuning removed — every one of them was a
real hit on Django 4.0 or git 2.34, and each would silently return if someone widened a
pattern. A scanner that cries wolf on human code is worse than no scanner, so those
tests are the load-bearing ones.
"""

import subprocess
import sys

import pytest
from conftest import DEV_HOOKS

SCAN = DEV_HOOKS / "skills" / "deslop" / "scripts" / "slop_scan.py"


def run(tmp_path, name, body, *args):
    """Write body to a file and scan it. Returns (exit code, stdout, stderr)."""
    path = tmp_path / name
    path.write_text(body)
    result = subprocess.run(
        [sys.executable, str(SCAN), *args, str(path)],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode, result.stdout, result.stderr


def rules(stdout):
    """The rule names in a scan's output, in order."""
    return [
        line.split("[", 1)[1].split("]", 1)[0]
        for line in stdout.splitlines()
        if "[" in line
    ]


# --- line rules ------------------------------------------------------------------


@pytest.mark.parametrize(
    "rule,body",
    [
        ("narration", "# This function handles the request\nx = 1\n"),
        ("narration", "# Helper function to build the URL\nx = 1\n"),
        ("apology", "# This is a simplified implementation\nx = 1\n"),
        ("apology", "# In a real implementation you would cache this\nx = 1\n"),
        ("deferral", "# Temporary workaround until the API lands\nx = 1\n"),
        ("deferral", "# Good enough for now\nx = 1\n"),
        ("placeholder", "# ... rest of the code\nx = 1\n"),
        ("placeholder", "# Your implementation goes here\nx = 1\n"),
        ("chat-artifact", "# Here's the updated implementation\nx = 1\n"),
        ("chat-artifact", "# You're absolutely right\nx = 1\n"),
        ("change-narration", "# Added this to handle the unicode case\nx = 1\n"),
        ("swallowed-error", "try:\n    f()\nexcept:\n"),
        ("swallowed-error", "try:\n    f()\nexcept Exception:\n    pass\n"),
        ("dead-branch", "if False:\n    f()\n"),
        ("debug-residue", 'print("DEBUG here")\n'),
        ("debug-residue", "breakpoint()\n"),
        ("generic-name", "def process_data(x):\n    return x\n"),
        ("type-suppression", "x = f()  # type: ignore\n"),
    ],
)
def test_line_rule_fires(tmp_path, rule, body):
    code, out, _ = run(tmp_path, "sample.py", body)
    assert code == 1, f"expected a finding for {rule}, got none:\n{out}"
    assert rule in rules(out), f"expected [{rule}] in:\n{out}"


def test_type_escape_is_scoped_to_ts(tmp_path):
    """`: any` is a TS escape but ordinary syntax elsewhere — 3 spurious Django hits."""
    ts = "const x = y as any;\n"
    assert "type-escape" in rules(run(tmp_path, "a.ts", ts)[1])

    py = "result = any(check(i) for i in items)\n"
    assert "type-escape" not in rules(run(tmp_path, "a.py", py)[1])


# --- regressions: each of these was a real false positive on human code ----------


@pytest.mark.parametrize(
    "comment",
    [
        # All 8 "for now" hits in Django 4.0 were ordinary human shorthand.
        "# String refs are also allowed for now.",
        "# For now, it's here so that every use of threading is consistent",
        # The verb-prefix narration rule fired on 222 Django comments like these.
        "# Set the precision high enough to avoid an exception (#15789).",
        "# Add the token to the command stack. This is used for error",
        "# Store the actual node that caused the exception.",
        "# Get the tag callback function from the ones registered with",
        "# Import the .autoreload module to trigger the registrations of signals.",
        # Multi-line comment continuations read as narration to a naive rule.
        "# then we need to push the whole branch to HAVING clause.",
        "# First we try to extract a potential kwarg from the bit",
    ],
)
def test_human_comment_not_flagged(tmp_path, comment):
    code, out, _ = run(tmp_path, "sample.py", f"{comment}\nx = 1\n")
    assert code == 0, f"false positive on a real human comment:\n{out}"


def test_stdlib_callback_name_not_flagged(tmp_path):
    """handle_data is html.parser's own callback — Django overrides it correctly."""
    code, out, _ = run(
        tmp_path, "sample.py", "def handle_data(self, data):\n    pass\n"
    )
    assert code == 0, out


def test_directives_are_never_flagged(tmp_path):
    body = (
        "# shellcheck disable=SC2086\n"
        "# jscpd:ignore-start\n"
        "# frozen_string_literal: true\n"
        "x = 1\n"
    )
    code, out, _ = run(tmp_path, "sample.py", body)
    assert code == 0, out


def test_shebang_is_not_a_comment(tmp_path):
    code, out, _ = run(tmp_path, "sample.sh", "#!/usr/bin/env bash\nx=1\n")
    assert code == 0, out


# --- file metrics ----------------------------------------------------------------


def test_comment_density_over_budget(tmp_path):
    body = "".join(f"# a note about step {i}\nx{i} = {i}\n" for i in range(40))
    code, out, _ = run(tmp_path, "dense.py", body)
    assert code == 1
    assert "comment-density" in rules(out)


def test_comment_density_under_budget_is_silent(tmp_path):
    body = "# the one note this file needs\n" + "".join(
        f"x{i} = {i}\n" for i in range(60)
    )
    code, out, _ = run(tmp_path, "sparse.py", body)
    assert code == 0, out


def test_density_ignores_tiny_files(tmp_path):
    """Below 40 code lines the ratio is noise — a 3-line file with 1 comment is 33%."""
    code, out, _ = run(tmp_path, "tiny.py", "# why this constant\nX = 1\n")
    assert code == 0, out


def test_em_dash_register(tmp_path):
    body = "".join(f"# note {i} — with an aside\nx{i} = {i}\n" for i in range(20))
    _, out, _ = run(tmp_path, "dashes.py", body)
    assert "comment-register" in rules(out)
    assert "em dash" in out


def test_register_needs_enough_comments(tmp_path):
    """Two comments, both with em dashes, is 100% — and tells you nothing."""
    body = "# one — aside\n# two — aside\n" + "".join(
        f"x{i} = {i}\n" for i in range(60)
    )
    _, out, _ = run(tmp_path, "few.py", body)
    assert "comment-register" not in rules(out), out


def test_god_file(tmp_path):
    body = "".join(f"x{i} = {i}\n" for i in range(700))
    _, out, _ = run(tmp_path, "big.py", body)
    assert "god-file" in rules(out)


def test_budgets_are_configurable(tmp_path):
    body = "".join(f"# a note about step {i}\nx{i} = {i}\n" for i in range(40))
    _, out, _ = run(tmp_path, "dense.py", body, "--max-density", "200")
    assert "comment-density" not in rules(out), out


# --- block comments and CLI ------------------------------------------------------


def test_block_comments_are_read(tmp_path):
    body = "/*\n * This function handles the request\n */\nconst x = 1;\n"
    _, out, _ = run(tmp_path, "a.js", body)
    assert "narration" in rules(out), out


def test_hash_inside_a_string_is_not_a_comment(tmp_path):
    code, out, _ = run(
        tmp_path, "sample.py", 'url = "https://x/#/this function handles"\n'
    )
    assert code == 0, out


def test_metrics_only_prints_a_table_and_no_findings(tmp_path):
    body = "".join(f"# a note about step {i}\nx{i} = {i}\n" for i in range(40))
    code, out, _ = run(tmp_path, "dense.py", body, "--metrics-only")
    assert code == 0
    assert "dens" in out
    assert "[comment-density]" not in out


def test_exit_code_2_when_nothing_readable(tmp_path):
    result = subprocess.run(
        [sys.executable, str(SCAN)], capture_output=True, text=True, check=False
    )
    assert result.returncode == 2


def test_unsupported_file_type_is_skipped(tmp_path):
    code, _, err = run(tmp_path, "notes.md", "# This function handles the request\n")
    assert code == 2
    assert "unsupported" in err

"""Tests for the deslop skill's slop_scan.py.

Positive tests assert each rule fires on the shape it names. The regression tests pin
false positives that tuning removed: every one was a real hit on Django 4.0 or git 2.34
and would return silently if someone widened a pattern. Those are the load-bearing ones.
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


def findings(stdout):
    """(line, rule) pairs from a scan's output."""
    out = []
    for line in stdout.splitlines():
        if ": [" not in line:
            continue
        loc, rest = line.split(": [", 1)
        out.append((int(loc.rsplit(":", 1)[1]), rest.split("]", 1)[0]))
    return out


# A bare `except:` catches everything, including KeyboardInterrupt and SystemExit, so it is
# flagged whenever the failure stops there — whatever the body does, unless it re-raises. The rule is matched against a two-line window without
# re.MULTILINE, which once made `$` reachable only at the window's end: a bare except was
# caught solely when the line after it was empty — never in real code, where a body follows.
# (The case in test_line_rule_fires passed only because its file ends in a newline.)
@pytest.mark.parametrize(
    "body",
    [
        "try:\n    f()\nexcept:\n    pass\n\nx = 1\n",
        # Logs and carries on: the error stops here, so it is swallowed — and a bare
        # except also swallows KeyboardInterrupt and SystemExit.
        "try:\n    f()\nexcept:\n    log()\nx = 1\n",
        "try:\n    f()\nexcept :\n    pass\ny = 2\n",
        "try:\n    f()\nexcept:",  # last line, no trailing newline
        # One-liners hit the same trap: `$` could only match at the window's end.
        "try:\n    f()\nexcept: pass\nx = 1\n",
        "try:\n    f()\nexcept Exception: pass\nx = 1\n",
        "try:\n    f()\nexcept Exception as e: ...\nx = 1\n",
    ],
)
def test_bare_except_fires_with_a_body_after_it(tmp_path, body):
    code, out, _ = run(tmp_path, "sample.py", body)
    assert code == 1, f"bare except not flagged:\n{out}"
    assert (3, "swallowed-error") in findings(out), out


def test_bare_except_is_reported_once_on_its_own_line(tmp_path):
    # Adding re.MULTILINE would have "fixed" the case above, but let the window's second
    # line match on its own: line 2's window ends in `except:`, so the finding would land
    # on line 2 as well as 3.
    _, out, _ = run(tmp_path, "sample.py", "try:\n    f()\nexcept:\n    pass\n")
    assert [f for f in findings(out) if f[1] == "swallowed-error"] == [
        (3, "swallowed-error")
    ]


@pytest.mark.parametrize(
    "body",
    [
        "try:\n    f()\nexcept:\n    cleanup()\n    raise\nx = 1\n",
        "try:\n    f()\nexcept:\n    # undo the partial write\n\n    rollback()\n    raise\n",
        "try:\n    f()\nexcept: raise\nx = 1\n",
        "try:\n    f()\nexcept:\n    if retry:\n        g()\n    raise\n",
    ],
)
def test_reraising_bare_except_is_not_a_swallowed_error(tmp_path, body):
    """The failure still propagates, so "discarded, not handled" would be false. 75 of the
    137 bare excepts in the CPython 3.12 stdlib are this cleanup-then-raise idiom."""
    _, out, _ = run(tmp_path, "sample.py", body)
    assert "swallowed-error" not in rules(out), out


@pytest.mark.parametrize(
    "name,body",
    [
        # Rails keyword argument continued onto its own line.
        (
            "c.rb",
            "class C < ApplicationController\n  before_action :auth,\n    except: [:index, :show]\nend\n",
        ),
        # GitLab CI
        ("ci.yml", "build:\n  script: make\n  except:\n    - main\n"),
        # A JS object key
        ("o.js", "const opts = {\n  except: true,\n  only: false,\n};\n"),
    ],
)
def test_except_key_outside_python_is_not_a_swallowed_error(tmp_path, name, body):
    """The swallowed-error rule once ran on every language; with the bare-except form no
    longer anchored at end of line, `except:` as a key or keyword argument became "a bug"."""
    code, out, _ = run(tmp_path, name, body)
    assert "swallowed-error" not in rules(out), out


@pytest.mark.parametrize(
    "name,body",
    [
        ("a.js", "try { f() } catch (e) {}\nconst x = 1\n"),
        ("a.go", "if err != nil {}\nx := 1\n"),
        ("a.rb", "begin\n  f\nrescue\n  nil\nend\n"),
    ],
)
def test_non_python_swallowed_errors_still_fire(tmp_path, name, body):
    # Splitting the rule by language must not drop the forms that were never Python's.
    _, out, _ = run(tmp_path, name, body)
    assert "swallowed-error" in rules(out), out


@pytest.mark.parametrize(
    "body",
    [
        # Re-raises only sometimes: whenever `strict` is false it swallows everything.
        "try:\n    f()\nexcept:\n    if strict: raise\n    log()\n",
        "try:\n    f()\nexcept:\n    if strict:\n        raise\n    log()\n",
        "try:\n    f()\nexcept:\n    for h in hooks:\n        raise\n",
        # The raise belongs to a function the handler defines, not to the handler.
        "try:\n    f()\nexcept:\n    def later():\n        raise\n    defer(later)\n",
        # `raise` inside a string is not a statement.
        'try:\n    f()\nexcept: log("x; raise")\n',
        'try:\n    f()\nexcept:\n    log("#1"); note("; raise")\n',
    ],
)
def test_conditional_or_nested_raise_still_swallows(tmp_path, body):
    """Only a raise at the handler's own statement level guarantees propagation."""
    _, out, _ = run(tmp_path, "sample.py", body)
    assert (3, "swallowed-error") in findings(out), out


@pytest.mark.parametrize(
    "body",
    [
        'try:\n    f()\nexcept:\n    log("#1"); raise\n',
        "try:\n    f()\nexcept:\n    log()  # then propagate\n    raise  # always\n",
    ],
)
def test_body_level_raise_after_a_string_or_comment_counts(tmp_path, body):
    _, out, _ = run(tmp_path, "sample.py", body)
    assert "swallowed-error" not in rules(out), out


def _except_line(body):
    return next(n for n, line in enumerate(body.split("\n"), 1) if "except:" in line)


def _parses(body):
    import ast

    ast.parse(body)  # a SyntaxError would make the case pass for the wrong reason
    return body


# Every case sits inside a real function or loop: a module-level `return` or `break` is a
# SyntaxError, and an unparseable file is flagged regardless — the test would pass without
# exercising the early-exit check at all.
@pytest.mark.parametrize(
    "body",
    [
        # An earlier return can leave the handler, so sometimes nothing is re-raised.
        "def g():\n    try:\n        f()\n    except:\n        if fallback:\n"
        "            return default\n        raise\n",
        "for x in xs:\n    try:\n        f()\n    except:\n        if skip:\n"
        "            break\n        raise\n",
        "for x in xs:\n    try:\n        f()\n    except:\n        if skip:\n"
        "            continue\n        raise\n",
        # A loop's else runs after the loop: a break there leaves the OUTER loop.
        "for x in xs:\n    try:\n        f()\n    except:\n        for y in ys:\n"
        "            pass\n        else:\n            break\n        raise\n",
        # Looks like a raise at the handler's level, but it is text in a string.
        'def g():\n    try:\n        f()\n    except:\n        doc = """\n'
        '        raise\n        """\n',
    ],
)
def test_handler_that_can_skip_its_raise_is_flagged(tmp_path, body):
    _, out, _ = run(tmp_path, "sample.py", _parses(body))
    assert (_except_line(body), "swallowed-error") in findings(out), out


@pytest.mark.parametrize(
    "body",
    [
        # These exits stay inside the handler, so the raise still always runs.
        "try:\n    f()\nexcept:\n    for h in hooks:\n        if h.done:\n"
        "            break\n    raise\n",
        "try:\n    f()\nexcept:\n    def cb():\n        return 1\n    defer(cb)\n    raise\n",
        "try:\n    f()\nexcept:\n    fn = lambda: 1\n    raise\n",
        # Code after the raise is unreachable, so it cannot skip it.
        "def g():\n    try:\n        f()\n    except:\n        raise\n        return 1\n",
    ],
)
def test_exits_that_cannot_skip_the_raise_do_not_count(tmp_path, body):
    _, out, _ = run(tmp_path, "sample.py", _parses(body))
    assert "swallowed-error" not in rules(out), out


def test_unparseable_file_flags_its_bare_excepts(tmp_path):
    # Without an AST there is no way to know the handler re-raises, so it is flagged.
    body = 'print "py2"\ntry:\n    f()\nexcept:\n    cleanup()\n    raise\n'
    _, out, _ = run(tmp_path, "sample.py", body)
    assert (4, "swallowed-error") in findings(out), out


def test_a_raise_after_the_except_block_does_not_count(tmp_path):
    # The raise belongs to the enclosing code, not the handler: this one does swallow.
    body = "def g():\n    try:\n        f()\n    except:\n        pass\n    raise X\n"
    _, out, _ = run(tmp_path, "sample.py", body)
    assert (4, "swallowed-error") in findings(out), out


@pytest.mark.parametrize(
    "body",
    [
        "try:\n    f()\nexcept ValueError:\n    pass\nx = 1\n",
        "try:\n    f()\nexcept (KeyError, ValueError):\n    log()\nx = 1\n",
        "handled_except = 1\nx = 2\n",
        # `pass` must be the whole statement, not a prefix of a name.
        "try:\n    f()\nexcept Exception:\n    passthrough = 1\nx = 1\n",
        "try:\n    f()\nexcept Exception: pass_on()\nx = 1\n",
    ],
)
def test_narrow_except_is_not_a_bare_except(tmp_path, body):
    _, out, _ = run(tmp_path, "sample.py", body)
    assert "swallowed-error" not in rules(out), out


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

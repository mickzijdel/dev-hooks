"""Golden-parity tests for the ported Python skill CLIs.

The golden files in tests/golden/ were captured from the original Ruby scripts before
they were removed; these tests assert the Python ports reproduce that output byte for
byte (and match the recorded exit codes).
"""

import shutil
import subprocess
import sys

import pytest

from conftest import FIXTURES, GOLDEN, ROOT, init_git_repo

GR = ROOT / "skills" / "github-readme" / "scripts" / "github_readme_audit.py"
RA = ROOT / "skills" / "readability" / "scripts" / "readability_audit.py"
FK = ROOT / "skills" / "readability" / "scripts" / "flesch_kincaid.py"
VP = ROOT / "skills" / "readability" / "scripts" / "vocabulary_profiler.py"

# (golden name, script, args, stdin fixture filename or None)
CASES = [
    ("gr_sample", GR, ["tests/fixtures/sample_readme.md"], None),
    ("gr_sample_strict", GR, ["tests/fixtures/sample_readme.md", "--strict"], None),
    ("gr_bad", GR, ["tests/fixtures/bad_readme.md"], None),
    ("gr_bad_strict", GR, ["tests/fixtures/bad_readme.md", "--strict"], None),
    ("gr_missing", GR, ["tests/fixtures/does_not_exist.md"], None),
    ("ra_prose", RA, ["tests/fixtures/sample_prose.md"], None),
    (
        "ra_prose_tg9",
        RA,
        ["tests/fixtures/sample_prose.md", "--target-grade", "9"],
        None,
    ),
    ("ra_readme", RA, ["tests/fixtures/sample_readme.md"], None),
    ("ra_missing", RA, ["tests/fixtures/does_not_exist.md"], None),
    ("fk_prose", FK, ["tests/fixtures/sample_prose.md"], None),
    ("fk_stdin", FK, [], "sample_prose.md"),
    ("fk_missing", FK, ["tests/fixtures/does_not_exist.md"], None),
    ("vp_prose", VP, ["tests/fixtures/sample_prose.md"], None),
    ("vp_stdin", VP, [], "sample_prose.md"),
]


@pytest.mark.parametrize(
    "name,script,args,stdin_fixture", CASES, ids=[c[0] for c in CASES]
)
def test_golden_parity(name, script, args, stdin_fixture, golden_exit_codes):
    stdin = (FIXTURES / stdin_fixture).read_text() if stdin_fixture else None
    result = subprocess.run(
        [sys.executable, str(script), *args],
        cwd=ROOT,
        input=stdin,
        capture_output=True,
        text=True,
    )
    expected_stdout = (GOLDEN / f"{name}.out").read_text()
    assert result.stdout == expected_stdout
    assert result.returncode == golden_exit_codes[name]


# --- branch comparison (needs a git repo with the file committed on `main`) ----------

BRANCH_CASES = [
    ("ra_branch", RA, ["doc.md", "--branch", "main"]),
    ("fk_branch", FK, ["doc.md", "main"]),
    ("vp_branch", VP, ["doc.md", "main"]),
]


@pytest.mark.parametrize(
    "name,script,args", BRANCH_CASES, ids=[c[0] for c in BRANCH_CASES]
)
def test_branch_parity(name, script, args, tmp_path, golden_exit_codes):
    run = init_git_repo(tmp_path)
    (tmp_path / "doc.md").write_text((FIXTURES / "sample_prose.md").read_text())
    run("add", "doc.md")
    run("commit", "-qm", "base")
    # Working copy becomes the "current" version (v2).
    (tmp_path / "doc.md").write_text((FIXTURES / "sample_prose_v2.md").read_text())

    result = subprocess.run(
        [sys.executable, str(script), *args],
        cwd=tmp_path,
        capture_output=True,
        text=True,
    )
    assert result.stdout == (GOLDEN / f"{name}.out").read_text()
    assert result.returncode == golden_exit_codes[name]


@pytest.mark.skipif(shutil.which("uv") is None, reason="uv not installed")
def test_runs_via_uv_shebang():
    """The shipping path: a PEP 723 script self-resolves via `uv run --script`."""
    result = subprocess.run(
        [str(FK), "tests/fixtures/sample_prose.md"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert result.stdout == "Flesch-Kincaid Grade Level: 6.9\n"

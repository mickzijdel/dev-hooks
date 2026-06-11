"""Tests for the bundled skill scripts.

Golden parity for the ported Python skill CLIs: the golden files in tests/golden/ were
captured from the original Ruby scripts before they were removed; these tests assert the
Python ports reproduce that output byte for byte (and match the recorded exit codes).
Plus subprocess tests for the dev-env-setup skill's dev_env_check.sh compliance checker
(harness lives in conftest).
"""

import shutil
import subprocess
import sys

import pytest

from conftest import (
    FIXTURES,
    GOLDEN,
    ROOT,
    init_git_repo,
    make_compliant_repo,
    run_checker,
)

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


# ── dev_env_check.sh (dev-env-setup skill checker; harness lives in conftest) ───────
def test_checker_compliant_with_docs(tmp_path):
    make_compliant_repo(tmp_path)
    out = run_checker(tmp_path)
    assert out["has_readme"] == "1"
    assert out["has_claude"] == "1"
    assert out["has_cooldown"] == "1"
    assert out["has_gitleaks_config"] == "1"
    assert out["status"] == "compliant"


def test_checker_needs_upgrade_without_readme(tmp_path):
    make_compliant_repo(tmp_path, readme=False)
    out = run_checker(tmp_path)
    assert out["has_readme"] == "0"
    assert out["status"] == "needs-upgrade"


def test_checker_needs_upgrade_without_claude(tmp_path):
    make_compliant_repo(tmp_path, claude=False)
    out = run_checker(tmp_path)
    assert out["has_claude"] == "0"
    assert out["status"] == "needs-upgrade"


def test_checker_needs_upgrade_without_cooldown(tmp_path):
    # A Python repo whose pyproject.toml lacks [tool.uv] exclude-newer is flagged.
    make_compliant_repo(tmp_path, cooldown=False)
    out = run_checker(tmp_path)
    assert out["has_cooldown"] == "0"
    assert out["status"] == "needs-upgrade"


def test_checker_needs_upgrade_without_gitleaks_config(tmp_path):
    # v10: a current-version repo missing .gitleaks.toml is flagged for upgrade.
    make_compliant_repo(tmp_path, gitleaks_config=False)
    out = run_checker(tmp_path)
    assert out["has_gitleaks_config"] == "0"
    assert out["status"] == "needs-upgrade"


def test_checker_needs_upgrade_without_jscpd_runner(tmp_path):
    # v14: a current-version repo missing scripts/run-jscpd.sh is flagged for upgrade.
    make_compliant_repo(tmp_path, jscpd_runner=False)
    out = run_checker(tmp_path)
    assert out["has_jscpd_runner"] == "0"
    assert out["status"] == "needs-upgrade"


def test_checker_cooldown_defaults_one_for_non_python(tmp_path):
    # Ruby repo (no pyproject.toml): the uv cooldown can't apply, so has_cooldown
    # defaults to 1 and never blocks — Ruby/JS cooldowns are recommended, not gated.
    version = (ROOT / "skills" / "dev-env-setup" / "VERSION").read_text().strip()
    (tmp_path / "Gemfile").write_text('source "https://rubygems.org"\n')
    (tmp_path / "mise.toml").write_text(
        f'[settings]\nlockfile = true\n[env]\nDEV_ENV_VERSION = "{version}"\n'
    )
    (tmp_path / "mise.lock").write_text("")
    (tmp_path / "hk.pkl").write_text('["gitleaks"] = Builtins.gitleaks\n')
    (tmp_path / ".gitleaks.toml").write_text("[extend]\nuseDefault = true\n")
    wf = tmp_path / ".github" / "workflows"
    wf.mkdir(parents=True)
    (wf / "ci.yml").write_text("name: ci\non: push\n")
    (tmp_path / "README.md").write_text("# x\n")
    (tmp_path / "CLAUDE.md").write_text("# project instructions\n")
    (tmp_path / "scripts").mkdir()
    (tmp_path / "scripts" / "run-jscpd.sh").write_text("#!/usr/bin/env bash\n")
    out = run_checker(tmp_path)
    assert out["stack"] == "ruby"
    assert out["has_cooldown"] == "1"
    assert out["status"] == "compliant"


def test_checker_suggests_fnox_for_plaintext_env(tmp_path):
    # A repo with a non-empty .env (KEY=value) and no fnox.toml → advisory suggests_fnox=1,
    # and the advisory must not change status (the repo is otherwise compliant).
    make_compliant_repo(tmp_path)
    (tmp_path / ".env").write_text("API_KEY=placeholder-not-a-secret\n")
    out = run_checker(tmp_path)
    assert out["suggests_fnox"] == "1"
    assert out["status"] == "compliant"


def test_checker_no_fnox_suggestion_once_migrated(tmp_path):
    # Same plaintext .env, but a fnox.toml is present → already migrated, no nudge.
    make_compliant_repo(tmp_path)
    (tmp_path / ".env").write_text("API_KEY=placeholder-not-a-secret\n")
    (tmp_path / "fnox.toml").write_text("[secrets]\n")
    out = run_checker(tmp_path)
    assert out["suggests_fnox"] == "0"


def test_checker_no_fnox_suggestion_without_secrets(tmp_path):
    # A compliant repo with no .env / credentials / secret references → no nudge.
    make_compliant_repo(tmp_path)
    out = run_checker(tmp_path)
    assert out["suggests_fnox"] == "0"


@pytest.mark.parametrize("vendor_dir", [".venv", "node_modules", "vendor"])
def test_checker_no_fnox_suggestion_from_vendored_dirs(tmp_path, vendor_dir):
    # A vendored/dependency dir whose third-party source contains Settings./ENV[
    # must NOT trigger the fnox nudge — only the repo's OWN source counts.
    # Regression for the readoc false positive (installed python-docx/pymupdf
    # under .venv matched the credential heuristic's grep).
    make_compliant_repo(tmp_path)
    vendored = tmp_path / vendor_dir / "lib" / "pkg"
    vendored.mkdir(parents=True)
    (vendored / "section.py").write_text("x = Settings.foo\ny = ENV['BAR']\n")
    out = run_checker(tmp_path)
    assert out["suggests_fnox"] == "0"

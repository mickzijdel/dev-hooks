"""Tests for the bundled skill scripts.

Golden parity for the ported Python skill CLIs: the golden files in tests/golden/ were
captured from the original Ruby scripts before they were removed; these tests assert the
Python ports reproduce that output byte for byte (and match the recorded exit codes).
gr_modern post-dates the port — it covers heading/command spellings the Python audit
recognises beyond the Ruby original (Install heading, /plugin and uv/mise commands) and
its golden was captured from the Python script.
Plus subprocess tests for the dev-env-setup skill's dev_env_check.sh compliance checker
(harness lives in conftest).
"""

import shutil
import subprocess
import sys

import pytest

from conftest import (
    DEV_HOOKS,
    FIXTURES,
    GOLDEN,
    ROOT,
    WRITING,
    init_git_repo,
    make_compliant_repo,
    parse_kv,
    run_checker,
)

INVENTORY = (
    DEV_HOOKS / "skills" / "dependency-upgrade" / "scripts" / "upgrade_inventory.sh"
)

GR = WRITING / "skills" / "github-readme" / "scripts" / "github_readme_audit.py"
RA = WRITING / "skills" / "readability" / "scripts" / "readability_audit.py"
FK = WRITING / "skills" / "readability" / "scripts" / "flesch_kincaid.py"
VP = WRITING / "skills" / "readability" / "scripts" / "vocabulary_profiler.py"
A11Y = DEV_HOOKS / "skills" / "accessibility" / "scripts" / "a11y_audit.py"

# (golden name, script, args, stdin fixture filename or None)
CASES = [
    ("gr_sample", GR, ["tests/fixtures/sample_readme.md"], None),
    ("gr_sample_strict", GR, ["tests/fixtures/sample_readme.md", "--strict"], None),
    ("gr_bad", GR, ["tests/fixtures/bad_readme.md"], None),
    ("gr_bad_strict", GR, ["tests/fixtures/bad_readme.md", "--strict"], None),
    ("gr_modern", GR, ["tests/fixtures/modern_readme.md"], None),
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


def test_checker_needs_upgrade_without_exec_bit_step(tmp_path):
    # v15: a current-version repo whose hk.pkl lacks the exec-bit-scripts step is flagged.
    make_compliant_repo(tmp_path, exec_bit=False)
    out = run_checker(tmp_path)
    assert out["has_exec_bit"] == "0"
    assert out["status"] == "needs-upgrade"


def test_checker_compliant_has_sha_pinned_ci(tmp_path):
    # v16: the default compliant repo ships a SHA-pinned `uses:` and reports it pinned.
    make_compliant_repo(tmp_path)
    out = run_checker(tmp_path)
    assert out["has_sha_pinned_ci"] == "1"
    assert out["status"] == "compliant"


def test_checker_needs_upgrade_with_tag_pinned_action(tmp_path):
    # v16: a current-version repo whose CI still pins an action by mutable tag is flagged.
    make_compliant_repo(tmp_path, sha_pinned=False)
    out = run_checker(tmp_path)
    assert out["has_sha_pinned_ci"] == "0"
    assert out["status"] == "needs-upgrade"


def test_checker_cooldown_defaults_one_for_non_python(tmp_path):
    # Ruby repo (no pyproject.toml): the uv cooldown can't apply, so has_cooldown
    # defaults to 1 and never blocks — Ruby/JS cooldowns are recommended, not gated.
    version = (DEV_HOOKS / "skills" / "dev-env-setup" / "VERSION").read_text().strip()
    (tmp_path / "Gemfile").write_text('source "https://rubygems.org"\n')
    (tmp_path / "mise.toml").write_text(
        f'[settings]\nlockfile = true\n[env]\nDEV_ENV_VERSION = "{version}"\n'
    )
    (tmp_path / "mise.lock").write_text("")
    (tmp_path / "hk.pkl").write_text(
        '["gitleaks"] = Builtins.gitleaks\n["exec-bit-scripts"] { check = "..." }\n'
    )
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


# ── upgrade_inventory.sh (dependency-upgrade skill preflight) ───────────────────────
def run_inventory(target, *args):
    """Run the dependency-upgrade preflight (default mode — read-only, no tool exec)
    and parse its key=value block."""
    r = subprocess.run(
        ["bash", str(INVENTORY), str(target), *args],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr
    return parse_kv(r.stdout), r.stdout


def test_inventory_empty_repo_detects_nothing(tmp_path):
    out, stdout = run_inventory(tmp_path)
    assert out["has_js"] == "0"
    assert out["has_ruby"] == "0"
    assert out["has_python"] == "0"
    assert out["has_actions"] == "0"
    assert out["ecosystems"] == ""
    assert "No JavaScript/Ruby/Python/GitHub-Actions dependencies" in stdout


def test_inventory_detects_all_ecosystems(tmp_path):
    (tmp_path / "package.json").write_text("{}\n")
    (tmp_path / "Gemfile").write_text('source "https://rubygems.org"\n')
    (tmp_path / "pyproject.toml").write_text("[project]\nname='x'\n")
    wf = tmp_path / ".github" / "workflows"
    wf.mkdir(parents=True)
    (wf / "ci.yml").write_text("name: ci\non: push\n")
    out, _ = run_inventory(tmp_path)
    assert out["has_js"] == "1"
    assert out["has_ruby"] == "1"
    assert out["has_python"] == "1"
    assert out["has_actions"] == "1"
    assert out["actions_count"] == "1"
    assert out["ecosystems"] == "js ruby python actions"
    assert out["ruby_manager"] == "bundler"


@pytest.mark.parametrize(
    "lockfile,expected",
    [("pnpm-lock.yaml", "pnpm"), ("yarn.lock", "yarn"), ("package-lock.json", "npm")],
)
def test_inventory_js_manager_from_lockfile(tmp_path, lockfile, expected):
    (tmp_path / "package.json").write_text("{}\n")
    (tmp_path / lockfile).write_text("\n")
    out, _ = run_inventory(tmp_path)
    assert out["js_manager"] == expected


def test_inventory_js_manager_defaults_to_npm_without_lockfile(tmp_path):
    (tmp_path / "package.json").write_text("{}\n")
    out, _ = run_inventory(tmp_path)
    assert out["js_manager"] == "npm"


def test_inventory_python_manager_uv_from_lock(tmp_path):
    (tmp_path / "pyproject.toml").write_text("[project]\nname='x'\n")
    (tmp_path / "uv.lock").write_text("\n")
    out, _ = run_inventory(tmp_path)
    assert out["python_manager"] == "uv"


def test_inventory_python_manager_uv_from_tool_table(tmp_path):
    (tmp_path / "pyproject.toml").write_text(
        "[project]\nname='x'\n[tool.uv]\nexclude-newer = \"4 days\"\n"
    )
    out, _ = run_inventory(tmp_path)
    assert out["python_manager"] == "uv"


def test_inventory_python_manager_poetry_from_tool_table(tmp_path):
    (tmp_path / "pyproject.toml").write_text("[tool.poetry]\nname='x'\n")
    out, _ = run_inventory(tmp_path)
    assert out["python_manager"] == "poetry"


def test_inventory_python_manager_pip_fallback(tmp_path):
    # requirements.txt with no uv/poetry signal → pip.
    (tmp_path / "requirements.txt").write_text("requests==2.0.0\n")
    out, _ = run_inventory(tmp_path)
    assert out["has_python"] == "1"
    assert out["python_manager"] == "pip"


# ── a11y_audit.py (accessibility skill checker) ──────────────────────────────────────
_BAD_MARKUP = (
    "<html>\n"
    '  <img src="logo.png">\n'
    "  <button><svg></svg></button>\n"
    '  <div onclick="go()">Menu</div>\n'
    '  <input type="text" placeholder="Name">\n'
    '  <a href="#" tabindex="3">x</a>\n'
    "</html>\n"
)
_GOOD_MARKUP = (
    '<html lang="en">\n'
    '  <img src="logo.png" alt="Company logo">\n'
    '  <label for="n">Name</label><input id="n" type="text">\n'
    '  <button type="button" aria-label="Delete"><svg aria-hidden="true"></svg></button>\n'
    "</html>\n"
)


def _run_a11y(*args, cwd=None):
    return subprocess.run(
        [sys.executable, str(A11Y), *args],
        cwd=cwd,
        capture_output=True,
        text=True,
    )


def test_a11y_audit_flags_issues(tmp_path):
    f = tmp_path / "page.html"
    f.write_text(_BAD_MARKUP)
    r = _run_a11y(str(f))
    assert r.returncode == 1
    out = r.stdout
    assert "missing a lang attribute" in out
    assert "no alt attribute" in out
    assert "icon-only <button>" in out
    assert "non-interactive" in out
    assert "no label association" in out
    assert "positive tabindex" in out
    # Each finding is reported as file:line:
    assert f"{f}:2:" in out  # the <img> is on line 2


def test_a11y_audit_clean_file(tmp_path):
    f = tmp_path / "ok.html"
    f.write_text(_GOOD_MARKUP)
    r = _run_a11y(str(f))
    assert r.returncode == 0
    assert r.stdout == ""
    assert "No accessibility issues" in r.stderr


def test_a11y_audit_jsx_htmlfor_is_label(tmp_path):
    # React uses htmlFor; an input with an id is considered labelable, so no false positive.
    f = tmp_path / "Form.jsx"
    f.write_text('<label htmlFor="e">Email</label><input id="e" type="email" />\n')
    r = _run_a11y(str(f))
    assert r.returncode == 0


def test_a11y_audit_no_markup_files(tmp_path):
    f = tmp_path / "notes.txt"
    f.write_text("not markup")
    r = _run_a11y(str(f))
    assert r.returncode == 2


@pytest.mark.skipif(shutil.which("uv") is None, reason="uv not installed")
def test_a11y_audit_runs_via_uv_shebang(tmp_path):
    """The shipping path: the PEP 723 script self-resolves via `uv run --script`."""
    f = tmp_path / "ok.html"
    f.write_text(_GOOD_MARKUP)
    r = subprocess.run([str(A11Y), str(f)], capture_output=True, text=True)
    assert r.returncode == 0

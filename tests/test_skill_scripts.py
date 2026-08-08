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

import json
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

DETECT = DEV_HOOKS / "skills" / "repo-review" / "scripts" / "detect_stack.sh"

GR = WRITING / "skills" / "github-readme" / "scripts" / "github_readme_audit.py"
RA = WRITING / "skills" / "readability" / "scripts" / "readability_audit.py"
FK = WRITING / "skills" / "readability" / "scripts" / "flesch_kincaid.py"
VP = WRITING / "skills" / "readability" / "scripts" / "vocabulary_profiler.py"
A11Y = DEV_HOOKS / "skills" / "accessibility" / "scripts" / "a11y_audit.py"
HAR_SCAN = DEV_HOOKS / "skills" / "api-scraping" / "scripts" / "har_scan.py"
VOICE = WRITING / "skills" / "voice-profile" / "scripts" / "voice_audit.py"
SCRIPT_TEMPLATE = DEV_HOOKS / "skills" / "script-library" / "references" / "template.py"
DEFAULT_RULES = WRITING / "skills" / "voice-profile" / "references" / "default-rules.md"

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


# ── script-library reference template ────────────────────────────────────────────────
def test_script_template_help_runs_clean():
    """The script-library template is the standard it teaches: a real argparse --help."""
    result = subprocess.run(
        [sys.executable, str(SCRIPT_TEMPLATE), "--help"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert "usage" in result.stdout.lower()


def test_script_template_default_run():
    result = subprocess.run(
        [sys.executable, str(SCRIPT_TEMPLATE), "claude", "--shout"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert result.stdout == "HELLO, CLAUDE!\n"


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


def test_checker_needs_upgrade_without_version_sync(tmp_path):
    # v23: a current-version repo missing scripts/check_version_sync.sh is flagged for upgrade.
    make_compliant_repo(tmp_path, version_sync=False)
    out = run_checker(tmp_path)
    assert out["has_version_sync"] == "0"
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


def test_checker_compliant_has_zizmor(tmp_path):
    # v18: the default compliant repo's hk.pkl carries the zizmor step.
    make_compliant_repo(tmp_path)
    out = run_checker(tmp_path)
    assert out["has_zizmor"] == "1"
    assert out["status"] == "compliant"


def test_checker_needs_upgrade_without_zizmor(tmp_path):
    # v18: a current-version repo whose hk.pkl lacks the zizmor step is flagged for upgrade.
    make_compliant_repo(tmp_path, zizmor=False)
    out = run_checker(tmp_path)
    assert out["has_zizmor"] == "0"
    assert out["status"] == "needs-upgrade"


def test_checker_compliant_has_actionlint(tmp_path):
    # v18: the default compliant repo's hk.pkl carries the actionlint step.
    make_compliant_repo(tmp_path)
    out = run_checker(tmp_path)
    assert out["has_actionlint"] == "1"
    assert out["status"] == "compliant"


def test_checker_needs_upgrade_without_actionlint(tmp_path):
    # v18: a current-version repo whose hk.pkl lacks the actionlint step is flagged for upgrade.
    make_compliant_repo(tmp_path, actionlint=False)
    out = run_checker(tmp_path)
    assert out["has_actionlint"] == "0"
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
        '["zizmor"] = Builtins.zizmor\n["actionlint"] = Builtins.actionlint\n'
    )
    (tmp_path / ".gitleaks.toml").write_text("[extend]\nuseDefault = true\n")
    wf = tmp_path / ".github" / "workflows"
    wf.mkdir(parents=True)
    (wf / "ci.yml").write_text("name: ci\non: push\n")
    (tmp_path / "README.md").write_text("# x\n")
    (tmp_path / "CLAUDE.md").write_text("# project instructions\n")
    (tmp_path / "scripts").mkdir()
    (tmp_path / "scripts" / "run-jscpd.sh").write_text("#!/usr/bin/env bash\n")
    (tmp_path / "scripts" / "check_version_sync.sh").write_text("#!/usr/bin/env bash\n")
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


# ── dev container drift (advisory, v19) ─────────────────────────────────────────────
def _mise_driven_dockerfile():
    return (
        "# syntax=docker/dockerfile:1\n"
        "FROM debian:trixie-slim\n"
        "RUN extrepo enable mise && apt-get install -y mise\n"
    )


def test_checker_no_devcontainer_signal_when_absent(tmp_path):
    # Default compliant repo has no .devcontainer/ → has_devcontainer=0, no drift, compliant.
    make_compliant_repo(tmp_path)
    out = run_checker(tmp_path)
    assert out["has_devcontainer"] == "0"
    assert out["devcontainer_mise_driven"] == "1"
    assert out["status"] == "compliant"


def test_checker_devcontainer_mise_driven(tmp_path):
    # A mise-driven .devcontainer/ (debian base + extrepo mise) → detected, no drift, and the
    # repo stays compliant (the devcontainer signal never changes status).
    make_compliant_repo(tmp_path)
    dc = tmp_path / ".devcontainer"
    dc.mkdir()
    (dc / "devcontainer.json").write_text('{"name": "x"}\n')
    (dc / "Dockerfile.dev").write_text(_mise_driven_dockerfile())
    out = run_checker(tmp_path)
    assert out["has_devcontainer"] == "1"
    assert out["devcontainer_mise_driven"] == "1"
    assert out["status"] == "compliant"


def test_checker_flags_hardcoded_base_devcontainer(tmp_path):
    # A .devcontainer/ with a hardcoded language base + nodesource-style nodejs + global pnpm
    # drifts from the mise toolchain → devcontainer_mise_driven=0 (advisory). It must NOT force
    # status to needs-upgrade — the otherwise-compliant repo stays compliant.
    make_compliant_repo(tmp_path)
    dc = tmp_path / ".devcontainer"
    dc.mkdir()
    (dc / "devcontainer.json").write_text('{"name": "x"}\n')
    (dc / "Dockerfile.dev").write_text(
        "FROM ruby:4.0.2-slim\nRUN apt-get install -y nodejs\nRUN npm install -g pnpm\n"
    )
    out = run_checker(tmp_path)
    assert out["has_devcontainer"] == "1"
    assert out["devcontainer_mise_driven"] == "0"
    assert out["status"] == "compliant"


def test_checker_devcontainer_drift_does_not_flag_comments(tmp_path):
    # The shipped Dockerfile.dev template carries cautionary comments ("do NOT add
    # `apt-get install nodejs`", "no `npm install -g pnpm`"). Comment lines are stripped before
    # scanning, so a faithful mise-driven devcontainer that merely *mentions* those in comments
    # must not self-flag.
    make_compliant_repo(tmp_path)
    dc = tmp_path / ".devcontainer"
    dc.mkdir()
    (dc / "Dockerfile.dev").write_text(
        "# syntax=docker/dockerfile:1\n"
        "# Do NOT add `apt-get install nodejs` or a `ruby:x.y` base or `npm install -g pnpm`.\n"
        "FROM debian:trixie-slim\n"
        "RUN extrepo enable mise && apt-get install -y mise\n"
    )
    out = run_checker(tmp_path)
    assert out["devcontainer_mise_driven"] == "1"


def test_checker_devcontainer_base_os_mismatch(tmp_path):
    # Both the devcontainer base and a root ./Dockerfile name a Debian codename directly, and
    # they differ → best-effort base-os-mismatch drift.
    make_compliant_repo(tmp_path)
    (tmp_path / "Dockerfile").write_text("FROM debian:trixie-slim\n")
    dc = tmp_path / ".devcontainer"
    dc.mkdir()
    (dc / "Dockerfile.dev").write_text(
        "FROM debian:bookworm-slim\n"
        "RUN extrepo enable mise && apt-get install -y mise\n"
    )
    out = run_checker(tmp_path)
    assert out["devcontainer_mise_driven"] == "0"


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


# ── detect_stack.sh (repo-review skill preflight) ────────────────────────────────────
def run_detect(target, *args):
    """Run the repo-review preflight (read-only) and parse its key=value block."""
    r = subprocess.run(
        ["bash", str(DETECT), str(target), *args],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr
    return parse_kv(r.stdout), r.stdout


def test_detect_empty_repo_finds_no_surfaces(tmp_path):
    out, _ = run_detect(tmp_path)
    assert out["is_rails"] == "0"
    assert out["has_frontend"] == "0"
    assert out["has_ci"] == "0"
    assert out["has_tests"] == "0"
    assert out["has_docker"] == "0"
    assert out["has_devenv"] == "0"
    assert out["languages"] == ""


def test_detect_languages_by_source_extension(tmp_path):
    (tmp_path / "main.py").write_text("print('hi')\n")
    (tmp_path / "app.ts").write_text("export {}\n")
    out, _ = run_detect(tmp_path)
    langs = out["languages"].split()
    assert "python" in langs
    assert "typescript" in langs
    assert "ruby" not in langs


def test_detect_rails_app_delegates_to_rails_audit(tmp_path):
    (tmp_path / "Gemfile").write_text('source "https://rubygems.org"\ngem "rails"\n')
    (tmp_path / "app").mkdir()
    (tmp_path / "config").mkdir()
    out, stdout = run_detect(tmp_path)
    assert out["is_rails"] == "1"
    assert "rails-audit" in stdout


def test_detect_gemfile_without_rails_is_not_rails(tmp_path):
    # A plain Ruby repo (Gemfile but no rails gem / app+config) stays generic.
    (tmp_path / "Gemfile").write_text('source "https://rubygems.org"\ngem "sinatra"\n')
    (tmp_path / "app").mkdir()
    (tmp_path / "config").mkdir()
    out, _ = run_detect(tmp_path)
    assert out["is_rails"] == "0"


def test_detect_frontend_triggers_accessibility_axis(tmp_path):
    (tmp_path / "index.html").write_text("<html></html>\n")
    out, stdout = run_detect(tmp_path)
    assert out["has_frontend"] == "1"
    assert "accessibility" in stdout


def test_detect_ci_tests_docker_devenv_surfaces(tmp_path):
    wf = tmp_path / ".github" / "workflows"
    wf.mkdir(parents=True)
    (wf / "ci.yml").write_text("name: ci\non: push\n")
    (tmp_path / "tests").mkdir()
    (tmp_path / "Dockerfile").write_text("FROM alpine\n")
    (tmp_path / "mise.toml").write_text("[tools]\n")
    out, stdout = run_detect(tmp_path)
    assert out["has_ci"] == "1"
    assert out["has_tests"] == "1"
    assert out["has_docker"] == "1"
    assert out["has_devenv"] == "1"
    assert "github-actions" in stdout
    assert "dev-env-setup" in stdout


def test_detect_monorepo_lists_subprojects(tmp_path):
    (tmp_path / "frontend").mkdir()
    (tmp_path / "frontend" / "package.json").write_text("{}\n")
    (tmp_path / "backend").mkdir()
    (tmp_path / "backend" / "pyproject.toml").write_text("[project]\nname='x'\n")
    out, stdout = run_detect(tmp_path)
    subs = out["subprojects"].split()
    assert "frontend" in subs
    assert "backend" in subs
    assert "Monorepo: 2 sub-projects" in stdout


def test_detect_single_root_project_is_not_a_monorepo(tmp_path):
    # A manifest at the root only (no nested ones) is one project, not a monorepo.
    (tmp_path / "pyproject.toml").write_text("[project]\nname='x'\n")
    (tmp_path / "main.py").write_text("print('hi')\n")
    out, stdout = run_detect(tmp_path)
    assert out["subprojects"] == ""
    assert "Monorepo" not in stdout


# ── fleet_roster.sh (dev-env-setup fleet discovery) ──────────────────────────────────
ROSTER = DEV_HOOKS / "skills" / "dev-env-setup" / "scripts" / "fleet_roster.sh"


def run_roster(*roots):
    """Run the fleet discovery and parse its tab-separated repo lines into
    {name: {field: value}} (repo paths may contain spaces, hence tabs)."""
    r = subprocess.run(
        ["bash", str(ROSTER), *map(str, roots)],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr
    repos = {}
    for line in r.stdout.splitlines():
        if line.startswith("repo="):
            kv = dict(field.partition("=")[::2] for field in line.split("\t"))
            repos[kv["name"]] = kv
    return repos, r.stdout


def make_fleet_repo(path, version):
    """A minimal fleet member: a committed git repo whose mise.toml carries
    DEV_ENV_VERSION."""
    path.mkdir(parents=True, exist_ok=True)
    (path / "mise.toml").write_text(f'[env]\nDEV_ENV_VERSION = "{version}"\n')
    run = init_git_repo(path)
    run("add", "-A")
    run("commit", "-q", "-m", "init")
    return run


def test_roster_reports_stamped_repo_with_version_branch_and_clean_state(tmp_path):
    repo = tmp_path / "alpha"
    make_fleet_repo(repo, 7)
    repos, _ = run_roster(tmp_path)
    assert repos["alpha"]["repo"] == str(repo)
    assert repos["alpha"]["version"] == "7"
    assert repos["alpha"]["branch"] == "main"
    assert repos["alpha"]["dirty"] == "0"


def test_roster_excludes_unstamped_repos(tmp_path):
    make_fleet_repo(tmp_path / "stamped", 5)
    plain = tmp_path / "plain"
    plain.mkdir()
    (plain / "mise.toml").write_text("[tools]\n")
    bare = tmp_path / "bare"
    bare.mkdir()
    (bare / "README.md").write_text("no mise here\n")
    repos, _ = run_roster(tmp_path)
    assert set(repos) == {"stamped"}


def test_roster_flags_dirty_worktree(tmp_path):
    repo = tmp_path / "messy"
    make_fleet_repo(repo, 5)
    (repo / "scratch.txt").write_text("wip\n")
    repos, _ = run_roster(tmp_path)
    assert repos["messy"]["dirty"] == "1"


def test_roster_behind_iff_older_than_current_standard(tmp_path):
    current = (DEV_HOOKS / "skills" / "dev-env-setup" / "VERSION").read_text().strip()
    make_fleet_repo(tmp_path / "old", 1)
    make_fleet_repo(tmp_path / "fresh", current)
    repos, stdout = run_roster(tmp_path)
    assert repos["old"]["behind"] == "1"
    assert repos["fresh"]["behind"] == "0"
    assert f"current_version={current}" in stdout


def test_roster_skips_nested_worktree_checkouts(tmp_path):
    make_fleet_repo(tmp_path / "host", 5)
    # A stamped checkout under the host's .worktrees/ must not appear as a repo.
    make_fleet_repo(tmp_path / "host" / ".worktrees" / "feat-x", 5)
    repos, _ = run_roster(tmp_path)
    assert set(repos) == {"host"}
    # Same when the scan root is the repo itself.
    repos, _ = run_roster(tmp_path / "host")
    assert set(repos) == {"host"}


def test_roster_multiple_roots_and_missing_root(tmp_path):
    make_fleet_repo(tmp_path / "r1" / "one", 5)
    make_fleet_repo(tmp_path / "r2" / "two", 5)
    repos, stdout = run_roster(tmp_path / "r1", tmp_path / "r2", tmp_path / "nope")
    assert set(repos) == {"one", "two"}
    assert "# fleet: 2 repo(s)" in stdout


def test_roster_skips_repos_in_fleet_ignore(tmp_path):
    """A repo whose basename is listed in references/fleet-ignore.txt (an abandoned repo, a
    fork you don't own) is dropped from discovery even though it carries a DEV_ENV_VERSION
    stamp — the retirement lives in the skill, so the repo itself is never touched."""
    ignore_file = (
        DEV_HOOKS / "skills" / "dev-env-setup" / "references" / "fleet-ignore.txt"
    )
    listed = [ln.split("#")[0].strip() for ln in ignore_file.read_text().splitlines()]
    listed = [n for n in listed if n]
    assert listed, (
        "fleet-ignore.txt should name at least one retired repo to exercise this"
    )
    make_fleet_repo(tmp_path / listed[0], 5)  # a retired repo …
    make_fleet_repo(tmp_path / "keep", 5)  # … and one that stays in the fleet
    repos, _ = run_roster(tmp_path)
    assert set(repos) == {"keep"}


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


# ── har_scan.py (api-scraping skill; find the data endpoint in a HAR) ────────────────
def _write_har(path):
    """A capture with a document, a stylesheet, an image (all noise), one JSON XHR that
    carries the data, and a GraphQL POST — the shape har_scan is built to sift."""
    har = {
        "log": {
            "version": "1.2",
            "entries": [
                {
                    "_resourceType": "document",
                    "request": {
                        "method": "GET",
                        "url": "https://shop.example.com/s?q=x",
                    },
                    "response": {
                        "status": 200,
                        "content": {
                            "mimeType": "text/html",
                            "size": 5120,
                            "text": "<html></html>",
                        },
                    },
                },
                {
                    "_resourceType": "stylesheet",
                    "request": {
                        "method": "GET",
                        "url": "https://shop.example.com/app.css",
                    },
                    "response": {
                        "status": 200,
                        "content": {"mimeType": "text/css", "size": 800},
                    },
                },
                {
                    "_resourceType": "xhr",
                    "request": {
                        "method": "GET",
                        "url": "https://api.example.com/v2/products?q=x&page=1&limit=50",
                    },
                    "response": {
                        "status": 200,
                        "content": {
                            "mimeType": "application/json",
                            "size": 4800,
                            "text": '{"results":[{"name":"Pixel 9 Pro"}],"next_cursor":"abc"}',
                        },
                    },
                },
                {
                    "_resourceType": "fetch",
                    "request": {
                        "method": "POST",
                        "url": "https://api.example.com/graphql",
                        "postData": {
                            "mimeType": "application/json",
                            "text": '{"operationName":"Reviews","query":"query Reviews{x}"}',
                        },
                    },
                    "response": {
                        "status": 200,
                        "content": {
                            "mimeType": "application/json",
                            "size": 200,
                            "text": '{"data":{}}',
                        },
                    },
                },
                {
                    "_resourceType": "image",
                    "request": {
                        "method": "GET",
                        "url": "https://cdn.example.com/logo.png",
                    },
                    "response": {
                        "status": 200,
                        "content": {"mimeType": "image/png", "size": 300},
                    },
                },
            ],
        }
    }
    path.write_text(json.dumps(har))


def _run_har_scan(*args):
    return subprocess.run(
        [sys.executable, str(HAR_SCAN), *args],
        capture_output=True,
        text=True,
    )


def test_har_scan_ranks_api_candidates_and_skips_noise(tmp_path):
    har = tmp_path / "capture.har"
    _write_har(har)
    r = _run_har_scan(str(har))
    assert r.returncode == 0
    # Two JSON XHR/fetch requests are candidates; the html/css/png are dropped.
    assert "2 API candidate(s) out of 5 request(s)" in r.stdout
    assert "https://api.example.com/v2/products" in r.stdout
    assert "https://api.example.com/graphql" in r.stdout
    assert "logo.png" not in r.stdout
    # Query params are split out for the parametrize step; GraphQL op is named.
    assert "? page = 1" in r.stdout
    assert "graphql: Reviews" in r.stdout


def test_har_scan_find_marks_the_matching_request(tmp_path):
    har = tmp_path / "capture.har"
    _write_har(har)
    r = _run_har_scan(str(har), "--find", "Pixel 9 Pro")
    assert r.returncode == 0
    assert "1 matched your search" in r.stdout
    # The match marker sits on the products endpoint, not the reviews one.
    match_line = next(ln for ln in r.stdout.splitlines() if "MATCH" in ln)
    assert "v2/products" in match_line


def test_har_scan_find_miss_warns_on_stderr(tmp_path):
    har = tmp_path / "capture.har"
    _write_har(har)
    r = _run_har_scan(str(har), "--find", "no-such-value")
    assert r.returncode == 0
    assert "0 matched your search" in r.stdout
    assert "No response body matched" in r.stderr


def test_har_scan_all_includes_non_api_entries(tmp_path):
    har = tmp_path / "capture.har"
    _write_har(har)
    r = _run_har_scan(str(har), "--all")
    assert r.returncode == 0
    assert "5 API candidate(s) out of 5 request(s)" in r.stdout
    assert "logo.png" in r.stdout


def test_har_scan_rejects_non_har(tmp_path):
    bad = tmp_path / "notes.txt"
    bad.write_text("not json at all")
    r = _run_har_scan(str(bad))
    assert r.returncode == 2
    assert "not a valid HAR" in r.stderr


@pytest.mark.parametrize("size,body_size", [(None, None), ("123", "456")])
def test_har_scan_tolerates_non_numeric_sizes(tmp_path, size, body_size):
    # HAR spec says size/bodySize are numbers, but exporters emit `null` or even a string;
    # ranking must not choke on either (regression: `None > 0` / `"123" > 0` blew up the
    # whole scan in rank_key/analyse).
    har = tmp_path / "capture.har"
    har.write_text(
        json.dumps(
            {
                "log": {
                    "entries": [
                        {
                            "_resourceType": "xhr",
                            "request": {
                                "method": "GET",
                                "url": "https://api.example.com/v2/x?page=1",
                            },
                            "response": {
                                "status": 200,
                                "bodySize": body_size,
                                "content": {
                                    "mimeType": "application/json",
                                    "size": size,
                                    "text": '{"a":1}',
                                },
                            },
                        }
                    ]
                }
            }
        )
    )
    r = _run_har_scan(str(har))
    assert r.returncode == 0, r.stderr
    assert "https://api.example.com/v2/x" in r.stdout
    assert "?" in r.stdout  # unknown size renders as '?', not a traceback


def test_har_scan_missing_file(tmp_path):
    r = _run_har_scan(str(tmp_path / "nope.har"))
    assert r.returncode == 2
    assert "no such file" in r.stderr


@pytest.mark.skipif(shutil.which("uv") is None, reason="uv not installed")
def test_har_scan_runs_via_uv_shebang(tmp_path):
    """The shipping path: the PEP 723 script self-resolves via `uv run --script`."""
    har = tmp_path / "capture.har"
    _write_har(har)
    r = subprocess.run([str(HAR_SCAN), str(har)], capture_output=True, text=True)
    assert r.returncode == 0


# ── voice_audit.py (voice-profile skill; banned-word scanner) ───────────────────────
def _run_voice_audit(profile, *files):
    return subprocess.run(
        [sys.executable, str(VOICE), "--profile", str(profile), *map(str, files)],
        capture_output=True,
        text=True,
    )


def test_voice_audit_flags_banned_words(tmp_path):
    doc = tmp_path / "draft.md"
    doc.write_text(
        "This is the cleanest design.\n"
        "The model converts the metric into a score.\n"
        "This reads as a warning.\n"
    )
    r = _run_voice_audit(DEFAULT_RULES, doc)
    assert r.returncode == 1
    assert f"{doc}:1: avoid" in r.stdout
    assert "cleanest" in r.stdout
    assert "converts the metric into" in r.stdout  # `converts ... into` wildcard
    assert "reads as" in r.stdout
    assert "(use:" in r.stdout  # rewrite hint surfaced from the profile


def test_voice_audit_clean_prose(tmp_path):
    doc = tmp_path / "ok.md"
    doc.write_text("This is a solid design that rescales the metric.\n")
    r = _run_voice_audit(DEFAULT_RULES, doc)
    assert r.returncode == 0
    assert r.stdout == ""
    assert "No banned words" in r.stderr


def test_voice_audit_skips_code_blocks_and_inline_code(tmp_path):
    doc = tmp_path / "doc.md"
    doc.write_text(
        "Prose stays plain here.\n\n"
        "```\nclean up the cleanest code\n```\n\n"
        "Inline `clean` is ignored too.\n"
    )
    r = _run_voice_audit(DEFAULT_RULES, doc)
    assert r.returncode == 0, r.stdout


def test_voice_audit_word_boundaries(tmp_path):
    # `clean` must not fire inside "cleanly"; `cleanest` is its own banned term.
    doc = tmp_path / "doc.md"
    doc.write_text("She wrote cleanly and the cleanup went well.\n")
    r = _run_voice_audit(DEFAULT_RULES, doc)
    assert r.returncode == 0, r.stdout


def test_voice_audit_missing_profile(tmp_path):
    doc = tmp_path / "draft.md"
    doc.write_text("text\n")
    r = _run_voice_audit(tmp_path / "nope.md", doc)
    assert r.returncode == 2
    assert "profile not found" in r.stderr


def test_voice_audit_profile_without_terms(tmp_path):
    profile = tmp_path / "empty_profile.md"
    profile.write_text("# Voice\n\n## Do\n\n- be plain\n")
    doc = tmp_path / "draft.md"
    doc.write_text("the cleanest thing\n")
    r = _run_voice_audit(profile, doc)
    assert r.returncode == 2
    assert "no banned terms" in r.stderr


@pytest.mark.skipif(shutil.which("uv") is None, reason="uv not installed")
def test_voice_audit_runs_via_uv_shebang(tmp_path):
    """The shipping path: the PEP 723 script self-resolves via `uv run --script`."""
    doc = tmp_path / "ok.md"
    doc.write_text("A solid design.\n")
    r = subprocess.run(
        [str(VOICE), "--profile", str(DEFAULT_RULES), str(doc)],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0

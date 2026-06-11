"""Content checks for the dev-env-setup CI templates.

These guard the gitleaks job that ships in every scaffolded repo: since v11 it runs the
MIT-licensed gitleaks CLI via mise (gitleaks/gitleaks-action is commercial since its
v2.0.0 and demands a paid GITLEAKS_LICENSE on org-owned repos), scanning full git
history. A plain file-content read is enough — no subprocess needed — so the checks stay
fast and offline.
"""

import ast
import json
import re

import pytest

from conftest import ROOT

TEMPLATES_DIR = ROOT / "skills" / "dev-env-setup" / "references" / "templates"
CI_TEMPLATES = ["ci.python.yml", "ci.ruby.yml", "ci.shell.yml", "ci.js.yml"]
MISE_TEMPLATES = [
    "mise.python.toml",
    "mise.ruby.toml",
    "mise.shell.toml",
    "mise.js.toml",
]
VERSION_FILE = ROOT / "skills" / "dev-env-setup" / "VERSION"
SKILL_MD = ROOT / "skills" / "dev-env-setup" / "SKILL.md"
STANDARD_MD = ROOT / "skills" / "dev-env-setup" / "references" / "standard.md"
MISSING_TEST_HOOK = ROOT / "hooks" / "scripts" / "missing-test-reminder.sh"
GITLEAKS_TEMPLATE = TEMPLATES_DIR / ".gitleaks.toml"

# Templates carrying shebang-based companion-step detectors for extensionless scripts.
SHEBANG_DETECTOR_TEMPLATES = [
    "hk.shell.pkl",
    "hk.python.pkl",
    "ci.shell.yml",
    "ci.python.yml",
]


@pytest.mark.parametrize("name", CI_TEMPLATES)
def test_gitleaks_job_runs_cli_not_action(name):
    """v11: the gitleaks job runs the MIT-licensed CLI via mise. gitleaks/gitleaks-action
    is commercial since its v2.0.0 and requires a paid GITLEAKS_LICENSE on org-owned repos
    (the free tier covers 1 repo per org), so the action must not reappear — and neither
    should its GITHUB_TOKEN env, which only the action needed."""
    text = (TEMPLATES_DIR / name).read_text()
    assert "uses: gitleaks/gitleaks-action" not in text
    assert "mise exec -- gitleaks git --redact --no-banner ." in text
    assert "secrets.GITHUB_TOKEN" not in text


@pytest.mark.parametrize("name", CI_TEMPLATES)
def test_gitleaks_job_scans_full_history_via_mise(name):
    """`gitleaks git` scans commit history, so the job's checkout needs fetch-depth: 0,
    and the CLI must come from mise-action (mise.lock-pinned, same binary as the hk hook)."""
    text = (TEMPLATES_DIR / name).read_text()
    # Both delimiters must exist, else the slice silently widens to the rest of the file
    # and the assertions below could pass on the audit job's own fetch-depth/mise-action.
    assert "\n  gitleaks:\n" in text and "\n  audit:\n" in text
    job = text.split("\n  gitleaks:\n")[1].split("\n  audit:\n")[0]
    assert "fetch-depth: 0" in job
    assert "uses: jdx/mise-action@v4" in job


@pytest.mark.parametrize("name", SHEBANG_DETECTOR_TEMPLATES)
def test_shebang_detector_matches_line_one_only(name):
    """The companion-step shebang detector must read line 1 only (head -n1), not the
    whole file. `grep -lE '^#!…'` matches a `#!` anywhere, so a shebang embedded in a
    fenced code block in docs gets misdetected as a script and the linter chokes parsing
    prose as code. Regression guard for that bug."""
    text = (TEMPLATES_DIR / name).read_text()
    # The buggy whole-file detector must be gone.
    assert "grep -lE '^#!" not in text, (
        f"{name} still uses the whole-file `grep -lE '^#!…'` detector"
    )
    # The line-1-only form must be present.
    assert "head -n1" in text, f"{name} is missing the `head -n1` line-1 detector"


def test_gitleaks_template_allowlists_gitignored_artifacts():
    """The v10 .gitleaks.toml extends the default ruleset and allowlists the gitignored
    runtime/secret PATHS — gitleaks `dir` scans the whole tree (no respect-gitignore flag),
    so without this every commit fails on local .env/log/*.key. The allowlist must stay
    path-scoped (these gitignored locations only) so app/config source is still scanned."""
    text = GITLEAKS_TEMPLATE.read_text()
    assert "useDefault = true" in text, "must extend the default ruleset"
    # Allowlist must cover the gitignored secret/artifact paths the standard relies on.
    for needle in (r"^\.env", "log/", r"config/credentials/.*\.key"):
        assert needle in text, f".gitleaks.toml allowlist is missing {needle!r}"


@pytest.mark.parametrize("name", MISE_TEMPLATES)
def test_mise_template_version_stamp_matches_version_file(name):
    """Every mise template's DEV_ENV_VERSION must equal the VERSION source of truth.
    Regression guard: the python/ruby/shell templates sat at "9" through three standard
    bumps, so freshly scaffolded repos immediately flagged as needing a v9→v12 upgrade."""
    version = VERSION_FILE.read_text().strip()
    m = re.search(
        r'^DEV_ENV_VERSION = "(\d+)"$', (TEMPLATES_DIR / name).read_text(), re.M
    )
    assert m is not None, f"{name} is missing a DEV_ENV_VERSION stamp"
    assert m.group(1) == version, (
        f"{name} stamps v{m.group(1)}, VERSION file says v{version}"
    )


@pytest.mark.parametrize(
    ("path", "pattern"),
    [
        (SKILL_MD, r"^## The standard \(v(\d+)\)"),
        (STANDARD_MD, r"^# The standard \(v(\d+)\) — full specification"),
    ],
    ids=["SKILL.md", "references/standard.md"],
)
def test_skill_doc_matches_version_stamp(path, pattern):
    """The 'The standard (vN)' headers in SKILL.md and its references/standard.md split
    both track the VERSION source of truth."""
    version = VERSION_FILE.read_text().strip()
    header = re.search(pattern, path.read_text(), re.M)
    assert header is not None, f"{path.name} is missing its 'The standard (vN)' header"
    assert header.group(1) == version


def _jscpd_dir_fragments(jscpd_json_path):
    """Dir fragments from a .jscpd.json's `**/<dir>/**` ignore entries (file-shaped
    patterns like `**/db/schema.rb` are excluded). Reads `ignore` (v12+, the key jscpd v5
    honors for paths) plus the pre-v12 `ignorePattern` for not-yet-upgraded repos."""
    data = json.loads(jscpd_json_path.read_text())
    frags = set()
    for pat in data.get("ignore", []) + data.get("ignorePattern", []):
        m = re.match(r"^\*\*/(.+)/\*\*$", pat)
        if m:
            frags.add(m.group(1))
    return frags


def test_jscpd_template_uses_ignore_key():
    """jscpd v5 honors `ignore` for path exclusion and silently ignores `ignorePattern`
    (which let CI scan vendor/bundle — the v12 fix). The template must never regress."""
    data = json.loads((TEMPLATES_DIR / ".jscpd.json").read_text())
    assert "ignore" in data
    assert "ignorePattern" not in data


def test_missing_test_fallback_matches_jscpd_template():
    """missing-test-reminder.sh reads each repo's .jscpd.json at run time, but falls back to a
    hardcoded DEFAULT_VENDOR_DIRS when a repo has none. That fallback must stay identical to the
    dirs the shipped .jscpd.json template ignores — otherwise the standard and the hook drift."""
    template_dirs = _jscpd_dir_fragments(TEMPLATES_DIR / ".jscpd.json")
    m = re.search(r"DEFAULT_VENDOR_DIRS = (\{[^}]*\})", MISSING_TEST_HOOK.read_text())
    assert m is not None, "missing-test-reminder.sh is missing DEFAULT_VENDOR_DIRS"
    hook_dirs = ast.literal_eval(m.group(1))
    assert hook_dirs == template_dirs, (
        f"hook fallback {hook_dirs} != .jscpd.json template dirs {template_dirs}"
    )

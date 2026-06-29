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

from conftest import DEV_HOOKS

TEMPLATES_DIR = DEV_HOOKS / "skills" / "dev-env-setup" / "references" / "templates"
CI_TEMPLATES = [
    "ci.python.yml",
    "ci.ruby.yml",
    "ci.shell.yml",
    "ci.js.yml",
    "ci.go.yml",
]
MISE_TEMPLATES = [
    "mise.python.toml",
    "mise.ruby.toml",
    "mise.shell.toml",
    "mise.js.toml",
    "mise.go.toml",
]
VERSION_FILE = DEV_HOOKS / "skills" / "dev-env-setup" / "VERSION"
SKILL_MD = DEV_HOOKS / "skills" / "dev-env-setup" / "SKILL.md"
STANDARD_MD = DEV_HOOKS / "skills" / "dev-env-setup" / "references" / "standard.md"
UPGRADE_GUIDE = (
    DEV_HOOKS / "skills" / "dev-env-setup" / "references" / "upgrade-guide.md"
)
MISSING_TEST_HOOK = DEV_HOOKS / "hooks" / "scripts" / "missing-test-reminder.sh"
GITLEAKS_TEMPLATE = TEMPLATES_DIR / ".gitleaks.toml"
HERB_TEMPLATE = TEMPLATES_DIR / "herb.ruby.yml"
RUBY_CI = TEMPLATES_DIR / "ci.ruby.yml"
RUBY_HK = TEMPLATES_DIR / "hk.ruby.pkl"

# Templates carrying shebang-based companion-step detectors for extensionless scripts.
SHEBANG_DETECTOR_TEMPLATES = [
    "hk.shell.pkl",
    "hk.python.pkl",
    "ci.shell.yml",
    "ci.python.yml",
    "ci.go.yml",
]

HK_TEMPLATES = [
    "hk.python.pkl",
    "hk.ruby.pkl",
    "hk.shell.pkl",
    "hk.js.pkl",
    "hk.go.pkl",
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
    # v16: mise-action is SHA-pinned with the release tag in a trailing comment.
    assert re.search(r"uses: jdx/mise-action@[0-9a-f]{40} # v", job), (
        f"{name}'s gitleaks job no longer SHA-pins jdx/mise-action with a version comment"
    )


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


@pytest.mark.parametrize("name", HK_TEMPLATES + CI_TEMPLATES)
def test_exec_bit_gate_in_every_template(name):
    """v15: every hk template carries the `exec-bit-scripts` step and every CI template
    mirrors it in the lint job, so a tracked shebang file at index mode 100644 (exit 126
    on every fresh clone / plugin install) fails before it ships. The detection must stay
    a single awk over `git ls-files -s`: hk's internal `sh` aborts on a while/read loop
    inside $(...) even when the substitution exits 0."""
    text = (TEMPLATES_DIR / name).read_text()
    assert "$1 ~ /^100644/" in text, f"{name} is missing the exec-bit awk detector"
    assert "git update-index --chmod=+x" in text, (
        f"{name}'s exec-bit gate doesn't name the fix"
    )
    if name.startswith("hk."):
        assert '["exec-bit-scripts"]' in text, (
            f"{name} is missing the exec-bit-scripts step"
        )


@pytest.mark.parametrize("name", CI_TEMPLATES)
def test_ci_actions_are_sha_pinned_with_version_comment(name):
    """v16: every remote `uses: owner/repo@ref` in a CI template pins a full 40-hex commit SHA
    with the release tag in a trailing comment (`owner/repo@<sha> # vX.Y.Z`). Tags are mutable —
    an action takeover repoints them (tj-actions, Trivy); a SHA can't be moved, and the comment
    keeps it human-readable and bumpable by pinact/check_action_refs.sh."""
    text = (TEMPLATES_DIR / name).read_text()
    uses = re.findall(r"uses:\s*([A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@\S+)(.*)", text)
    assert uses, f"{name} has no `uses:` action references"
    for ref, trailing in uses:
        sha = ref.split("@", 1)[1]
        assert re.fullmatch(r"[0-9a-f]{40}", sha), (
            f"{name} pins {ref!r} to a non-SHA ref — SHA-pin it (owner/repo@<40-hex> # vX.Y.Z)"
        )
        assert re.search(r"#\s*v[0-9]", trailing), (
            f"{name} pins {ref!r} without a `# vX.Y.Z` version comment"
        )


@pytest.mark.parametrize("name", CI_TEMPLATES)
def test_ci_template_declares_read_only_token(name):
    """v16: every CI template declares a workflow-level `permissions: { contents: read }` so the
    GITHUB_TOKEN defaults to read-only and a compromised step can't write. A job needing more
    declares its own job-level block."""
    text = (TEMPLATES_DIR / name).read_text()
    assert re.search(r"^permissions:\n  contents: read$", text, re.M), (
        f"{name} is missing a top-level read-only permissions block"
    )


@pytest.mark.parametrize("name", HK_TEMPLATES)
def test_zizmor_step_in_every_hk_template(name):
    """v18: every hk template wires the zizmor GitHub Actions security scan as the hk built-in,
    so a staged workflow/action file is statically audited at pre-commit."""
    text = (TEMPLATES_DIR / name).read_text()
    assert '["zizmor"] = Builtins.zizmor' in text, (
        f'{name} is missing the ["zizmor"] = Builtins.zizmor step'
    )


@pytest.mark.parametrize("name", MISE_TEMPLATES)
def test_zizmor_tool_in_every_mise_template(name):
    """v18: every mise template pins `zizmor` so the hk step + CI job have the binary on PATH
    (and mise.lock checksum-verifies it)."""
    text = (TEMPLATES_DIR / name).read_text()
    assert re.search(r'^zizmor = "latest"', text, re.M), (
        f"{name} does not pin the zizmor tool"
    )


@pytest.mark.parametrize("name", CI_TEMPLATES)
def test_zizmor_job_in_every_ci_template(name):
    """v18: every CI template runs zizmor in a dedicated `actions-security` job, mirroring the
    hk `zizmor` step so CI and pre-commit agree."""
    text = (TEMPLATES_DIR / name).read_text()
    assert "\n  actions-security:\n" in text, (
        f"{name} is missing the `actions-security` zizmor job"
    )
    assert "zizmor --no-progress .github/workflows/" in text, (
        f"{name}'s actions-security job doesn't run zizmor over the workflows"
    )


@pytest.mark.parametrize("name", CI_TEMPLATES)
def test_every_checkout_disables_persist_credentials(name):
    """v18: every `actions/checkout` sets `persist-credentials: false` (zizmor's `artipacked`
    finding) so the job token isn't left in `.git/config` on the runner. Counts must match —
    a new checkout without the hardening drops the persist-credentials count and fails."""
    text = (TEMPLATES_DIR / name).read_text()
    checkouts = text.count("uses: actions/checkout@")
    hardened = text.count("persist-credentials: false")
    assert checkouts > 0, f"{name} has no actions/checkout to check"
    assert hardened == checkouts, (
        f"{name} has {checkouts} checkout(s) but {hardened} persist-credentials: false "
        f"— every checkout must set it (or carry a `# zizmor: ignore[artipacked]`)"
    )


def test_shell_hk_uses_ruff_builtins():
    """v18: the shell stack swaps its hand-rolled ruff steps for the hk built-ins — there `ruff`
    is a mise tool (bare command on PATH), so `Builtins.ruff`/`Builtins.ruff_format` match exactly.
    (Stacks that run ruff via `uv run` deliberately keep custom steps — see hk.python.pkl.)"""
    text = (TEMPLATES_DIR / "hk.shell.pkl").read_text()
    assert '["ruff-check"] = Builtins.ruff' in text
    assert '["ruff-format"] = Builtins.ruff_format' in text
    # The bare hand-rolled invocation must be gone from the shell template.
    assert 'check = "ruff check --force-exclude' not in text


def test_python_hk_keeps_uv_run_ruff():
    """v18 guard: the Python stack must NOT adopt Builtins.ruff — its ruff comes from uv
    (`uv run ruff`), and the bare-command built-in would resolve a different/missing binary."""
    text = (TEMPLATES_DIR / "hk.python.pkl").read_text()
    assert "uv run ruff check --force-exclude" in text
    assert '["ruff-check"] = Builtins.ruff' not in text


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
        (SKILL_MD, r"compliant at v(\d+)"),
        (STANDARD_MD, r"^# The standard \(v(\d+)\) — full specification"),
        (STANDARD_MD, r"compliant at v(\d+)"),
        (STANDARD_MD, r'DEV_ENV_VERSION = "(\d+)"'),
    ],
    ids=[
        "SKILL.md-standard-header",
        "SKILL.md-compliant-at",
        "standard.md-standard-header",
        "standard.md-compliant-at",
        "standard.md-version-stamp",
    ],
)
def test_doc_current_version_mentions(path, pattern):
    """Every current-version mention in SKILL.md and references/standard.md tracks the
    VERSION source of truth. The header patterns stay anchored so the docs must keep a
    versioned 'The standard (vN)' header; the body patterns use findall so a stale
    mention anywhere fails. Historical mentions ('added in v6', 'the v12 fix',
    '## v10 → v11') deliberately don't match — when writing prose about a *past*
    version, phrase it that way rather than as 'compliant at vN'."""
    version = VERSION_FILE.read_text().strip()
    found = re.findall(pattern, path.read_text(), re.M)
    assert found, f"{path.name} has no match for {pattern!r}"
    stale = sorted({v for v in found if v != version})
    assert not stale, (
        f"{path.name} mentions v{', v'.join(stale)} where VERSION says v{version} "
        f"(pattern {pattern!r})"
    )


def test_upgrade_guide_reaches_current_version():
    """The upgrade guide's '## vN-1 → vN' chain must be contiguous from v1 and end at the
    VERSION source of truth, and the newest section must tell migrators to stamp exactly
    that version. Catches the classic drift: VERSION bumped without a migration section
    (or vice versa)."""
    version = int(VERSION_FILE.read_text().strip())
    text = UPGRADE_GUIDE.read_text()
    pairs = [
        (int(a), int(b)) for a, b in re.findall(r"^## v(\d+) → v(\d+) ", text, re.M)
    ]
    assert pairs, "upgrade-guide.md has no '## vN → vN' migration sections"
    assert all(b == a + 1 for a, b in pairs), f"non-adjacent migration step in {pairs}"
    assert sorted(b for _, b in pairs) == list(range(1, version + 1)), (
        f"migration sections cover targets {sorted(b for _, b in pairs)}, "
        f"expected v1..v{version} (VERSION = {version})"
    )
    newest = re.search(
        rf"^## v{version - 1} → v{version} .*?(?=^## |\Z)", text, re.M | re.S
    )
    assert newest is not None
    assert f'DEV_ENV_VERSION = "{version}"' in newest.group(0), (
        f"the v{version - 1} → v{version} section never says to stamp "
        f'DEV_ENV_VERSION = "{version}"'
    )


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


def test_herb_template_enables_linter():
    """v17: the Ruby stack ships a .herb.yml (herb ERB-linter config) with the linter on."""
    assert HERB_TEMPLATE.exists(), "templates/herb.ruby.yml is missing"
    text = HERB_TEMPLATE.read_text()
    assert re.search(r"^linter:\n\s+enabled: true$", text, re.M), (
        "herb.ruby.yml must enable the linter (`linter:` → `enabled: true`)"
    )


def test_ruby_ci_has_v17_tooling():
    """v17: ci.ruby.yml runs herb (analyze + lint) in the lint job, database_consistency in
    the test job, a dedicated security `scan` job (brakeman + bundler-audit + importmap audit),
    and fasterer in the audit job. Mirrors Rails 8's scan_ruby/scan_js plus a gem CVE check."""
    text = RUBY_CI.read_text()
    assert "herb analyze app/" in text
    assert "herb lint app/ --github" in text
    assert "\n  scan:\n" in text, "ci.ruby.yml is missing the security `scan` job"
    for needle in (
        "brakeman -q --no-pager --exit-on-warn",
        "bundle-audit check",
        "importmap audit",
        "database_consistency",
        "fasterer",
    ):
        assert needle in text, f"ci.ruby.yml is missing {needle!r}"


def test_ruby_hk_has_v17_steps():
    """v17: hk.ruby.pkl carries every new glob-gated step so the pre-commit gate matches CI."""
    text = RUBY_HK.read_text()
    for key in (
        '["herb-analyze"]',
        '["herb-lint"]',
        '["brakeman"]',
        '["bundler-audit"]',
        '["importmap-audit"]',
        '["fasterer"]',
        '["database_consistency"]',
    ):
        assert key in text, f"hk.ruby.pkl is missing the {key} step"
    # The database_consistency probe must stay loop-free — hk's internal `sh` aborts on a
    # while/read loop inside $(...). Guard against a future refactor reintroducing one.
    db_step = text.split('["database_consistency"]')[1].split("}")[0]
    assert "while" not in db_step, (
        "database_consistency step must stay loop-free (hk `sh` aborts on while/read in $())"
    )


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

"""Subprocess tests for skills/dev-env-setup/scripts/check_action_refs.sh.

The script resolves `uses: owner/repo@ref` against the remote with `git ls-remote`. To stay
offline and deterministic, the tests inject a stub resolver via DEV_HOOKS_LSREMOTE (the
documented test seam): it is called as `<cmd> <url> refs/tags/<ref> refs/heads/<ref>` and
decides by the ref name — `*missing*` → reachable-but-absent (FAIL), `*offline*` → exit 2
(unreachable → SKIP), anything else → prints a line (OK).
"""

import subprocess

from conftest import ROOT, requires_jq

SCRIPT = ROOT / "skills" / "dev-env-setup" / "scripts" / "check_action_refs.sh"

STUB = """#!/bin/bash
case "$*" in
  *offline*) exit 2 ;;
  *missing*) exit 0 ;;
  *) echo "deadbeefcafe\trefs/found" ; exit 0 ;;
esac
"""

pytestmark = requires_jq  # the suite-wide external-tool gate; bash is always present


def make_stub(tmp_path):
    stub = tmp_path / "fake_lsremote.sh"
    stub.write_text(STUB)
    stub.chmod(0o755)
    return f"bash {stub}"


def run(tmp_path, *args, env_extra=None):
    import os

    env = os.environ.copy()
    env["DEV_HOOKS_LSREMOTE"] = make_stub(tmp_path)
    if env_extra:
        env.update(env_extra)
    return subprocess.run(
        ["bash", str(SCRIPT), *args],
        cwd=str(tmp_path),
        capture_output=True,
        text=True,
        env=env,
    )


def write_workflow(tmp_path, body, name="ci.yml"):
    wf = tmp_path / name
    wf.write_text("jobs:\n  x:\n    steps:\n" + body)
    return wf


def test_all_refs_ok_exits_zero(tmp_path):
    wf = write_workflow(
        tmp_path,
        "      - uses: actions/checkout@v6\n      - uses: astral-sh/setup-uv@v8.2.0\n",
    )
    r = run(tmp_path, str(wf))
    assert r.returncode == 0
    assert "OK    actions/checkout@v6" in r.stdout
    assert "0 unresolved" in r.stdout


def test_unresolved_ref_fails(tmp_path):
    wf = write_workflow(
        tmp_path,
        "      - uses: actions/checkout@v6\n      - uses: astral-sh/setup-uv@vmissing\n",
    )
    r = run(tmp_path, str(wf))
    assert r.returncode == 1
    assert "FAIL  astral-sh/setup-uv@vmissing" in r.stdout
    assert "will break CI" in r.stdout


def test_unreachable_remote_is_skip_not_fail(tmp_path):
    wf = write_workflow(tmp_path, "      - uses: some/offline-action@v1\n")
    r = run(tmp_path, str(wf))
    assert r.returncode == 0  # network trouble must never fail the run
    assert "SKIP  some/offline-action@v1" in r.stdout


def test_commit_sha_pin_reported_not_resolved(tmp_path):
    sha = "a" * 40
    wf = write_workflow(tmp_path, f"      - uses: actions/checkout@{sha}\n")
    r = run(tmp_path, str(wf))
    assert r.returncode == 0
    assert "PIN   actions/checkout@" in r.stdout
    assert "1 pinned-sha" in r.stdout


def test_quoted_uses_value_is_checked(tmp_path):
    # YAML allows quoting the value; the ref must still be extracted (quote stripped).
    wf = write_workflow(tmp_path, '      - uses: "actions/checkout@v6"\n')
    r = run(tmp_path, str(wf))
    assert r.returncode == 0
    assert "OK    actions/checkout@v6" in r.stdout


def test_no_action_refs_is_clean(tmp_path):
    wf = write_workflow(tmp_path, "      - run: echo hi\n")
    r = run(tmp_path, str(wf))
    assert r.returncode == 0
    assert "No GitHub Actions" in r.stdout


def test_composite_action_subpath_uses_repo_root(tmp_path):
    # github/codeql-action/init@v3 → resolves against github/codeql-action.
    wf = write_workflow(tmp_path, "      - uses: github/codeql-action/init@v3\n")
    r = run(tmp_path, str(wf))
    assert r.returncode == 0
    assert "OK    github/codeql-action/init@v3" in r.stdout


def test_default_path_scans_dot_github_workflows(tmp_path):
    wfdir = tmp_path / ".github" / "workflows"
    wfdir.mkdir(parents=True)
    write_workflow(wfdir, "      - uses: actions/checkout@v6\n", name="ci.yml")
    r = run(tmp_path)  # no path arg → defaults to ./.github/workflows
    assert r.returncode == 0
    assert "OK    actions/checkout@v6" in r.stdout


def test_missing_path_arg_errors(tmp_path):
    r = run(tmp_path, str(tmp_path / "does_not_exist.yml"))
    assert r.returncode == 2
    assert "no such file" in r.stderr

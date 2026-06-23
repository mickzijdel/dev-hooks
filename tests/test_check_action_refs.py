"""Subprocess tests for plugins/dev-hooks/skills/dev-env-setup/scripts/check_action_refs.sh.

The script resolves `uses: owner/repo@ref` against the remote with `git ls-remote`. To stay
offline and deterministic, the tests inject a stub resolver via DEV_HOOKS_LSREMOTE (the
documented test seam): it is called as `<cmd> <url> refs/tags/<ref> refs/heads/<ref>` and
decides by the ref name — `*missing*` → reachable-but-absent (FAIL), `*offline*` → exit 2
(unreachable → SKIP), anything else → prints a line (OK).
"""

import subprocess

from conftest import DEV_HOOKS, requires_jq

SCRIPT = DEV_HOOKS / "skills" / "dev-env-setup" / "scripts" / "check_action_refs.sh"

STUB = """#!/bin/bash
case "$*" in
  *offline*) exit 2 ;;
  *missing*) exit 0 ;;
  *) echo "deadbeefcafe\trefs/found" ; exit 0 ;;
esac
"""

pytestmark = requires_jq  # the suite-wide external-tool gate; bash is always present


def make_stub(tmp_path, stub_text=STUB):
    stub = tmp_path / "fake_lsremote.sh"
    stub.write_text(stub_text)
    stub.chmod(0o755)
    return f"bash {stub}"


def run(tmp_path, *args, env_extra=None, stub_text=STUB):
    import os

    env = os.environ.copy()
    env["DEV_HOOKS_LSREMOTE"] = make_stub(tmp_path, stub_text)
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


# ── SHA-pin verification (the v16 standard: `owner/repo@<sha> # vX.Y.Z`) ──────────────
# A stub that resolves a comment's tag to a known commit so we can assert the pin is honest:
#   v0.0.0 → reachable but absent (tag not found)   v1.0.0 → commit 1111…   v2.0.0 → commit 2222…
SHA1 = "1" * 40
SHA2 = "2" * 40
# v3.0.0 is an *annotated* tag: ls-remote returns the tag-object line AND a peeled `^{}` commit
# line. GitHub checks out the peeled commit (SHA4), not the tag-object (SHA3).
SHA3 = "3" * 40
SHA4 = "4" * 40
STUB_SHA = (
    "#!/bin/bash\n"
    'case "$*" in\n'
    "  *offline*) exit 2 ;;\n"
    "  *v0.0.0*) exit 0 ;;\n"
    f'  *v1.0.0*) printf "{SHA1}\\trefs/tags/v1.0.0\\n" ; exit 0 ;;\n'
    f'  *v2.0.0*) printf "{SHA2}\\trefs/tags/v2.0.0\\n" ; exit 0 ;;\n'
    f'  *v3.0.0*) printf "{SHA3}\\trefs/tags/v3.0.0\\n{SHA4}\\trefs/tags/v3.0.0^{{}}\\n" ; exit 0 ;;\n'
    "  *) exit 0 ;;\n"
    "esac\n"
)


def test_sha_pin_with_matching_comment_is_verified_ok(tmp_path):
    wf = write_workflow(tmp_path, f"      - uses: actions/checkout@{SHA1} # v1.0.0\n")
    r = run(tmp_path, str(wf), stub_text=STUB_SHA)
    assert r.returncode == 0, r.stdout
    assert (
        f"OK    actions/checkout@{SHA1} # v1.0.0  (SHA matches tag v1.0.0)" in r.stdout
    )
    assert "0 unresolved" in r.stdout


def test_sha_pin_with_wrong_sha_fails(tmp_path):
    # Pin claims v2.0.0 but the SHA is SHA1, while v2.0.0 actually resolves to SHA2.
    wf = write_workflow(tmp_path, f"      - uses: actions/checkout@{SHA1} # v2.0.0\n")
    r = run(tmp_path, str(wf), stub_text=STUB_SHA)
    assert r.returncode == 1, r.stdout
    assert "pinned SHA is not tag v2.0.0" in r.stdout


def test_sha_pin_with_missing_tag_comment_fails(tmp_path):
    wf = write_workflow(tmp_path, f"      - uses: actions/checkout@{SHA1} # v0.0.0\n")
    r = run(tmp_path, str(wf), stub_text=STUB_SHA)
    assert r.returncode == 1, r.stdout
    assert "tag v0.0.0 does not exist" in r.stdout


def test_sha_pin_without_comment_is_pin_not_verified(tmp_path):
    wf = write_workflow(tmp_path, f"      - uses: actions/checkout@{SHA1}\n")
    r = run(tmp_path, str(wf), stub_text=STUB_SHA)
    assert r.returncode == 0, r.stdout
    assert "PIN   actions/checkout@" in r.stdout
    assert "1 pinned-sha" in r.stdout


def test_sha_pin_annotated_tag_matches_peeled_commit(tmp_path):
    # The pin equals the peeled commit (what GitHub checks out) → OK.
    wf = write_workflow(tmp_path, f"      - uses: actions/checkout@{SHA4} # v3.0.0\n")
    r = run(tmp_path, str(wf), stub_text=STUB_SHA)
    assert r.returncode == 0, r.stdout
    assert "OK    actions/checkout@" in r.stdout


def test_sha_pin_annotated_tag_object_sha_fails(tmp_path):
    # Pinning the annotated tag's OBJECT sha (not the peeled commit) must FAIL — GitHub resolves
    # the tag to the peeled commit, so such a pin looks valid here but breaks CI at checkout.
    wf = write_workflow(tmp_path, f"      - uses: actions/checkout@{SHA3} # v3.0.0\n")
    r = run(tmp_path, str(wf), stub_text=STUB_SHA)
    assert r.returncode == 1, r.stdout
    assert "pinned SHA is not tag v3.0.0" in r.stdout

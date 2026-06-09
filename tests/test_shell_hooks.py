"""Subprocess tests for the bundled shell hooks.

Each hook is run as `bash hooks/scripts/<name>.sh` with a crafted stdin payload / cwd /
environment, asserting on exit code and that stdout is empty (silent) or valid JSON. Both
the silent-gate path and the firing path are exercised for every hook.
"""

import json
import os
import subprocess
import time

from conftest import HOOKS, ROOT, init_git_repo, make_transcript, requires_jq

pytestmark = requires_jq


def base_env(**overrides):
    env = os.environ.copy()
    for key, value in overrides.items():
        if value is None:
            env.pop(key, None)
        else:
            env[key] = value
    return env


def run_hook(name, *, stdin="", cwd=None, env=None):
    return subprocess.run(
        ["bash", str(HOOKS / name)],
        input=stdin,
        cwd=str(cwd) if cwd else None,
        env=env,
        capture_output=True,
        text=True,
    )


def assert_json_with(stdout, needle):
    payload = json.loads(stdout)
    assert needle in json.dumps(payload)
    return payload


# ── detect-stack-skills.sh ──────────────────────────────────────────────────────────
def test_detect_stack_fires_for_python(tmp_path):
    (tmp_path / "pyproject.toml").write_text("[project]\nname='x'\n")
    r = run_hook("detect-stack-skills.sh", stdin=json.dumps({"cwd": str(tmp_path)}))
    assert r.returncode == 0
    assert_json_with(r.stdout, "Python")


def test_detect_stack_silent_when_unrecognized(tmp_path):
    r = run_hook("detect-stack-skills.sh", stdin=json.dumps({"cwd": str(tmp_path)}))
    assert r.returncode == 0
    assert r.stdout.strip() == ""


# ── dev-env-reminder.sh ─────────────────────────────────────────────────────────────
def test_dev_env_reminder_silent_outside_git(tmp_path):
    r = run_hook("dev-env-reminder.sh", stdin=json.dumps({"cwd": str(tmp_path)}))
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_dev_env_reminder_silent_when_opted_out(tmp_path):
    init_git_repo(tmp_path)
    r = run_hook(
        "dev-env-reminder.sh",
        stdin=json.dumps({"cwd": str(tmp_path)}),
        env=base_env(DEV_HOOKS_DEVENV_OWNED="false"),
    )
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_dev_env_reminder_fires_on_needs_setup(tmp_path):
    init_git_repo(tmp_path)
    (tmp_path / "foo.sh").write_text("#!/bin/bash\necho hi\n")  # makes it applicable
    r = run_hook(
        "dev-env-reminder.sh",
        stdin=json.dumps({"cwd": str(tmp_path)}),
        env=base_env(DEV_HOOKS_DEVENV_OWNED="true", CLAUDE_PLUGIN_ROOT=str(ROOT)),
    )
    assert r.returncode == 0
    assert_json_with(r.stdout, "[dev-env]")


# ── dev_env_check.sh (skill checker) ────────────────────────────────────────────────
CHECKER = ROOT / "skills" / "dev-env-setup" / "scripts" / "dev_env_check.sh"


def run_checker(target):
    r = subprocess.run(
        ["bash", str(CHECKER), str(target)],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr
    out = {}
    for line in r.stdout.splitlines():
        if "=" in line and not line.startswith("# "):
            key, _, value = line.partition("=")
            out[key] = value
    return out


def make_v3_compliant_repo(path, *, readme=True, claude=True):
    """Build a repo that satisfies everything the checker enforces at v3 except
    optionally the README/CLAUDE.md docs."""
    (path / "pyproject.toml").write_text("[project]\nname='x'\n")  # python stack
    (path / "mise.toml").write_text(
        '[settings]\nlockfile = true\n[env]\nDEV_ENV_VERSION = "3"\n'
    )
    (path / "mise.lock").write_text("")
    (path / "hk.pkl").write_text('["gitleaks"] = Builtins.gitleaks\n')
    wf = path / ".github" / "workflows"
    wf.mkdir(parents=True)
    (wf / "ci.yml").write_text("name: ci\non: push\n")
    if readme:
        (path / "README.md").write_text("# x\n")
    if claude:
        (path / "CLAUDE.md").write_text("# project instructions\n")


def test_checker_v3_compliant_with_docs(tmp_path):
    make_v3_compliant_repo(tmp_path)
    out = run_checker(tmp_path)
    assert out["has_readme"] == "1"
    assert out["has_claude"] == "1"
    assert out["status"] == "compliant"


def test_checker_v3_needs_upgrade_without_readme(tmp_path):
    make_v3_compliant_repo(tmp_path, readme=False)
    out = run_checker(tmp_path)
    assert out["has_readme"] == "0"
    assert out["status"] == "needs-upgrade"


def test_checker_v3_needs_upgrade_without_claude(tmp_path):
    make_v3_compliant_repo(tmp_path, claude=False)
    out = run_checker(tmp_path)
    assert out["has_claude"] == "0"
    assert out["status"] == "needs-upgrade"


# ── latest-deps-reminder.sh ─────────────────────────────────────────────────────────
def test_latest_deps_fires_once_per_session(tmp_path):
    env = base_env(TMPDIR=str(tmp_path), DEV_HOOKS_LATEST_DEPS=None)
    payload = json.dumps(
        {
            "tool_input": {"file_path": str(tmp_path / "pyproject.toml")},
            "session_id": "s1",
        }
    )
    first = run_hook("latest-deps-reminder.sh", stdin=payload, env=env)
    assert first.returncode == 0
    assert_json_with(first.stdout, "stale")
    # Manifest edits also nudge keeping the human-facing docs in sync.
    assert_json_with(first.stdout, "README.md")
    assert_json_with(first.stdout, "CLAUDE.md")
    # Marker now exists → second call for same session+category stays silent.
    second = run_hook("latest-deps-reminder.sh", stdin=payload, env=env)
    assert second.returncode == 0
    assert second.stdout.strip() == ""


def test_latest_deps_gemfile_nudges_docs(tmp_path):
    env = base_env(TMPDIR=str(tmp_path), DEV_HOOKS_LATEST_DEPS=None)
    payload = json.dumps(
        {"tool_input": {"file_path": str(tmp_path / "Gemfile")}, "session_id": "g1"}
    )
    r = run_hook("latest-deps-reminder.sh", stdin=payload, env=env)
    assert r.returncode == 0
    assert_json_with(r.stdout, "README.md")
    assert_json_with(r.stdout, "CLAUDE.md")


def test_latest_deps_lockfile_omits_docs_nudge(tmp_path):
    env = base_env(TMPDIR=str(tmp_path), DEV_HOOKS_LATEST_DEPS=None)
    payload = json.dumps(
        {"tool_input": {"file_path": str(tmp_path / "uv.lock")}, "session_id": "l1"}
    )
    r = run_hook("latest-deps-reminder.sh", stdin=payload, env=env)
    assert r.returncode == 0
    # Lockfiles are regenerated, not where versions are authored → no docs trailer.
    assert "README.md" not in r.stdout
    assert "Regenerate" in r.stdout or "regenerate" in r.stdout


def test_latest_deps_silent_for_non_manifest(tmp_path):
    env = base_env(TMPDIR=str(tmp_path), DEV_HOOKS_LATEST_DEPS=None)
    payload = json.dumps(
        {"tool_input": {"file_path": str(tmp_path / "README.md")}, "session_id": "s2"}
    )
    r = run_hook("latest-deps-reminder.sh", stdin=payload, env=env)
    assert r.returncode == 0
    assert r.stdout.strip() == ""


# ── dockerfile-reminder.sh (also exercises lib/reminder-common.sh) ───────────────────
def test_dockerfile_reminder_fires_for_dockerfile(tmp_path):
    dockerfile = tmp_path / "Dockerfile"
    dockerfile.write_text("FROM alpine:3.20\nRUN echo hi\n")
    payload = json.dumps(
        {"tool_input": {"file_path": str(dockerfile)}, "session_id": "d1"}
    )
    r = run_hook(
        "dockerfile-reminder.sh", stdin=payload, env=base_env(TMPDIR=str(tmp_path))
    )
    assert r.returncode == 0
    assert_json_with(r.stdout, "Order instructions")


def test_dockerfile_reminder_silent_for_non_dockerfile(tmp_path):
    payload = json.dumps(
        {"tool_input": {"file_path": str(tmp_path / "app.py")}, "session_id": "d2"}
    )
    r = run_hook(
        "dockerfile-reminder.sh", stdin=payload, env=base_env(TMPDIR=str(tmp_path))
    )
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_dockerfile_reminder_silent_when_opted_out(tmp_path):
    payload = json.dumps(
        {"tool_input": {"file_path": str(tmp_path / "Dockerfile")}, "session_id": "d3"}
    )
    r = run_hook(
        "dockerfile-reminder.sh",
        stdin=payload,
        env=base_env(TMPDIR=str(tmp_path), DEV_HOOKS_DOCKERFILE="false"),
    )
    assert r.returncode == 0
    assert r.stdout.strip() == ""


# ── lint-on-edit.sh ─────────────────────────────────────────────────────────────────
def test_lint_on_edit_silent_without_file_path():
    r = run_hook("lint-on-edit.sh", stdin=json.dumps({}))
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_lint_on_edit_exits_zero_for_python_file(tmp_path):
    py = tmp_path / "snippet.py"
    py.write_text("x = 1\n")
    r = run_hook(
        "lint-on-edit.sh", stdin=json.dumps({"tool_input": {"file_path": str(py)}})
    )
    assert r.returncode == 0
    assert r.stdout.strip() == ""


# ── memory-reminder.sh ──────────────────────────────────────────────────────────────
MEMORY_SENTINEL = "[memory-reminder] session learnings not yet captured this session"


def test_memory_reminder_silent_when_not_in_use(tmp_path):
    # HOME with no projects/*/memory dir and no opt-in → gate 1 fails.
    home = tmp_path / "home"
    home.mkdir()
    r = run_hook(
        "memory-reminder.sh",
        stdin=json.dumps({"transcript_path": "/nope"}),
        env=base_env(HOME=str(home), DEV_HOOKS_MEMORY=None),
    )
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_memory_reminder_fires_on_substantial_session(tmp_path):
    transcript = make_transcript(tmp_path / "t.jsonl", human_turns=6)
    r = run_hook(
        "memory-reminder.sh",
        stdin=json.dumps({"transcript_path": str(transcript)}),
        env=base_env(DEV_HOOKS_MEMORY="1"),
    )
    assert r.returncode == 2
    assert_json_with(r.stdout, "[memory-reminder]")


def test_memory_reminder_skips_when_already_prompted(tmp_path):
    transcript = make_transcript(
        tmp_path / "t.jsonl", human_turns=6, extra_lines=[MEMORY_SENTINEL]
    )
    r = run_hook(
        "memory-reminder.sh",
        stdin=json.dumps({"transcript_path": str(transcript)}),
        env=base_env(DEV_HOOKS_MEMORY="1"),
    )
    assert r.returncode == 0
    assert r.stdout.strip() == ""


# ── plan-reminder.sh ────────────────────────────────────────────────────────────────
def test_plan_reminder_silent_without_plan(tmp_path):
    r = run_hook("plan-reminder.sh", cwd=tmp_path)
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_plan_reminder_fires_for_stale_plan(tmp_path):
    plan = tmp_path / ".claude" / "current_plan.md"
    plan.parent.mkdir()
    plan.write_text("# plan\n")
    old = time.time() - 200  # > 120s threshold
    os.utime(plan, (old, old))
    r = run_hook("plan-reminder.sh", cwd=tmp_path)
    assert r.returncode == 0
    assert "REMINDER:" in r.stdout


# ── review-reminder.sh ──────────────────────────────────────────────────────────────
def test_review_reminder_silent_outside_git(tmp_path):
    r = run_hook("review-reminder.sh", cwd=tmp_path, stdin=json.dumps({}))
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_review_reminder_fires_on_unreviewed_code(tmp_path):
    init_git_repo(tmp_path)
    (tmp_path / "changed.py").write_text("x = 1\n")  # untracked code change
    transcript = make_transcript(tmp_path / "t.jsonl", human_turns=2)
    r = run_hook(
        "review-reminder.sh",
        cwd=tmp_path,
        stdin=json.dumps({"transcript_path": str(transcript)}),
    )
    assert r.returncode == 2
    assert_json_with(r.stdout, "[review-reminder]")


def test_review_reminder_silent_after_review(tmp_path):
    init_git_repo(tmp_path)
    (tmp_path / "changed.py").write_text("x = 1\n")
    review_line = json.dumps(
        {
            "message": {
                "content": [{"type": "tool_use", "input": {"skill": "code-review"}}]
            }
        }
    )
    transcript = make_transcript(
        tmp_path / "t.jsonl", human_turns=2, extra_lines=[review_line]
    )
    r = run_hook(
        "review-reminder.sh",
        cwd=tmp_path,
        stdin=json.dumps({"transcript_path": str(transcript)}),
    )
    assert r.returncode == 0
    assert r.stdout.strip() == ""


# ── verify-work.sh ──────────────────────────────────────────────────────────────────
def test_verify_work_silent_outside_git(tmp_path):
    r = run_hook("verify-work.sh", cwd=tmp_path)
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_verify_work_silent_when_no_code_changed(tmp_path):
    init_git_repo(tmp_path)
    (tmp_path / "notes.txt").write_text("hello\n")  # not a code file
    r = run_hook("verify-work.sh", cwd=tmp_path)
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_verify_work_fires_when_no_tools_detected(tmp_path):
    init_git_repo(tmp_path)
    (tmp_path / "changed.py").write_text("x = 1\n")  # code changed, no test/lint config
    r = run_hook("verify-work.sh", cwd=tmp_path)
    assert r.returncode == 2
    assert_json_with(r.stdout, "No test suite")


# ── debug-leftover-reminder.sh ──────────────────────────────────────────────────────
DEBUG_SENTINEL = "[debug-leftover] new debug statements detected this session"


def test_debug_leftover_fires_on_new_debug_lines(tmp_path):
    init_git_repo(tmp_path)
    (tmp_path / "foo.py").write_text("def f():\n    breakpoint()\n    return 1\n")
    (tmp_path / "bar.rb").write_text("def g\n  p x\nend\n")  # untracked code
    r = run_hook(
        "debug-leftover-reminder.sh",
        cwd=tmp_path,
        stdin=json.dumps({"transcript_path": "/nope"}),
    )
    assert r.returncode == 2
    payload = assert_json_with(r.stdout, "[debug-leftover]")
    body = json.dumps(payload)
    assert "foo.py" in body and "bar.rb" in body


def test_debug_leftover_silent_for_preexisting_committed(tmp_path):
    run = init_git_repo(tmp_path)
    (tmp_path / "foo.py").write_text("def f():\n    breakpoint()\n")
    run("add", "foo.py")
    run("commit", "-q", "-m", "add foo")
    # No new changes → the committed breakpoint() is pre-existing and ignored.
    r = run_hook(
        "debug-leftover-reminder.sh",
        cwd=tmp_path,
        stdin=json.dumps({"transcript_path": "/nope"}),
    )
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_debug_leftover_silent_when_opted_out(tmp_path):
    init_git_repo(tmp_path)
    (tmp_path / "foo.py").write_text("breakpoint()\n")
    r = run_hook(
        "debug-leftover-reminder.sh",
        cwd=tmp_path,
        stdin=json.dumps({"transcript_path": "/nope"}),
        env=base_env(DEV_HOOKS_DEBUG_LEFTOVER="false"),
    )
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_debug_leftover_silent_when_already_prompted(tmp_path):
    init_git_repo(tmp_path)
    (tmp_path / "foo.py").write_text("breakpoint()\n")
    transcript = make_transcript(
        tmp_path / "t.jsonl", human_turns=1, extra_lines=[DEBUG_SENTINEL]
    )
    r = run_hook(
        "debug-leftover-reminder.sh",
        cwd=tmp_path,
        stdin=json.dumps({"transcript_path": str(transcript)}),
    )
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_debug_leftover_ignores_test_files(tmp_path):
    init_git_repo(tmp_path)
    (tmp_path / "test_foo.py").write_text("breakpoint()\n")  # a test file
    r = run_hook(
        "debug-leftover-reminder.sh",
        cwd=tmp_path,
        stdin=json.dumps({"transcript_path": "/nope"}),
    )
    assert r.returncode == 0
    assert r.stdout.strip() == ""


# ── secret-plaintext-reminder.sh ────────────────────────────────────────────────────
def test_secret_plaintext_fires_once_per_session(tmp_path):
    env = base_env(TMPDIR=str(tmp_path), DEV_HOOKS_SECRETS=None)
    payload = json.dumps(
        {
            "tool_input": {
                "file_path": str(tmp_path / ".env"),
                "content": 'API_KEY="testtesttest"\n',  # deliberately low-entropy fake
            },
            "session_id": "s1",
        }
    )
    first = run_hook("secret-plaintext-reminder.sh", stdin=payload, env=env)
    assert first.returncode == 0
    assert_json_with(first.stdout, "env-to-fnox")
    # Marker now exists → second call for the same session stays silent.
    second = run_hook("secret-plaintext-reminder.sh", stdin=payload, env=env)
    assert second.returncode == 0
    assert second.stdout.strip() == ""


def test_secret_plaintext_silent_for_env_reference(tmp_path):
    env = base_env(TMPDIR=str(tmp_path), DEV_HOOKS_SECRETS=None)
    payload = json.dumps(
        {
            "tool_input": {
                "file_path": str(tmp_path / "config.js"),
                "content": "const API_KEY = process.env.API_KEY;\n",
            },
            "session_id": "s2",
        }
    )
    r = run_hook("secret-plaintext-reminder.sh", stdin=payload, env=env)
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_secret_plaintext_silent_for_placeholder(tmp_path):
    env = base_env(TMPDIR=str(tmp_path), DEV_HOOKS_SECRETS=None)
    payload = json.dumps(
        {
            "tool_input": {
                "file_path": str(tmp_path / ".env"),
                "content": 'API_KEY="your-key-here"\n',
            },
            "session_id": "s3",
        }
    )
    r = run_hook("secret-plaintext-reminder.sh", stdin=payload, env=env)
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_secret_plaintext_silent_for_example_file(tmp_path):
    env = base_env(TMPDIR=str(tmp_path), DEV_HOOKS_SECRETS=None)
    payload = json.dumps(
        {
            "tool_input": {
                "file_path": str(tmp_path / ".env.example"),
                "content": 'API_KEY="testtesttest"\n',  # deliberately low-entropy fake
            },
            "session_id": "s4",
        }
    )
    r = run_hook("secret-plaintext-reminder.sh", stdin=payload, env=env)
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_secret_plaintext_silent_when_opted_out(tmp_path):
    payload = json.dumps(
        {
            "tool_input": {
                "file_path": str(tmp_path / ".env"),
                "content": 'API_KEY="testtesttest"\n',  # deliberately low-entropy fake
            },
            "session_id": "s5",
        }
    )
    r = run_hook(
        "secret-plaintext-reminder.sh",
        stdin=payload,
        env=base_env(TMPDIR=str(tmp_path), DEV_HOOKS_SECRETS="false"),
    )
    assert r.returncode == 0
    assert r.stdout.strip() == ""


# ── missing-test-reminder.sh ────────────────────────────────────────────────────────
MISSING_TEST_SENTINEL = "[missing-test] new source files without tests this session"


def test_missing_test_fires_for_untested_new_file(tmp_path):
    init_git_repo(tmp_path)
    (tmp_path / "foo.py").write_text("def f():\n    return 1\n")  # new, no test
    r = run_hook(
        "missing-test-reminder.sh",
        cwd=tmp_path,
        stdin=json.dumps({"transcript_path": "/nope"}),
    )
    assert r.returncode == 2
    assert_json_with(r.stdout, "[missing-test]")


def test_missing_test_silent_when_test_present(tmp_path):
    init_git_repo(tmp_path)
    (tmp_path / "foo.py").write_text("def f():\n    return 1\n")
    (tmp_path / "test_foo.py").write_text("def test_f():\n    assert True\n")
    r = run_hook(
        "missing-test-reminder.sh",
        cwd=tmp_path,
        stdin=json.dumps({"transcript_path": "/nope"}),
    )
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_missing_test_silent_when_opted_out(tmp_path):
    init_git_repo(tmp_path)
    (tmp_path / "foo.py").write_text("def f():\n    return 1\n")
    r = run_hook(
        "missing-test-reminder.sh",
        cwd=tmp_path,
        stdin=json.dumps({"transcript_path": "/nope"}),
        env=base_env(DEV_HOOKS_MISSING_TEST="false"),
    )
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_missing_test_silent_when_already_prompted(tmp_path):
    init_git_repo(tmp_path)
    (tmp_path / "foo.py").write_text("def f():\n    return 1\n")
    transcript = make_transcript(
        tmp_path / "t.jsonl", human_turns=1, extra_lines=[MISSING_TEST_SENTINEL]
    )
    r = run_hook(
        "missing-test-reminder.sh",
        cwd=tmp_path,
        stdin=json.dumps({"transcript_path": str(transcript)}),
    )
    assert r.returncode == 0
    assert r.stdout.strip() == ""


# ── ci-action-ref-reminder.sh (reminder-only; never hits the network) ────────────────
def _workflow(tmp_path, name="ci.yml", body="      - uses: astral-sh/setup-uv@v8\n"):
    wf = tmp_path / name
    wf.write_text("jobs:\n  x:\n    steps:\n" + body)
    return wf


def test_ci_action_ref_fires_for_workflow(tmp_path):
    wf = _workflow(tmp_path)
    payload = json.dumps({"tool_input": {"file_path": str(wf)}, "session_id": "c1"})
    r = run_hook(
        "ci-action-ref-reminder.sh", stdin=payload, env=base_env(TMPDIR=str(tmp_path))
    )
    assert r.returncode == 0
    # Points Claude at the bundled checker, not a network call by the hook itself.
    assert_json_with(r.stdout, "check_action_refs.sh")


def test_ci_action_ref_silent_for_yaml_without_uses(tmp_path):
    plain = tmp_path / "config.yml"
    plain.write_text("a: 1\nb: 2\n")
    payload = json.dumps({"tool_input": {"file_path": str(plain)}, "session_id": "c2"})
    r = run_hook(
        "ci-action-ref-reminder.sh", stdin=payload, env=base_env(TMPDIR=str(tmp_path))
    )
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_ci_action_ref_silent_for_non_yaml(tmp_path):
    other = tmp_path / "notes.txt"
    other.write_text("uses: astral-sh/setup-uv@v8\n")  # not a .yml/.yaml file
    payload = json.dumps({"tool_input": {"file_path": str(other)}, "session_id": "c3"})
    r = run_hook(
        "ci-action-ref-reminder.sh", stdin=payload, env=base_env(TMPDIR=str(tmp_path))
    )
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_ci_action_ref_silent_when_opted_out(tmp_path):
    wf = _workflow(tmp_path)
    payload = json.dumps({"tool_input": {"file_path": str(wf)}, "session_id": "c4"})
    r = run_hook(
        "ci-action-ref-reminder.sh",
        stdin=payload,
        env=base_env(TMPDIR=str(tmp_path), DEV_HOOKS_CI_ACTION_REFS="false"),
    )
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_ci_action_ref_fires_once_per_session(tmp_path):
    wf = _workflow(tmp_path)
    payload = json.dumps({"tool_input": {"file_path": str(wf)}, "session_id": "c5"})
    env = base_env(TMPDIR=str(tmp_path))
    first = run_hook("ci-action-ref-reminder.sh", stdin=payload, env=env)
    second = run_hook("ci-action-ref-reminder.sh", stdin=payload, env=env)
    assert_json_with(first.stdout, "check_action_refs.sh")
    assert second.stdout.strip() == ""

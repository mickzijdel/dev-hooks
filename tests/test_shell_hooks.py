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
    # Marker now exists → second call for same session+category stays silent.
    second = run_hook("latest-deps-reminder.sh", stdin=payload, env=env)
    assert second.returncode == 0
    assert second.stdout.strip() == ""


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

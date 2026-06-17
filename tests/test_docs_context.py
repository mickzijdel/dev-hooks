"""Tests for docs-context.sh (SessionStart hook)."""

import json
import os
import subprocess

import pytest

from conftest import HOOKS, requires_jq

pytestmark = requires_jq


def base_env(**overrides):
    env = os.environ.copy()
    for key, value in overrides.items():
        if value is None:
            env.pop(key, None)
        else:
            env[key] = value
    return env


def run_docs_context(cwd, **env_overrides):
    return subprocess.run(
        ["bash", str(HOOKS / "docs-context.sh")],
        input=json.dumps({"cwd": str(cwd)}),
        capture_output=True,
        text=True,
        env=base_env(**env_overrides),
    )


def test_docs_context_fires_with_docs_dir(tmp_path):
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "getting-started.md").write_text("# Getting Started\n\nContent here.\n")
    r = run_docs_context(tmp_path)
    assert r.returncode == 0
    payload = json.loads(r.stdout)
    ctx = payload["hookSpecificOutput"]["additionalContext"]
    assert "docs/" in ctx
    assert "Getting Started" in ctx


def test_docs_context_silent_when_no_docs_dir(tmp_path):
    r = run_docs_context(tmp_path)
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_docs_context_silent_when_docs_dir_empty(tmp_path):
    (tmp_path / "docs").mkdir()
    r = run_docs_context(tmp_path)
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_docs_context_uses_doc_dir(tmp_path):
    doc = tmp_path / "doc"
    doc.mkdir()
    (doc / "readme.md").write_text("# Overview\n")
    r = run_docs_context(tmp_path)
    assert r.returncode == 0
    assert "doc/" in json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"]


def test_docs_context_uses_yaml_frontmatter_title(tmp_path):
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "api.md").write_text('---\ntitle: "API Reference"\n---\n\n# Something Else\n')
    r = run_docs_context(tmp_path)
    ctx = json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"]
    assert "API Reference" in ctx
    assert "Something Else" not in ctx


def test_docs_context_uses_heading_when_no_frontmatter(tmp_path):
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "guide.md").write_text("# Setup Guide\n\nContent.\n")
    r = run_docs_context(tmp_path)
    ctx = json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"]
    assert "Setup Guide" in ctx


def test_docs_context_falls_back_to_filename(tmp_path):
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "overview.md").write_text("No heading here, just prose.\n")
    r = run_docs_context(tmp_path)
    ctx = json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"]
    assert "overview" in ctx


def test_docs_context_includes_description(tmp_path):
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "deploy.md").write_text(
        "---\ntitle: Deployment\ndescription: How to deploy to production\n---\n"
    )
    r = run_docs_context(tmp_path)
    ctx = json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"]
    assert "How to deploy to production" in ctx


def test_docs_context_opt_out(tmp_path):
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "guide.md").write_text("# Guide\n")
    r = run_docs_context(tmp_path, DEV_HOOKS_DOCS_CONTEXT="false")
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_docs_context_caps_at_30_files(tmp_path):
    docs = tmp_path / "docs"
    docs.mkdir()
    for i in range(35):
        (docs / f"page-{i:02d}.md").write_text(f"# Page {i}\n")
    r = run_docs_context(tmp_path)
    assert r.returncode == 0
    ctx = json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"]
    # Exactly 30 entries listed, 5 remainder noted
    assert ctx.count("  - ") == 30
    assert "5 more files not shown" in ctx


def test_docs_context_no_truncation_note_at_exactly_30(tmp_path):
    docs = tmp_path / "docs"
    docs.mkdir()
    for i in range(30):
        (docs / f"page-{i:02d}.md").write_text(f"# Page {i}\n")
    r = run_docs_context(tmp_path)
    assert r.returncode == 0
    ctx = json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"]
    assert "more files not shown" not in ctx
    assert ctx.count("  - ") == 30

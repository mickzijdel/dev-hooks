"""Behaviour of the v23 version-sync gate (templates/check_version_sync.sh).

The script is copied verbatim into every standard-tracking repo and run by both the hk
`versions` step and CI's `versions` job, so it is exercised here as a subprocess against
throwaway repos rather than by reading its source. Two properties matter most and are the
ones a template edit can silently break:

* it **fails** — naming the file and both values — when two pins disagree, and
* it **degrades** on absence: a repo with no Dockerfile / no compose file exits 0 and says
  what it skipped, instead of erroring or silently appearing to have checked.
"""

import subprocess
import textwrap

import pytest

from conftest import DEV_HOOKS

SCRIPT = (
    DEV_HOOKS
    / "skills"
    / "dev-env-setup"
    / "references"
    / "templates"
    / "check_version_sync.sh"
)


def build(path, files):
    """Write `files` ({relative path: content}) into `path` and install the script at
    scripts/check_version_sync.sh, where every repo carries it (the script resolves the
    repo root as its own parent's parent)."""
    for name, content in files.items():
        target = path / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(textwrap.dedent(content).lstrip("\n"))
    scripts = path / "scripts"
    scripts.mkdir(exist_ok=True)
    (scripts / "check_version_sync.sh").write_text(SCRIPT.read_text())
    return scripts / "check_version_sync.sh"


def run(path, files):
    script = build(path, files)
    return subprocess.run(
        ["bash", str(script)], capture_output=True, text=True, cwd=path
    )


RUBY_REPO = {
    ".ruby-version": "ruby-3.4.10\n",
    ".node-version": "22.4.1\n",
    "mise.toml": """
        [tools]
        ruby = "3.4.10"
        node = "22.4.1"
        yarn = "1.22.19"
        hk = "latest"
    """,
    "Dockerfile": """
        ARG RUBY_VERSION=3.4.10
        FROM ruby:$RUBY_VERSION
        ARG NODE_VERSION=22.4.1
        ARG YARN_VERSION=1.22.19
    """,
    "docker-compose.yml": """
        services:
          db:
            image: "mysql:8.4"
          cache:
            image: redis:7.4
    """,
    ".github/workflows/ci.yml": """
        jobs:
          test:
            services:
              db:
                image: mysql:8.4@sha256:deadbeef
    """,
}


def test_agreeing_pins_pass_and_say_what_they_verified(tmp_path):
    """A repo whose pins all agree exits 0 — and prints a ✓ line per comparison, because a
    gate that says nothing when it passes teaches nobody what it covers."""
    r = run(tmp_path, RUBY_REPO)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "✓ ruby 3.4.10" in r.stdout
    assert "✓ node 22.4.1" in r.stdout
    assert "✓ yarn 1.22.19" in r.stdout
    # The image digest in ci.yml must be stripped before comparing, or nothing ever matches.
    assert "✓ mysql 8.4" in r.stdout


def test_ruby_version_prefix_is_normalised(tmp_path):
    """`.ruby-version` may be bare (3.4.10) or prefixed (ruby-3.4.10) and `.node-version` may
    carry a leading v; both spellings are valid for setup-* and mise, so neither may false-fail.
    RUBY_REPO already uses the prefixed form — assert the bare form behaves identically."""
    files = dict(
        RUBY_REPO, **{".ruby-version": "3.4.10\n", ".node-version": "v22.4.1\n"}
    )
    r = run(tmp_path, files)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "✓ ruby 3.4.10" in r.stdout and "✓ node 22.4.1" in r.stdout


def test_stale_dockerfile_arg_fails_and_names_the_file(tmp_path):
    """The negative test the upgrade guide insists on: break one pin and the gate must fail,
    naming the offending file and both values — not just exit non-zero."""
    files = dict(
        RUBY_REPO,
        Dockerfile="ARG RUBY_VERSION=3.3.3\nARG NODE_VERSION=22.4.1\nARG YARN_VERSION=1.22.19\n",
    )
    r = run(tmp_path, files)
    assert r.returncode == 1
    assert "✗ Dockerfile ARG RUBY_VERSION (3.3.3) != .ruby-version (3.4.10)" in r.stdout
    # The pins that still agree keep reporting, so one failure doesn't hide the rest.
    assert "✓ node 22.4.1" in r.stdout


def test_service_tag_drift_between_prod_and_ci_fails(tmp_path):
    """The drift that motivated the gate: CI green against a database server nobody deploys."""
    files = dict(
        RUBY_REPO,
        **{
            "docker-compose.yml": 'services:\n  db:\n    image: "mysql:8.3"\n',
        },
    )
    r = run(tmp_path, files)
    assert r.returncode == 1
    assert "✗ mysql tags disagree" in r.stdout
    assert "docker-compose.yml (8.3)" in r.stdout
    assert ".github/workflows/ci.yml (8.4)" in r.stdout


def test_service_in_only_one_file_is_reported_not_failed(tmp_path):
    """An image named in one file alone is not drift — CI may legitimately not need Redis."""
    r = run(tmp_path, RUBY_REPO)
    assert r.returncode == 0
    assert "- redis: pinned only in docker-compose.yml (7.4)" in r.stdout


def test_absent_files_are_skipped_out_loud(tmp_path):
    """A JS repo with no Dockerfile and no compose file must exit 0 — and must say so, so its
    pass never looks like more coverage than it is."""
    r = run(
        tmp_path,
        {
            ".node-version": "22.4.1\n",
            "mise.toml": '[tools]\nnode = "22.4.1"\n',
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "- no Dockerfile, so no image-build ARGs to cross-check" in r.stdout
    assert "- no compose / deploy / workflow files, nothing to cross-check" in r.stdout
    assert "✓ node 22.4.1" in r.stdout


def test_empty_repo_passes(tmp_path):
    """Nothing to check at all is a pass, not a crash."""
    r = run(tmp_path, {})
    assert r.returncode == 0, r.stdout + r.stderr
    assert "- no mise.toml" in r.stdout


def test_floating_mise_spec_is_not_compared(tmp_path):
    """`node = "latest"` names no fixed version (mise.lock is its real pin), so it must be
    reported as skipped rather than diffed against .node-version."""
    r = run(
        tmp_path,
        {
            ".node-version": "22.4.1\n",
            "mise.toml": '[tools]\nnode = "latest"\n',
            "Dockerfile": "ARG NODE_VERSION=22.4.1\n",
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert 'mise.toml spec is "latest"' in r.stdout
    assert "✓ node 22.4.1" in r.stdout


def test_mise_table_form_and_multi_manifest_repo(tmp_path):
    """The Kamal shape: `ruby = { version = … }` in mise.toml, a config/deploy.yml plus a
    devcontainer compose, no ARG NODE_VERSION at all. Every one of those must work, because
    forcing a Dockerfile style on adopters is explicitly out of scope."""
    r = run(
        tmp_path,
        {
            ".ruby-version": "4.0.2",  # no trailing newline, as written by some tools
            ".node-version": "24.13.0\n",
            "mise.toml": """
                [tools]
                ruby = { version = "4.0.2", compile = false }
                node = "24.13.0"
            """,
            "Dockerfile": "ARG RUBY_VERSION=4.0.2\nRUN setup_24.x\n",
            "config/deploy.yml": """
                image: acme/app
                accessories:
                  mysql:
                    image: mysql:8.4
                #   valkey:
                #     image: valkey/valkey:8
            """,
            ".devcontainer/compose.yaml": "services:\n  db:\n    image: mysql:8.4\n",
            ".github/workflows/ci.yml": "jobs:\n  t:\n    services:\n      db:\n        image: mysql:8.4\n",
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "✓ ruby 4.0.2" in r.stdout
    assert "✓ node 24.13.0" in r.stdout
    assert "✓ mysql 8.4" in r.stdout
    # An untagged image pins nothing and a commented-out one isn't real config.
    assert "acme/app" not in r.stdout
    assert "valkey" not in r.stdout


def test_package_manager_pin_is_compared(tmp_path):
    """package.json's `packageManager` is corepack's pin and drifts from a Dockerfile ARG
    exactly like every other version does."""
    r = run(
        tmp_path,
        {
            "package.json": '{"name": "x", "packageManager": "pnpm@9.1.0+sha512.abc"}\n',
            "Dockerfile": "ARG PNPM_VERSION=9.2.0\n",
        },
    )
    assert r.returncode == 1
    assert (
        "✗ Dockerfile ARG PNPM_VERSION (9.2.0) != package.json packageManager (9.1.0)"
        in r.stdout
    )


def test_go_mod_directive_is_not_compared(tmp_path):
    """go.mod's `go` directive is a *minimum*, not a pin, and is routinely older than the
    toolchain — comparing it would fail healthy repos."""
    r = run(
        tmp_path,
        {
            "go.mod": "module example.com/x\n\ngo 1.21\n",
            ".go-version": "1.22.5\n",
            "mise.toml": '[tools]\ngo = "1.22.5"\n',
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "✓ go 1.22.5" in r.stdout
    assert "go.mod" not in r.stdout


@pytest.mark.parametrize(
    "image",
    ["${DB_IMAGE}", "{{ db_image }}", "<%= db_image %>"],
    ids=["compose-var", "mustache", "erb"],
)
def test_templated_images_are_ignored(tmp_path, image):
    """A templated `image:` names no concrete tag; treating the template text as one would
    produce a permanent, unfixable failure."""
    r = run(
        tmp_path,
        {
            "docker-compose.yml": f"services:\n  db:\n    image: {image}\n",
            ".github/workflows/ci.yml": "jobs:\n  t:\n    services:\n      db:\n        image: mysql:8.4\n",
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "✗" not in r.stdout

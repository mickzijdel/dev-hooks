"""Tests for the env-to-fnox skill's migrate_env_to_fnox.py automation.

Every case runs the script as a real subprocess (this repo's convention -- see
conftest.py), never by importing internals. `--dry-run` cases run with PATH stripped
of `bws`/`fnox` entirely, which itself proves no subprocess call is made. The
non-dry-run cases stub `bws`/`fnox` with tiny Python scripts under a fake bin dir
prepended to PATH -- `fake_bws` logs the exact argv of each `secret create` call (one
line per call, fields separated by a control character) so tests can assert the
parsed dotenv values reached `bws` unchanged, without a real Bitwarden account.
"""

import os
import shutil
import stat
import subprocess
import sys

import pytest

from conftest import DEV_HOOKS

SCRIPT = DEV_HOOKS / "skills" / "env-to-fnox" / "scripts" / "migrate_env_to_fnox.py"

SEP = "\x1e"  # unit separator: joins one call's argv into a single log line


def _run(*args, cwd, env=None, input_text=None):
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        cwd=cwd,
        input=input_text,
        env=env,
        capture_output=True,
        text=True,
    )


def _make_stub(path, body):
    path.write_text(body)
    path.chmod(path.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)


FAKE_BWS = f"""#!/usr/bin/env python3
import os, sys
with open(os.environ["BWS_CALL_LOG"], "a") as f:
    f.write({SEP!r}.join(sys.argv[1:]) + "\\n")
sys.exit(int(os.environ.get("BWS_EXIT_CODE", "0")))
"""

FAKE_FNOX_GET = """#!/usr/bin/env python3
import os, sys
key = sys.argv[-1]
if key in os.environ.get("FNOX_FAIL_KEYS", "").split(","):
    sys.exit(1)
print(f"resolved-{key}")
"""


@pytest.fixture
def fake_bin(tmp_path):
    """A bin/ dir with stub bws + fnox on it; returns (bin_dir, call_log_path)."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _make_stub(bin_dir / "bws", FAKE_BWS)
    _make_stub(bin_dir / "fnox", FAKE_FNOX_GET)
    return bin_dir, tmp_path / "bws_calls.log"


@pytest.fixture
def bare_path(tmp_path):
    """A PATH with no bws/fnox at all -- proves --dry-run makes zero subprocess calls."""
    empty = tmp_path / "empty_bin"
    empty.mkdir()
    return str(empty)


# ── dotenv parsing (via --dry-run, which is pure parse + summary, no subprocess) ────


def test_dry_run_parses_bare_single_and_double_quoted_values(tmp_path, bare_path):
    env_file = tmp_path / ".env"
    env_file.write_text(
        "\n".join(
            [
                "# a comment, and a blank line above",
                "",
                "BARE_VALUE=hello",
                "SINGLE_QUOTED='hello world'",
                'DOUBLE_QUOTED="hello \\"world\\""',
                "EMPTY_VALUE=",
            ]
        )
        + "\n"
    )
    r = _run(
        "--env-file",
        str(env_file),
        "--project-id",
        "proj-123",
        "--dry-run",
        cwd=tmp_path,
        env={"PATH": bare_path},
    )
    assert r.returncode == 0, r.stderr
    assert "Would migrate 4 variable(s):" in r.stdout
    for key in ("BARE_VALUE", "SINGLE_QUOTED", "DOUBLE_QUOTED", "EMPTY_VALUE"):
        assert key in r.stdout
    assert not (tmp_path / "fnox.toml").exists()


def test_dry_run_rejects_unsupported_syntax(tmp_path, bare_path):
    env_file = tmp_path / ".env"
    env_file.write_text("export FOO=bar\n")  # `export ` prefix isn't supported
    r = _run(
        "--env-file",
        str(env_file),
        "--project-id",
        "proj-123",
        "--dry-run",
        cwd=tmp_path,
        env={"PATH": bare_path},
    )
    assert r.returncode == 1
    assert "Unsupported dotenv syntax on line 1" in r.stderr


def test_dry_run_rejects_unterminated_double_quote(tmp_path, bare_path):
    env_file = tmp_path / ".env"
    env_file.write_text('BROKEN="unterminated\n')
    r = _run(
        "--env-file",
        str(env_file),
        "--project-id",
        "proj-123",
        "--dry-run",
        cwd=tmp_path,
        env={"PATH": bare_path},
    )
    assert r.returncode == 1
    assert "Unsupported dotenv value syntax on line 1" in r.stderr


def test_dry_run_rejects_empty_env_file(tmp_path, bare_path):
    env_file = tmp_path / ".env"
    env_file.write_text("# only a comment\n\n")
    r = _run(
        "--env-file",
        str(env_file),
        "--project-id",
        "proj-123",
        "--dry-run",
        cwd=tmp_path,
        env={"PATH": bare_path},
    )
    assert r.returncode == 1
    assert "no dotenv assignments found" in r.stderr


def test_dry_run_missing_env_file(tmp_path, bare_path):
    r = _run(
        "--env-file",
        str(tmp_path / "nope.env"),
        "--project-id",
        "proj-123",
        "--dry-run",
        cwd=tmp_path,
        env={"PATH": bare_path},
    )
    assert r.returncode == 1
    assert "no such file" in r.stderr


def test_dry_run_rejects_bad_project_id(tmp_path, bare_path):
    env_file = tmp_path / ".env"
    env_file.write_text("FOO=bar\n")
    r = _run(
        "--env-file",
        str(env_file),
        "--project-id",
        "not valid!",
        "--dry-run",
        cwd=tmp_path,
        env={"PATH": bare_path},
    )
    assert r.returncode == 1
    assert "--project-id may contain only" in r.stderr


def test_dry_run_makes_no_subprocess_calls(tmp_path, bare_path):
    # PATH has neither bws nor fnox; a real call would fail with "command not found"
    # via FileNotFoundError inside subprocess.run. A clean exit 0 here is the proof.
    env_file = tmp_path / ".env"
    env_file.write_text("A=1\nB=2\n")
    r = _run(
        "--env-file",
        str(env_file),
        "--project-id",
        "proj-123",
        "--dry-run",
        "--verify",
        "--delete-source",
        cwd=tmp_path,
        env={"PATH": bare_path},
    )
    assert r.returncode == 0, r.stderr
    assert env_file.exists()  # --delete-source is a no-op under --dry-run


# ── --help / argument validation (argparse) ─────────────────────────────────────────


def test_help_runs_clean(tmp_path):
    r = _run("--help", cwd=tmp_path)
    assert r.returncode == 0
    assert "usage" in r.stdout.lower()
    assert "--env-file" in r.stdout
    assert "--project-id" in r.stdout


def test_missing_required_arguments_is_usage_error(tmp_path):
    r = _run(cwd=tmp_path)
    assert r.returncode == 2
    assert "--env-file" in r.stderr
    assert "--project-id" in r.stderr


# ── real migration flow (stubbed bws/fnox) ──────────────────────────────────────────


def _bin_env(bin_dir, call_log, **extra):
    env = {
        "PATH": f"{bin_dir}:{os.environ.get('PATH', '')}",
        "BWS_CALL_LOG": str(call_log),
    }
    env.update(extra)
    return env


def test_migration_creates_secrets_and_writes_fnox_toml(tmp_path, fake_bin):
    bin_dir, call_log = fake_bin
    env_file = tmp_path / ".env"
    env_file.write_text(
        "DATABASE_URL=placeholder-db-value\nSTRIPE_KEY=placeholder-not-a-real-key\n"
    )
    output = tmp_path / "fnox.toml"
    r = _run(
        "--env-file",
        str(env_file),
        "--project-id",
        "proj-abc-123",
        "--output",
        str(output),
        cwd=tmp_path,
        env=_bin_env(bin_dir, call_log),
    )
    assert r.returncode == 0, r.stderr

    # bws was invoked once per variable, with the documented positional shape:
    # `bws secret create <key-name> <value> <project-id>`.
    # (split on "\n", not str.splitlines() -- the latter also breaks on \x1e, our SEP)
    calls = [line.split(SEP) for line in call_log.read_text().split("\n") if line]
    assert [
        "secret",
        "create",
        "database-url",
        "placeholder-db-value",
        "proj-abc-123",
    ] in calls
    assert [
        "secret",
        "create",
        "stripe-key",
        "placeholder-not-a-real-key",
        "proj-abc-123",
    ] in calls

    # fnox.toml holds only references -- the provider/project-id and key NAMES, never
    # a secret value.
    toml = output.read_text()
    assert "[providers]" in toml
    assert 'type = "bitwarden-sm"' in toml
    assert 'project_id = "proj-abc-123"' in toml
    assert "[secrets]" in toml
    assert 'DATABASE_URL = { provider = "bws", value = "database-url" }' in toml
    assert 'STRIPE_KEY = { provider = "bws", value = "stripe-key" }' in toml
    assert "placeholder-db-value" not in toml
    assert "placeholder-not-a-real-key" not in toml

    mode = output.stat().st_mode & 0o777
    assert mode == 0o600


def test_migration_reports_bws_failure(tmp_path, fake_bin):
    bin_dir, call_log = fake_bin
    env_file = tmp_path / ".env"
    env_file.write_text("FOO=bar\n")
    r = _run(
        "--env-file",
        str(env_file),
        "--project-id",
        "proj-1",
        cwd=tmp_path,
        env=_bin_env(bin_dir, call_log, BWS_EXIT_CODE="1"),
    )
    assert r.returncode == 1
    assert "bws secret create failed" in r.stderr
    assert not (tmp_path / "fnox.toml").exists()


def test_migration_missing_bws_binary(tmp_path, bare_path):
    env_file = tmp_path / ".env"
    env_file.write_text("FOO=bar\n")
    r = _run(
        "--env-file",
        str(env_file),
        "--project-id",
        "proj-1",
        cwd=tmp_path,
        env={"PATH": bare_path},
    )
    assert r.returncode == 1
    assert "bws CLI not found" in r.stderr


def test_migration_verify_success(tmp_path, fake_bin):
    bin_dir, call_log = fake_bin
    env_file = tmp_path / ".env"
    env_file.write_text("FOO=bar\n")
    r = _run(
        "--env-file",
        str(env_file),
        "--project-id",
        "proj-1",
        "--verify",
        cwd=tmp_path,
        env=_bin_env(bin_dir, call_log),
    )
    assert r.returncode == 0, r.stderr
    assert "Verified 1 secret(s) resolve via fnox." in r.stdout


def test_migration_verify_failure_blocks_success(tmp_path, fake_bin):
    bin_dir, call_log = fake_bin
    env_file = tmp_path / ".env"
    env_file.write_text("FOO=bar\n")
    r = _run(
        "--env-file",
        str(env_file),
        "--project-id",
        "proj-1",
        "--verify",
        cwd=tmp_path,
        env=_bin_env(bin_dir, call_log, FNOX_FAIL_KEYS="FOO"),
    )
    assert r.returncode == 1
    assert "verification failed for: FOO" in r.stderr


def test_migration_delete_source_with_correct_confirmation(tmp_path, fake_bin):
    bin_dir, call_log = fake_bin
    env_file = tmp_path / ".env"
    env_file.write_text("FOO=bar\n")
    r = _run(
        "--env-file",
        str(env_file),
        "--project-id",
        "proj-1",
        "--delete-source",
        cwd=tmp_path,
        env=_bin_env(bin_dir, call_log),
        input_text="DELETE\n",
    )
    assert r.returncode == 0, r.stderr
    assert not env_file.exists()
    assert "Removed" in r.stdout


def test_migration_delete_source_wrong_confirmation_keeps_file(tmp_path, fake_bin):
    bin_dir, call_log = fake_bin
    env_file = tmp_path / ".env"
    env_file.write_text("FOO=bar\n")
    r = _run(
        "--env-file",
        str(env_file),
        "--project-id",
        "proj-1",
        "--delete-source",
        cwd=tmp_path,
        env=_bin_env(bin_dir, call_log),
        input_text="yes\n",
    )
    assert r.returncode == 1
    assert env_file.exists()
    assert "confirmation did not match" in r.stderr
    # The migration itself already happened -- secrets and fnox.toml exist.
    assert (tmp_path / "fnox.toml").exists()


@pytest.mark.skipif(shutil.which("uv") is None, reason="uv not installed")
def test_runs_via_uv_shebang(tmp_path):
    """The shipping path: a PEP 723 script self-resolves via `uv run --script`."""
    r = subprocess.run(
        [str(SCRIPT), "--help"], cwd=tmp_path, capture_output=True, text=True
    )
    assert r.returncode == 0
    assert "usage" in r.stdout.lower()

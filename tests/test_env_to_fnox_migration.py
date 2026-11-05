"""Tests for the env-to-fnox skill's migrate_env_to_fnox.py automation.

Every case runs the script as a real subprocess (this repo's convention -- see
conftest.py), never by importing internals. `--dry-run` cases run with an empty PATH,
which itself proves no subprocess call is made. The other cases put a fake `fnox` on a
PATH that holds no real `fnox` or `bws` (the real ones are mise shims), under a temp
HOME, so no test can reach Bitwarden, the keychain or the network. The fake logs each
call (argv, whether BWS_ACCESS_TOKEN was in its env, and stdin for `set`) as one JSON
line, and answers `get` from FNOX_VALUES.
"""

import json
import shutil
import stat
import subprocess
import sys

import pytest
from conftest import DEV_HOOKS

SCRIPT = DEV_HOOKS / "skills" / "env-to-fnox" / "scripts" / "migrate_env_to_fnox.py"

FAKE_TOKEN = "fake-bws-token-6c1d9e"  # stands in for the keychain's BWS token

FAKE_FNOX = f"""#!/usr/bin/env python3
import json, os, sys
argv = sys.argv[1:]
rest = list(argv)
config = None
if rest[:1] == ["-c"]:
    config, rest = rest[1], rest[2:]
cmd = rest[0]
if cmd == "get" and rest[1:2] == ["-c"]:
    config, rest = rest[2], ["get", *rest[3:]]
entry = {{"argv": argv, "cmd": cmd, "config": config,
          "token": os.environ.get("BWS_ACCESS_TOKEN")}}
if cmd == "set":
    entry["stdin"] = sys.stdin.read()
with open(os.environ["FNOX_CALL_LOG"], "a") as f:
    f.write(json.dumps(entry) + "\\n")
if cmd == "get":
    key = rest[-1]
    if key == "BWS_ACCESS_TOKEN":
        if os.environ.get("FNOX_NO_TOKEN"):
            print("Error: secret not found", file=sys.stderr)
            sys.exit(1)
        print({FAKE_TOKEN!r})
        sys.exit(0)
    values = json.loads(os.environ.get("FNOX_VALUES", "{{}}"))
    if key not in values:
        sys.exit(1)
    print(values[key])
    sys.exit(0)
if cmd == "set":
    sys.exit(int(os.environ.get("FNOX_SET_EXIT", "0")))
sys.exit(3)
"""


def _run(*args, cwd, env=None, input_text=None):
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        cwd=cwd,
        input=input_text,
        env=env,
        capture_output=True,
        text=True,
    )


@pytest.fixture
def fake_env(tmp_path):
    """Env for a run against the fake fnox: temp HOME, a PATH proven free of the real
    fnox/bws. Returns (env, call_log); add keys to env for per-test behaviour."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    stub = bin_dir / "fnox"
    stub.write_text(FAKE_FNOX)
    stub.chmod(stub.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    home = tmp_path / "home"
    home.mkdir()
    path = f"{bin_dir}:/usr/bin:/bin"
    assert shutil.which("fnox", path=path) == str(stub)
    assert shutil.which("bws", path=path) is None
    call_log = tmp_path / "fnox_calls.log"
    env = {"PATH": path, "HOME": str(home), "FNOX_CALL_LOG": str(call_log)}
    return env, call_log


def _calls(call_log):
    if not call_log.exists():
        return []
    return [json.loads(line) for line in call_log.read_text().splitlines()]


@pytest.fixture
def bare_path(tmp_path):
    """A PATH with no fnox at all -- proves --dry-run makes zero subprocess calls."""
    empty = tmp_path / "empty_bin"
    empty.mkdir()
    return str(empty)


# ── dotenv parsing (via --dry-run, which is pure parse + summary, no subprocess) ────


def _dry(tmp_path, bare_path, *extra, project="proj-123"):
    return _run(
        "--env-file",
        str(tmp_path / ".env"),
        "--project-id",
        project,
        "--dry-run",
        *extra,
        cwd=tmp_path,
        env={"PATH": bare_path},
    )


def test_dry_run_parses_bare_single_and_double_quoted_values(tmp_path, bare_path):
    (tmp_path / ".env").write_text(
        "# a comment, and a blank line above\n"
        "\n"
        "BARE_VALUE=hello\n"
        "SINGLE_QUOTED='hello world'\n"
        'DOUBLE_QUOTED="hello \\"world\\""\n'
        "EMPTY_VALUE=\n"
    )
    r = _dry(tmp_path, bare_path)
    assert r.returncode == 0, r.stderr
    assert "Would migrate 4 variable(s):" in r.stdout
    for key in ("BARE_VALUE", "SINGLE_QUOTED", "DOUBLE_QUOTED", "EMPTY_VALUE"):
        assert key in r.stdout
    assert not (tmp_path / "fnox.toml").exists()


def test_dry_run_rejects_unsupported_syntax(tmp_path, bare_path):
    (tmp_path / ".env").write_text("export FOO=bar\n")  # `export ` prefix unsupported
    r = _dry(tmp_path, bare_path)
    assert r.returncode == 1
    assert "Unsupported dotenv syntax on line 1" in r.stderr


def test_dry_run_rejects_unterminated_double_quote(tmp_path, bare_path):
    (tmp_path / ".env").write_text('BROKEN="unterminated\n')
    r = _dry(tmp_path, bare_path)
    assert r.returncode == 1
    assert "Unsupported dotenv value syntax on line 1" in r.stderr


def test_dry_run_rejects_empty_env_file(tmp_path, bare_path):
    (tmp_path / ".env").write_text("# only a comment\n\n")
    r = _dry(tmp_path, bare_path)
    assert r.returncode == 1
    assert "no dotenv assignments found" in r.stderr


def test_dry_run_missing_env_file(tmp_path, bare_path):
    r = _dry(tmp_path, bare_path)
    assert r.returncode == 1
    assert "no such file" in r.stderr


def test_dry_run_rejects_bad_project_id(tmp_path, bare_path):
    (tmp_path / ".env").write_text("FOO=bar\n")
    r = _dry(tmp_path, bare_path, project="not valid!")
    assert r.returncode == 1
    assert "--project-id may contain only" in r.stderr


def test_dry_run_makes_no_subprocess_calls(tmp_path, bare_path):
    # PATH has no fnox; a real call would fail with FileNotFoundError inside
    # subprocess.run. A clean exit 0 here is the proof.
    env_file = tmp_path / ".env"
    env_file.write_text("A=1\nB=2\n")
    r = _dry(tmp_path, bare_path, "--verify", "--delete-source")
    assert r.returncode == 0, r.stderr
    assert env_file.exists()  # --delete-source is a no-op under --dry-run


def test_dry_run_shows_the_plan_without_values(tmp_path, bare_path):
    (tmp_path / ".env").write_text(
        "CLIENT_SECRET=val-cs-1\nPORT=val-port-3000\nREGISTRY=val-reg-77\n"
    )
    r = _dry(
        tmp_path,
        bare_path,
        "--key-prefix",
        "my-app-",
        "--config",
        "PORT",
        "--shared",
        "REGISTRY=kamal-registry-password",
    )
    assert r.returncode == 0, r.stderr
    assert "CLIENT_SECRET -> my-app-client-secret" in r.stdout
    assert "PORT" in r.stdout
    assert "REGISTRY -> kamal-registry-password" in r.stdout
    assert "val-" not in r.stdout + r.stderr


# ── --help / argument validation (argparse) ─────────────────────────────────────────


def test_help_runs_clean(tmp_path):
    r = _run("--help", cwd=tmp_path)
    assert r.returncode == 0
    assert "usage" in r.stdout.lower()
    for flag in ("--env-file", "--project-id", "--key-prefix", "--config", "--shared"):
        assert flag in r.stdout


def test_missing_required_arguments_is_usage_error(tmp_path):
    r = _run(cwd=tmp_path)
    assert r.returncode == 2
    assert "--env-file" in r.stderr
    assert "--project-id" in r.stderr


def test_config_var_missing_from_env_file_is_an_error(tmp_path, bare_path):
    (tmp_path / ".env").write_text("FOO=bar\n")
    r = _dry(tmp_path, bare_path, "--config", "NOPE")
    assert r.returncode == 1
    assert "--config NOPE is not in" in r.stderr


def test_malformed_shared_is_an_error(tmp_path, bare_path):
    (tmp_path / ".env").write_text("FOO=bar\n")
    r = _dry(tmp_path, bare_path, "--shared", "FOO")
    assert r.returncode == 1
    assert "--shared takes VAR=key-name" in r.stderr


def test_var_both_config_and_shared_is_an_error(tmp_path, bare_path):
    (tmp_path / ".env").write_text("FOO=bar\n")
    r = _dry(tmp_path, bare_path, "--config", "FOO", "--shared", "FOO=foo-key")
    assert r.returncode == 1
    assert "FOO is both --config and --shared" in r.stderr


# ── the real migration flow (fake fnox) ─────────────────────────────────────────────


def _migrate(tmp_path, env, *extra, input_text=None):
    return _run(
        "--env-file",
        str(tmp_path / ".env"),
        "--project-id",
        "proj-abc-123",
        "--output",
        str(tmp_path / "fnox.toml"),
        *extra,
        cwd=tmp_path,
        env=env,
        input_text=input_text,
    )


def test_token_reaches_only_the_fnox_set_child(tmp_path, fake_env):
    env, call_log = fake_env
    (tmp_path / ".env").write_text("DATABASE_URL=val-db-4e2f\n")
    env["FNOX_VALUES"] = json.dumps({"DATABASE_URL": "val-db-4e2f"})
    r = _migrate(tmp_path, env, "--verify")
    assert r.returncode == 0, r.stderr

    calls = _calls(call_log)
    token_get = calls[0]
    assert token_get["cmd"] == "get"
    assert token_get["argv"][-1] == "BWS_ACCESS_TOKEN"
    assert token_get["config"] == f"{env['HOME']}/.config/fnox/config.toml"

    sets = [c for c in calls if c["cmd"] == "set"]
    assert len(sets) == 1
    assert sets[0]["token"] == FAKE_TOKEN
    # Every other child (the token fetch, the verify reads) runs without it.
    assert all(c["token"] is None for c in calls if c["cmd"] != "set")
    assert FAKE_TOKEN not in r.stdout
    assert FAKE_TOKEN not in r.stderr
    assert FAKE_TOKEN not in (tmp_path / "fnox.toml").read_text()


def test_set_passes_the_value_on_stdin_never_argv(tmp_path, fake_env):
    env, call_log = fake_env
    (tmp_path / ".env").write_text(
        "DATABASE_URL=val-db-4e2f\nSTRIPE_KEY='val stripe 8a'\n"
    )
    r = _migrate(tmp_path, env)
    assert r.returncode == 0, r.stderr
    sets = {c["argv"][3]: c for c in _calls(call_log) if c["cmd"] == "set"}
    output = str(tmp_path / "fnox.toml")
    assert sets["DATABASE_URL"]["argv"] == [
        "-c",
        output,
        "set",
        "DATABASE_URL",
        "-p",
        "bws",
        "-k",
        "database-url",
    ]
    assert sets["DATABASE_URL"]["stdin"] == "val-db-4e2f"
    assert sets["STRIPE_KEY"]["stdin"] == "val stripe 8a"
    for c in sets.values():
        assert not {"val-db-4e2f", "val stripe 8a"} & set(c["argv"])
    assert "val-" not in r.stdout + r.stderr


def test_fnox_toml_holds_references_only(tmp_path, fake_env):
    env, _ = fake_env
    (tmp_path / ".env").write_text(
        "DATABASE_URL=val-db-4e2f\nSTRIPE_KEY=val-stripe-8a\n"
    )
    r = _migrate(tmp_path, env)
    assert r.returncode == 0, r.stderr
    toml = (tmp_path / "fnox.toml").read_text()
    assert "[providers]" in toml
    assert 'type = "bitwarden-sm"' in toml
    assert 'project_id = "proj-abc-123"' in toml
    assert 'DATABASE_URL = { provider = "bws", value = "database-url" }' in toml
    assert 'STRIPE_KEY = { provider = "bws", value = "stripe-key" }' in toml
    assert "val-" not in toml
    assert (tmp_path / "fnox.toml").stat().st_mode & 0o777 == 0o600


def test_key_prefix_names_every_new_key(tmp_path, fake_env):
    env, call_log = fake_env
    (tmp_path / ".env").write_text("CLIENT_SECRET=val-cs-1\n")
    r = _migrate(tmp_path, env, "--key-prefix", "basecamp-sp-proxy-")
    assert r.returncode == 0, r.stderr
    (set_call,) = [c for c in _calls(call_log) if c["cmd"] == "set"]
    assert set_call["argv"][-1] == "basecamp-sp-proxy-client-secret"
    toml = (tmp_path / "fnox.toml").read_text()
    assert (
        'CLIENT_SECRET = { provider = "bws", value = "basecamp-sp-proxy-client-secret" }'
        in toml
    )


def test_config_vars_become_plain_defaults(tmp_path, fake_env):
    env, call_log = fake_env
    (tmp_path / ".env").write_text(
        'SECRET=val-s-1\nPORT=3000\nBASE_URL="https://example.test/a"\n'
    )
    r = _migrate(tmp_path, env, "--config", "PORT", "BASE_URL")
    assert r.returncode == 0, r.stderr
    toml = (tmp_path / "fnox.toml").read_text()
    assert 'PORT = { default = "3000" }' in toml
    assert 'BASE_URL = { default = "https://example.test/a" }' in toml
    assert [c["argv"][3] for c in _calls(call_log) if c["cmd"] == "set"] == ["SECRET"]


def test_shared_vars_reference_an_existing_key(tmp_path, fake_env):
    env, call_log = fake_env
    (tmp_path / ".env").write_text("SECRET=val-s-1\nKAMAL_REGISTRY_PASSWORD=val-k\n")
    r = _migrate(
        tmp_path, env, "--shared", "KAMAL_REGISTRY_PASSWORD=kamal-registry-password"
    )
    assert r.returncode == 0, r.stderr
    toml = (tmp_path / "fnox.toml").read_text()
    assert (
        'KAMAL_REGISTRY_PASSWORD = { provider = "bws", '
        'value = "kamal-registry-password" }' in toml
    )
    assert [c["argv"][3] for c in _calls(call_log) if c["cmd"] == "set"] == ["SECRET"]


def test_verify_prints_only_same_or_different(tmp_path, fake_env):
    env, _ = fake_env
    (tmp_path / ".env").write_text(
        "SAME_ONE=val-same-1\nCLASHED=val-mine-2\nPORT=val-port-3\nGONE=val-gone-4\n"
    )
    env["FNOX_VALUES"] = json.dumps(
        {"SAME_ONE": "val-same-1", "CLASHED": "val-theirs-2", "PORT": "val-port-3"}
    )
    r = _migrate(tmp_path, env, "--config", "PORT", "--verify")
    assert r.returncode == 1
    assert "SAME_ONE: same" in r.stdout
    assert "CLASHED: different" in r.stdout
    assert "PORT: same" in r.stdout
    assert "GONE: unresolved" in r.stdout
    assert "verification failed for: CLASHED, GONE" in r.stderr
    assert "val-" not in r.stdout + r.stderr


def test_verify_success(tmp_path, fake_env):
    env, _ = fake_env
    (tmp_path / ".env").write_text("FOO=val-foo-1\n")
    env["FNOX_VALUES"] = json.dumps({"FOO": "val-foo-1"})
    r = _migrate(tmp_path, env, "--verify")
    assert r.returncode == 0, r.stderr
    assert "FOO: same" in r.stdout
    assert "Verified 1 variable(s) match" in r.stdout


def test_missing_token_stops_before_anything_is_written(tmp_path, fake_env):
    env, call_log = fake_env
    (tmp_path / ".env").write_text("FOO=val-foo-1\n")
    env["FNOX_NO_TOKEN"] = "1"
    r = _migrate(tmp_path, env)
    assert r.returncode == 1
    assert "could not read BWS_ACCESS_TOKEN" in r.stderr
    assert not (tmp_path / "fnox.toml").exists()
    assert not [c for c in _calls(call_log) if c["cmd"] == "set"]


def test_set_failure_names_the_variable(tmp_path, fake_env):
    env, _ = fake_env
    (tmp_path / ".env").write_text("FOO=val-foo-1\n")
    env["FNOX_SET_EXIT"] = "1"
    r = _migrate(tmp_path, env)
    assert r.returncode == 1
    assert "fnox set failed for FOO (foo)" in r.stderr
    assert FAKE_TOKEN not in r.stderr


def test_missing_fnox_binary(tmp_path, bare_path):
    (tmp_path / ".env").write_text("FOO=bar\n")
    r = _run(
        "--env-file",
        str(tmp_path / ".env"),
        "--project-id",
        "proj-1",
        cwd=tmp_path,
        env={"PATH": bare_path, "HOME": str(tmp_path)},
    )
    assert r.returncode == 1
    assert "fnox CLI not found" in r.stderr


def test_delete_source_with_correct_confirmation(tmp_path, fake_env):
    env, _ = fake_env
    env_file = tmp_path / ".env"
    env_file.write_text("FOO=bar\n")
    r = _migrate(tmp_path, env, "--delete-source", input_text="DELETE\n")
    assert r.returncode == 0, r.stderr
    assert not env_file.exists()
    assert "Removed" in r.stdout


def test_delete_source_wrong_confirmation_keeps_file(tmp_path, fake_env):
    env, _ = fake_env
    env_file = tmp_path / ".env"
    env_file.write_text("FOO=bar\n")
    r = _migrate(tmp_path, env, "--delete-source", input_text="yes\n")
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

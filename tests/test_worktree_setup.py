"""setup-worktree.sh (worktree-setup skill).

The native EnterWorktree tool switches the session into a fresh worktree but leaves it
unprovisioned: mise.toml untrusted, gitignored-but-needed files (Rails master.key, .env)
missing, and shebang scripts possibly non-executable. This script, run *inside* the new
worktree, fixes all of that. Exercised as a subprocess against a throwaway repo + worktree —
never by importing internals.
"""

import os
import shutil
import subprocess


from conftest import DEV_HOOKS, init_git_repo, parse_kv

SETUP = DEV_HOOKS / "skills" / "worktree-setup" / "scripts" / "setup-worktree.sh"


def _make_source_repo(path):
    """A committed repo carrying a tracked shebang script plus a set of gitignored files
    (secrets to copy + heavy dirs to skip), then returns its `run` git helper."""
    run = init_git_repo(path)
    (path / ".gitignore").write_text(
        ".env\nconfig/master.key\nnode_modules/\n.venv/\n.worktrees/\n"
    )
    # Tracked shebang script — committed at 100644 so the worktree checkout can drop +x,
    # exactly the case the exec-bit pass re-applies.
    script = path / "bin" / "run.sh"
    script.parent.mkdir()
    script.write_text("#!/usr/bin/env bash\necho hi\n")
    run("add", ".gitignore", "bin/run.sh")
    run("update-index", "--chmod=-x", "bin/run.sh")
    run("commit", "-q", "-m", "init")

    # Gitignored-but-present working-tree files: secrets/config to copy …
    (path / ".env").write_text("SECRET=1\n")
    (path / "config").mkdir()
    (path / "config" / "master.key").write_text("deadbeef\n")
    # … and a heavy dependency dir to skip.
    (path / "node_modules").mkdir()
    (path / "node_modules" / "big.js").write_text("// huge\n")
    (path / ".venv").mkdir()
    (path / ".venv" / "pyvenv.cfg").write_text("home = /x\n")
    return run


def _add_worktree(src, wt_path):
    subprocess.run(
        ["git", "worktree", "add", "-q", "-b", "wt", str(wt_path), "HEAD"],
        cwd=str(src),
        check=True,
        capture_output=True,
        text=True,
    )


def run_setup(wt_path, *args):
    """Run setup-worktree.sh from inside the worktree and parse its key=value block."""
    r = subprocess.run(
        ["bash", str(SETUP), *args],
        cwd=str(wt_path),
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr
    return parse_kv(r.stdout), r.stdout


def test_copies_secrets_and_skips_heavy_dirs(tmp_path):
    src = tmp_path / "src"
    src.mkdir()
    _make_source_repo(src)
    wt = src / ".worktrees" / "wt"
    _add_worktree(src, wt)

    out, _ = run_setup(wt)

    # Secrets / config copied verbatim into the worktree …
    assert (wt / ".env").read_text() == "SECRET=1\n"
    assert (wt / "config" / "master.key").read_text() == "deadbeef\n"
    # … heavy dirs skipped …
    assert not (wt / "node_modules").exists()
    assert not (wt / ".venv").exists()
    assert int(out["copied"]) >= 2
    assert int(out["skipped_heavy"]) >= 2


def test_does_not_copy_worktree_into_itself(tmp_path):
    """`.worktrees/` is gitignored, so a naive copy would recurse the worktree into itself."""
    src = tmp_path / "src"
    src.mkdir()
    _make_source_repo(src)
    wt = src / ".worktrees" / "wt"
    _add_worktree(src, wt)

    run_setup(wt)

    assert not (wt / ".worktrees").exists()


def test_reapplies_exec_bit_on_shebang_scripts(tmp_path):
    src = tmp_path / "src"
    src.mkdir()
    _make_source_repo(src)
    wt = src / ".worktrees" / "wt"
    _add_worktree(src, wt)
    # Simulate a checkout that dropped the executable bit.
    os.chmod(wt / "bin" / "run.sh", 0o644)

    out, _ = run_setup(wt)

    assert os.access(wt / "bin" / "run.sh", os.X_OK)
    assert int(out["exec_fixed"]) >= 1


def test_sets_baseref_to_head(tmp_path):
    src = tmp_path / "src"
    src.mkdir()
    _make_source_repo(src)
    wt = src / ".worktrees" / "wt"
    _add_worktree(src, wt)

    run_setup(wt)

    baseref = subprocess.run(
        ["git", "config", "--get", "worktree.baseref"],
        cwd=str(src),
        capture_output=True,
        text=True,
    ).stdout.strip()
    assert baseref == "head"


def test_resolves_source_and_worktree_paths(tmp_path):
    src = tmp_path / "src"
    src.mkdir()
    _make_source_repo(src)
    wt = src / ".worktrees" / "wt"
    _add_worktree(src, wt)

    out, _ = run_setup(wt)

    assert os.path.realpath(out["worktree"]) == os.path.realpath(wt)
    assert os.path.realpath(out["source"]) == os.path.realpath(src)


def test_mise_trust_gated_on_mise_availability(tmp_path):
    src = tmp_path / "src"
    src.mkdir()
    _make_source_repo(src)
    (src / "mise.toml").write_text("[tools]\n")
    wt = src / ".worktrees" / "wt"
    _add_worktree(src, wt)

    out, _ = run_setup(wt)

    # The key is always emitted; its value reflects whether mise was found + ran.
    assert out["mise_trusted"] in {"0", "1"}
    if shutil.which("mise") is None:
        assert out["mise_trusted"] == "0"


def test_source_override_flag(tmp_path):
    """--source pins the copy origin instead of auto-detecting the main worktree."""
    src = tmp_path / "src"
    src.mkdir()
    _make_source_repo(src)
    wt = src / ".worktrees" / "wt"
    _add_worktree(src, wt)

    out, _ = run_setup(wt, "--source", str(src))
    assert os.path.realpath(out["source"]) == os.path.realpath(src)
    assert (wt / ".env").exists()


def test_explicit_worktree_arg(tmp_path):
    """A positional worktree path lets the script run from anywhere, not just inside it."""
    src = tmp_path / "src"
    src.mkdir()
    _make_source_repo(src)
    wt = src / ".worktrees" / "wt"
    _add_worktree(src, wt)

    r = subprocess.run(
        ["bash", str(SETUP), str(wt)],
        cwd=str(tmp_path),
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr
    out = parse_kv(r.stdout)
    assert os.path.realpath(out["worktree"]) == os.path.realpath(wt)
    assert (wt / ".env").exists()

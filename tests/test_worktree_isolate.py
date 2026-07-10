"""isolate-worktree.sh (worktree-setup skill).

setup-worktree.sh copies .env/master.key verbatim into every worktree, so N worktrees all
collide on the same port and database. isolate-worktree.sh closes that gap: driven by a
committed .worktree-isolate.conf, it allocates a stable, collision-free per-worktree offset
from a shared registry and writes the derived PORT / DB suffix / redis index /
COMPOSE_PROJECT_NAME into a gitignored mise.local.toml overlay (never touching the copied
.env). Exercised as a subprocess against throwaway repos + real worktrees, never by importing
internals.
"""

import subprocess

from conftest import DEV_HOOKS, init_git_repo, parse_kv

ISOLATE = DEV_HOOKS / "skills" / "worktree-setup" / "scripts" / "isolate-worktree.sh"

CONF = (
    "WT_BASE_PORT=3000\n"
    "WT_DB_SUFFIX_VAR=WORKTREE_DB_SUFFIX\n"
    "WT_REDIS_URL_VAR=REDIS_URL\n"
    "WT_COMPOSE_NAME=myapp\n"
)


def _source_repo(path):
    """A committed repo (isolate needs a commit so worktrees can be added)."""
    run = init_git_repo(path)
    (path / ".gitignore").write_text("mise.local.toml\n.worktrees/\n")
    (path / "README.md").write_text("# x\n")
    run("add", ".gitignore", "README.md")
    run("commit", "-q", "-m", "init")
    return run


def _add_worktree(src, branch, wt_path):
    subprocess.run(
        ["git", "worktree", "add", "-q", "-b", branch, str(wt_path), "HEAD"],
        cwd=str(src),
        check=True,
        capture_output=True,
        text=True,
    )
    return wt_path


def _remove_worktree(src, wt_path):
    subprocess.run(
        ["git", "worktree", "remove", "--force", str(wt_path)],
        cwd=str(src),
        check=True,
        capture_output=True,
        text=True,
    )


def run_isolate(wt_path, *args):
    r = subprocess.run(
        ["bash", str(ISOLATE), *args],
        cwd=str(wt_path),
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr
    return parse_kv(r.stdout), r.stdout


def _mk(tmp_path, branch, *, conf=CONF):
    """Build a source repo + one worktree on `branch`, optionally seeding its conf file."""
    src = tmp_path / "src"
    src.mkdir()
    _source_repo(src)
    wt = _add_worktree(src, branch, src / ".worktrees" / branch)
    if conf is not None:
        (wt / ".worktree-isolate.conf").write_text(conf)
    return src, wt


def test_absent_config_is_a_noop(tmp_path):
    """No .worktree-isolate.conf ⇒ behaves as before: writes nothing, reports config=none."""
    _, wt = _mk(tmp_path, "feat-x", conf=None)

    out, _ = run_isolate(wt)

    assert out["config"] == "none"
    assert not (wt / "mise.local.toml").exists()


def test_writes_isolation_vars(tmp_path):
    _, wt = _mk(tmp_path, "feat-x")

    out, _ = run_isolate(wt)

    # First worktree gets offset 1 (offset 0 is reserved for the un-provisioned main checkout
    # still running on the base port).
    assert out["offset"] == "1"
    assert out["port"] == "3001"
    assert out["db_suffix"] == "_feat_x"
    assert out["compose_project"] == "myapp_feat_x"

    mise = (wt / "mise.local.toml").read_text()
    assert 'PORT = "3001"' in mise
    assert 'WORKTREE_DB_SUFFIX = "_feat_x"' in mise
    assert 'REDIS_URL = "redis://localhost:6379/1"' in mise
    assert 'COMPOSE_PROJECT_NAME = "myapp_feat_x"' in mise


def test_two_worktrees_get_distinct_offsets(tmp_path):
    src = tmp_path / "src"
    src.mkdir()
    _source_repo(src)
    wt_x = _add_worktree(src, "feat-x", src / ".worktrees" / "feat-x")
    wt_y = _add_worktree(src, "feat-y", src / ".worktrees" / "feat-y")
    (wt_x / ".worktree-isolate.conf").write_text(CONF)
    (wt_y / ".worktree-isolate.conf").write_text(CONF)

    out_x, _ = run_isolate(wt_x)
    out_y, _ = run_isolate(wt_y)

    assert out_x["port"] != out_y["port"]
    assert {out_x["offset"], out_y["offset"]} == {"1", "2"}
    assert out_x["db_suffix"] == "_feat_x"
    assert out_y["db_suffix"] == "_feat_y"


def test_offset_is_stable_across_reruns(tmp_path):
    _, wt = _mk(tmp_path, "feat-x")

    first, _ = run_isolate(wt)
    second, _ = run_isolate(wt)

    assert first["offset"] == second["offset"]
    # Idempotent: re-run rewrites the generated block, never appends a duplicate PORT.
    mise = (wt / "mise.local.toml").read_text()
    assert mise.count("PORT = ") == 1
    assert mise.count("[env]") == 1


def test_pruning_frees_a_removed_worktrees_offset(tmp_path):
    src = tmp_path / "src"
    src.mkdir()
    _source_repo(src)
    wt_x = _add_worktree(src, "feat-x", src / ".worktrees" / "feat-x")
    wt_y = _add_worktree(src, "feat-y", src / ".worktrees" / "feat-y")
    (wt_x / ".worktree-isolate.conf").write_text(CONF)
    (wt_y / ".worktree-isolate.conf").write_text(CONF)
    assert run_isolate(wt_x)[0]["offset"] == "1"
    assert run_isolate(wt_y)[0]["offset"] == "2"

    # feat-x goes away; its offset 1 should become free again.
    _remove_worktree(src, wt_x)
    wt_z = _add_worktree(src, "feat-z", src / ".worktrees" / "feat-z")
    (wt_z / ".worktree-isolate.conf").write_text(CONF)

    assert run_isolate(wt_z)[0]["offset"] == "1"


def test_extra_ports_each_get_the_offset(tmp_path):
    _, wt = _mk(
        tmp_path, "feat-x", conf="WT_BASE_PORT=3000\nWT_EXTRA_PORTS=VITE_PORT=3036\n"
    )

    run_isolate(wt)

    mise = (wt / "mise.local.toml").read_text()
    assert 'PORT = "3001"' in mise
    assert 'VITE_PORT = "3037"' in mise


def test_compose_project_only_when_name_set(tmp_path):
    _, wt = _mk(tmp_path, "feat-x", conf="WT_BASE_PORT=3000\n")

    out, _ = run_isolate(wt)

    assert out["compose_project"] == ""
    assert "COMPOSE_PROJECT_NAME" not in (wt / "mise.local.toml").read_text()


def test_writes_compose_adjacent_env(tmp_path):
    conf = CONF + "WT_COMPOSE_ENV=.devcontainer/.env\n"
    _, wt = _mk(tmp_path, "feat-x", conf=conf)

    run_isolate(wt)

    env = (wt / ".devcontainer" / ".env").read_text()
    assert "COMPOSE_PROJECT_NAME=myapp_feat_x" in env
    assert "PORT=3001" in env


def test_never_touches_copied_env(tmp_path):
    _, wt = _mk(tmp_path, "feat-x")
    (wt / ".env").write_text("SECRET=1\n")

    run_isolate(wt)

    assert (wt / ".env").read_text() == "SECRET=1\n"

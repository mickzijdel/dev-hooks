"""plugin-scope-reminder.sh: a plugin switched off here whose trigger matches (a project file
at SessionStart, a typed prompt at UserPromptSubmit) gets Claude to offer enabling it."""

import json
import os
import subprocess

from conftest import HOOKS, init_git_repo

RAILS = "rails-toolkit@skills-dir"
AIRTABLE = "airtable-utils@airtable-utils"
TRIGGERS = {
    RAILS: {"file": "Gemfile", "match": "^[[:space:]]*gem ['\"]rails['\"]"},
    AIRTABLE: {"prompt": "\\bairtable\\b"},
}


def _setup(tmp_path, *, user=None, local=None, triggers=TRIGGERS, gemfile=None):
    config = tmp_path / "xdg"
    claude = tmp_path / "claude"
    repo = tmp_path / "repo"
    for d in (config / "dev-hooks", claude, repo / ".claude"):
        d.mkdir(parents=True)
    init_git_repo(repo)
    if triggers is not None:
        (config / "dev-hooks" / "plugin-triggers.json").write_text(json.dumps(triggers))
    (claude / "settings.json").write_text(json.dumps({"enabledPlugins": user or {}}))
    if local is not None:
        (repo / ".claude" / "settings.local.json").write_text(
            json.dumps({"enabledPlugins": local})
        )
    if gemfile is not None:
        (repo / "Gemfile").write_text(gemfile)
    env = {
        **os.environ,
        "XDG_CONFIG_HOME": str(config),
        "CLAUDE_CONFIG_DIR": str(claude),
    }
    return repo, env


def _run(mode, payload, env):
    return subprocess.run(
        ["bash", str(HOOKS / "plugin-scope-reminder.sh"), mode],
        input=json.dumps(payload),
        env=env,
        capture_output=True,
        text=True,
    )


def _context(r):
    assert r.returncode == 0, r.stderr
    if not r.stdout.strip():
        return ""
    return json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"]


def _session(repo, env, session="11111111-2222-3333-4444-555555555555"):
    return _context(_run("session", {"cwd": str(repo), "session_id": session}, env))


def _prompt(repo, env, prompt, session="11111111-2222-3333-4444-555555555555"):
    payload = {"cwd": str(repo), "session_id": session, "prompt": prompt}
    return _context(_run("prompt", payload, env))


def test_session_start_names_a_plugin_whose_project_file_matches(tmp_path):
    repo, env = _setup(tmp_path, user={RAILS: False}, gemfile='gem "rails", "~> 8.0"\n')
    msg = _session(repo, env)
    assert RAILS in msg
    assert f"claude plugin enable {RAILS} --scope local" in msg
    assert "/reload-plugins" in msg


def test_session_start_silent_when_the_plugin_is_on_here(tmp_path):
    # local beats user, as in Claude Code's own precedence
    repo, env = _setup(
        tmp_path, user={RAILS: False}, local={RAILS: True}, gemfile='gem "rails"\n'
    )
    assert _session(repo, env) == ""


def test_session_start_silent_without_a_match_or_a_config(tmp_path):
    repo, env = _setup(tmp_path, user={RAILS: False}, gemfile='gem "sinatra"\n')
    assert _session(repo, env) == ""
    repo2, env2 = _setup(
        tmp_path / "b", user={RAILS: False}, triggers=None, gemfile='gem "rails"\n'
    )
    assert _session(repo2, env2) == ""


def test_session_start_silent_when_the_plugin_was_never_switched_off(tmp_path):
    repo, env = _setup(tmp_path, gemfile='gem "rails"\n')
    assert _session(repo, env) == ""


def test_prompt_naming_the_trigger_gets_the_offer_once_per_session(tmp_path):
    repo, env = _setup(tmp_path, user={AIRTABLE: False})
    msg = _prompt(repo, env, "Can you fix the Airtable sync for the shows table?")
    assert AIRTABLE in msg and "/reload-plugins" in msg
    assert _prompt(repo, env, "and the airtable view too") == ""
    assert _prompt(repo, env, "airtable again", session="other-session") != ""


def test_prompt_silent_without_the_trigger_or_from_an_agent(tmp_path):
    repo, env = _setup(tmp_path, user={AIRTABLE: False})
    assert _prompt(repo, env, "fix the login page") == ""
    notification = "<task-notification>the airtable export finished</task-notification>"
    assert _prompt(repo, env, notification) == ""

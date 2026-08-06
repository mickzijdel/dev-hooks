"""Every dev-hooks hook script must declare the capability bet it makes.

Part of the harness's standing anti-overengineering mechanism: a scaffold that compensates
for a model weakness has to name that weakness (`# bet:`) and the observable that would make
it removable (`# sunset:`). Scaffolds that encode preference/fact/verification/safety instead
say so with `bet: none (L1-L6)` and `sunset: never`. The point is that a NEW hook can't be
added without its author consciously stating what capability bet it is making — the absence of
a declared bet is the failure, so the pruning review (weekly-automation-review's Retire pass)
always has something concrete to check against the current model.
"""

import os
import subprocess

from conftest import HOOKS

LIB = HOOKS / "lib" / "reminder-common.sh"


def _fire(home, **env):
    """Source the lib and invoke the fire-logger once, under a controlled HOME."""
    e = os.environ.copy()
    e["HOME"] = str(home)
    e.update(env)
    subprocess.run(
        ["bash", "-c", f'SESSION=s1; source "{LIB}"; _reminder_log_fire probe.sh'],
        env=e,
        check=True,
    )


def test_fire_log_writes_only_when_opted_in(tmp_path):
    log = tmp_path / ".claude" / "automation-review" / "hook-fires.jsonl"
    log.parent.mkdir(parents=True)
    # Default (env unset) → best-effort no-op, nothing written.
    _fire(tmp_path)
    assert not log.exists()
    # Opt-in → one JSONL line naming the firing hook and session.
    _fire(tmp_path, DEV_HOOKS_FIRE_LOG="1")
    assert log.exists()
    body = log.read_text()
    assert '"hook":"probe.sh"' in body and '"session":"s1"' in body


def test_fire_log_silent_without_dir(tmp_path):
    # Opted in but the automation-review dir doesn't exist → still silent, never errors.
    _fire(tmp_path, DEV_HOOKS_FIRE_LOG="1")
    assert not (
        tmp_path / ".claude" / "automation-review" / "hook-fires.jsonl"
    ).exists()


def _emit_function_bodies():
    """Split the lib into {function name: body} for every `reminder_emit*` function."""
    bodies, name, buf = {}, None, []
    for line in LIB.read_text().splitlines():
        if name is None:
            if line.startswith("reminder_emit") and line.rstrip().endswith("() {"):
                name = line.split("(")[0]
        elif line == "}":
            bodies[name], name, buf = "\n".join(buf), None, []
        else:
            buf.append(line)
    return bodies


def test_every_emit_function_logs_a_fire():
    """A hook is only visible to the Retire pass if the emit function it calls logs the
    fire. reminder_emit_decision silently lacked the call, which made dangerous-command-guard
    permanently invisible and its "0 fires" undecidable. Every emit path must log."""
    bodies = _emit_function_bodies()
    assert len(bodies) >= 5, f"emit functions not parsed from the lib: {sorted(bodies)}"
    missing = [n for n, body in bodies.items() if "_reminder_log_fire" not in body]
    assert not missing, (
        "emit functions that don't record a fire — hooks calling them can never appear in "
        f"hook-fires.jsonl, so their fire count is meaningless: {missing}"
    )


def test_no_hook_emits_outside_the_lib():
    """The corollary: a hook that hand-rolls its own emit skips the logging entirely. Route
    every emission through the lib (reminder_emit / _session / _prompt / _stop / _decision /
    _correction) so instrumentation can't be bypassed by copying a jq line into a hook."""
    offenders = {}
    for script in sorted(HOOKS.glob("*.sh")):
        hits = []
        for n, line in enumerate(script.read_text().splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            if "hookSpecificOutput" in stripped or stripped == "exit 2":
                hits.append(f"{n}: {stripped[:60]}")
        if hits:
            offenders[script.name] = hits
    assert not offenders, (
        "hooks emitting without the lib (so no fire is logged) — use a reminder_emit_* "
        f"helper instead: {offenders}"
    )


def test_session_start_hook_logs_a_fire(tmp_path):
    """End-to-end: the SessionStart hooks predated reminder_emit_session and inlined their
    own jq, so none of them ever reached the fire log. Prove one really does now."""
    home = tmp_path / "home"
    (home / ".claude" / "automation-review").mkdir(parents=True)
    proj = tmp_path / "proj"
    proj.mkdir()
    (proj / "pyproject.toml").write_text("[project]\nname='x'\n")

    e = os.environ.copy()
    e.update(HOME=str(home), DEV_HOOKS_FIRE_LOG="1")
    r = subprocess.run(
        ["bash", str(HOOKS / "detect-stack-skills.sh")],
        input=f'{{"cwd":"{proj}","session_id":"sess-abc"}}',
        env=e,
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr
    assert "SessionStart" in r.stdout, r.stdout

    log = home / ".claude" / "automation-review" / "hook-fires.jsonl"
    assert log.exists(), "SessionStart hook emitted but logged no fire"
    body = log.read_text()
    assert '"hook":"detect-stack-skills.sh"' in body
    assert '"session":"sess-abc"' in body, "session_id not carried into the fire log"


def test_every_hook_declares_a_bet_and_sunset():
    missing = {}
    for script in sorted(HOOKS.glob("*.sh")):
        head = script.read_text().splitlines()[:8]
        needs = [
            tag
            for tag in ("# bet:", "# sunset:")
            if not any(line.startswith(tag) for line in head)
        ]
        if needs:
            missing[script.name] = needs
    assert not missing, (
        "hook scripts missing bet/sunset annotation in their first 8 lines "
        f"(add `# bet:`/`# sunset:` after the shebang): {missing}"
    )

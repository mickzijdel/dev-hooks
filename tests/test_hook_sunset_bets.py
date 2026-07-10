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

"""Every plugin's hooks.json registers each hook on an event that can run it. Claude Code
runs `"type": "prompt"` and `"type": "agent"` hooks only on the tool events; one configured
on Stop or UserPromptSubmit loads without error and silently never runs."""

import json

import pytest
from conftest import ROOT

TOOL_EVENTS = {"PreToolUse", "PostToolUse", "PermissionRequest"}
MODEL_TYPES = {"prompt", "agent"}
HOOK_FILES = sorted(ROOT.glob("plugins/*/hooks/hooks.json"))


def misplaced(config):
    """`<event>: <type>` for each prompt or agent hook outside the tool events."""
    return [
        f"{event}: {hook.get('type')}"
        for event, groups in config.get("hooks", {}).items()
        if event not in TOOL_EVENTS
        for group in groups
        for hook in group.get("hooks", [])
        if hook.get("type") in MODEL_TYPES
    ]


def test_finds_every_plugin_hook_file():
    names = {p.parent.parent.name for p in HOOK_FILES}
    assert {"dev-hooks", "thinking-tools", "writing"} <= names


@pytest.mark.parametrize("path", HOOK_FILES, ids=lambda p: p.parent.parent.name)
def test_model_hooks_sit_only_on_tool_events(path):
    assert misplaced(json.loads(path.read_text())) == []


def test_a_prompt_hook_on_stop_is_caught():
    config = {
        "hooks": {
            "Stop": [{"hooks": [{"type": "prompt", "prompt": "judge the work"}]}],
            "PreToolUse": [
                {"matcher": "Bash", "hooks": [{"type": "agent", "prompt": "check"}]}
            ],
        }
    }
    assert misplaced(config) == ["Stop: prompt"]


def _bash_hooks(config, event):
    return [
        hook
        for group in config["hooks"].get(event, [])
        if group.get("matcher") == "Bash"
        for hook in group["hooks"]
    ]


def test_skill_injected_commands_meet_the_bash_guards():
    """A skill's `!`cmd`` runs without PreToolUse, so each Bash-only guard also sits on
    PreSkillShellCommand, failing the same way (a crashed blocking guard must still block)."""
    config = json.loads((ROOT / "plugins/dev-hooks/hooks/hooks.json").read_text())
    assert _bash_hooks(config, "PreSkillShellCommand") == _bash_hooks(
        config, "PreToolUse"
    )

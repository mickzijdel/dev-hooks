"""marketplace.json carries one stable line per plugin (CLAUDE.md). A description that names
the plugin's skills drifts each time one is added: thinking-tools' listed seven of thirteen."""

import json
import re

import pytest
from conftest import ROOT

ENTRIES = json.loads((ROOT / ".claude-plugin" / "marketplace.json").read_text())[
    "plugins"
]


@pytest.mark.parametrize("entry", ENTRIES, ids=[e["name"] for e in ENTRIES])
def test_marketplace_description_is_a_stable_line(entry):
    text = entry["description"]
    skills = [
        p.name for p in (ROOT / entry["source"] / "skills").iterdir() if p.is_dir()
    ]
    named = [
        s for s in skills if re.search(rf"(?<![\w-]){re.escape(s)}(?![\w-])", text)
    ]
    assert not named, f"names its skills {named}: {text}"
    assert "\n" not in text and len(text) <= 200, text

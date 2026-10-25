"""ruff must never format for a newer Python than a shipped script runs on. Its target comes
from pyproject.toml, which describes the 3.14 dev tooling, while each PEP 723 script names its
own floor; at 3.14 ruff rewrote `except (A, B):` as `except A, B:`, a SyntaxError on 3.12."""

import re
import tomllib

from conftest import ROOT

FLOOR = re.compile(r'^# requires-python = ">=(\d+)\.(\d+)"', re.M)


def _version(target):
    return int(target[2]), int(target[3:])


def _ruff_targets():
    """The default target and the per-file ones, as (major, minor)."""
    config = tomllib.loads((ROOT / "pyproject.toml").read_text())
    ruff = config.get("tool", {}).get("ruff", {})
    if "target-version" in ruff:
        default = _version(ruff["target-version"])
    else:
        found = re.search(r"(\d+)\.(\d+)", config["project"]["requires-python"])
        default = int(found[1]), int(found[2])
    per_file = {
        k: _version(v) for k, v in ruff.get("per-file-target-version", {}).items()
    }
    return default, per_file


def test_ruff_targets_no_newer_python_than_any_shipped_script():
    default, per_file = _ruff_targets()
    floors = {
        str(p.relative_to(ROOT)): (int(m[1]), int(m[2]))
        for p in ROOT.glob("plugins/**/*.py")
        if (m := FLOOR.search(p.read_text()))
    }
    assert floors, "found no PEP 723 scripts"
    newer = {p: f for p, f in floors.items() if f < per_file.get(p, default)}
    assert not newer, f"ruff targets newer Python than these scripts declare: {newer}"

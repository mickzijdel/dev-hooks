"""Every Python file a plugin ships must parse on the Python it claims to support.

The plugins' scripts and hook helpers run under the user's python3, not this repo's pinned
interpreter, so a green suite on 3.14 says nothing about 3.12. `ast.parse(...,
feature_version=...)` checks the grammar of an older release from any newer one, so this
needs no second interpreter in CI.
"""

import ast
import re
import subprocess

import pytest
from conftest import ROOT

FLOOR_RE = re.compile(r'^#\s*requires-python\s*=\s*">=\s*(\d+)\.(\d+)', re.MULTILINE)
# What a shipped file must parse on when it declares nothing: the floor every PEP 723
# script in the plugins states today.
DEFAULT_FLOOR = (3, 12)


def _shipped_python():
    tracked = subprocess.run(
        ["git", "ls-files", "plugins"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.split()
    out = []
    for rel in tracked:
        path = ROOT / rel
        if rel.endswith(".py"):
            out.append(path)
            continue
        try:
            first = path.read_text(errors="ignore").split("\n", 1)[0]
        except OSError:
            continue
        if re.match(r"#!.*\b(python3?|uv run)", first):
            out.append(path)
    return out


SHIPPED = _shipped_python()


def test_found_the_shipped_scripts():
    # A test that silently parametrizes over nothing proves nothing.
    assert len(SHIPPED) >= 10, [p.name for p in SHIPPED]


@pytest.mark.parametrize("path", SHIPPED, ids=lambda p: str(p.relative_to(ROOT)))
def test_parses_on_its_declared_floor(path):
    src = path.read_text()
    m = FLOOR_RE.search(src)
    floor = (int(m.group(1)), int(m.group(2))) if m else DEFAULT_FLOOR
    ast.parse(src, filename=str(path), feature_version=floor)

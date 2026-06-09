"""Content checks for the dev-env-setup CI templates.

These guard the gitleaks job that ships in every scaffolded repo: gitleaks-action
hard-requires a GITHUB_TOKEN to scan pull_request events (without it the job fails the
PR), and the standard pins the action at its current major. A plain file-content read is
enough — no subprocess needed — so the checks stay fast and offline.
"""

import re

import pytest

from conftest import ROOT

TEMPLATES_DIR = ROOT / "skills" / "dev-env-setup" / "references" / "templates"
CI_TEMPLATES = ["ci.python.yml", "ci.ruby.yml", "ci.shell.yml"]
VERSION_FILE = ROOT / "skills" / "dev-env-setup" / "VERSION"
SKILL_MD = ROOT / "skills" / "dev-env-setup" / "SKILL.md"


@pytest.mark.parametrize("name", CI_TEMPLATES)
def test_gitleaks_job_pins_v3(name):
    text = (TEMPLATES_DIR / name).read_text()
    assert "gitleaks/gitleaks-action@v3" in text
    assert "gitleaks/gitleaks-action@v2" not in text


@pytest.mark.parametrize("name", CI_TEMPLATES)
def test_gitleaks_job_passes_github_token(name):
    text = (TEMPLATES_DIR / name).read_text()
    # The token env must sit on the gitleaks step (the action reads it to enumerate PR commits).
    assert "GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}" in text


def test_skill_doc_matches_version_stamp():
    """SKILL.md's '## The standard (vN)' header tracks the VERSION source of truth."""
    version = VERSION_FILE.read_text().strip()
    header = re.search(r"^## The standard \(v(\d+)\)", SKILL_MD.read_text(), re.M)
    assert header is not None, "SKILL.md is missing the '## The standard (vN)' header"
    assert header.group(1) == version

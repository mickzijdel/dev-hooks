"""The test-suite-tuning skill's kill_matrix.mjs, on hand-made Stryker reports."""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

SCRIPTS = (
    Path(__file__).resolve().parent.parent
    / "plugins/dev-hooks/skills/test-suite-tuning/scripts"
)

pytestmark = pytest.mark.skipif(not shutil.which("node"), reason="needs node")


def _stryker_report(tmp_path, killed_by):
    """A mutation-testing-report-schema file: three tests, one mutant per entry of killed_by."""
    mutants = [
        {
            "id": str(i),
            "status": "Killed" if k else "Survived",
            "killedBy": k,
            "coveredBy": ["0", "1", "2"],
            "mutatorName": "X",
            "location": {},
        }
        for i, k in enumerate(killed_by)
    ]
    report = {
        "files": {"src/gate.ts": {"mutants": mutants}},
        "testFiles": {
            "src/gate.test.ts": {
                "tests": [
                    {"id": "0", "name": "adult"},
                    {"id": "1", "name": "child"},
                    {"id": "2", "name": "older"},
                ]
            }
        },
    }
    path = tmp_path / "mutation.json"
    path.write_text(json.dumps(report))
    return path


def test_kill_matrix_lists_zero_kill_and_subsumed_tests(tmp_path):
    report = _stryker_report(tmp_path, [["0", "2"], ["0"], ["1"], ["1", "0"]])
    out = subprocess.run(
        ["node", str(SCRIPTS / "kill_matrix.mjs"), str(report)],
        capture_output=True,
        text=True,
        check=True,
    )
    _, subsumed = out.stdout.split("every kill also made")
    assert (
        "src/gate.test.ts > older" in subsumed
    )  # older's kills {0} are a subset of adult's
    assert "adult" not in subsumed and "child" not in subsumed
    assert "warning" not in out.stderr


def test_kill_matrix_warns_when_stryker_bailed(tmp_path):
    report = _stryker_report(tmp_path, [["0"], ["1"], []])
    out = subprocess.run(
        ["node", str(SCRIPTS / "kill_matrix.mjs"), str(report)],
        capture_output=True,
        text=True,
        check=True,
    )
    assert "--disableBail" in out.stderr
    assert "older" in out.stdout.split("every kill also made")[0]


def test_kill_matrix_refuses_a_report_without_per_test_coverage(tmp_path):
    report = _stryker_report(tmp_path, [["0"], ["1"]])
    data = json.loads(report.read_text())
    for m in data["files"]["src/gate.ts"]["mutants"]:
        del m["coveredBy"]
    report.write_text(json.dumps(data))
    out = subprocess.run(
        ["node", str(SCRIPTS / "kill_matrix.mjs"), str(report)],
        capture_output=True,
        text=True,
    )
    assert out.returncode != 0
    assert "perTest" in out.stderr


def test_kill_matrix_keeps_same_mutant_ids_in_different_files_apart(tmp_path):
    report = _stryker_report(tmp_path, [["0"], ["1"]])
    data = json.loads(report.read_text())
    # in b.ts, mutant "0" is killed only by "older": older is no longer subsumed by adult
    data["files"]["src/b.ts"] = {
        "mutants": [
            {
                "id": "0",
                "status": "Killed",
                "killedBy": ["2"],
                "coveredBy": ["0", "1", "2"],
            }
        ]
    }
    report.write_text(json.dumps(data))
    out = subprocess.run(
        ["node", str(SCRIPTS / "kill_matrix.mjs"), str(report)],
        capture_output=True,
        text=True,
        check=True,
    )
    zero, subsumed = out.stdout.split("every kill also made")
    assert "older" not in zero and "older" not in subsumed

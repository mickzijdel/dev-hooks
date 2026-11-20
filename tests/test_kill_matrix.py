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
    # older's kills {0} are a subset of adult's: the line names the test to read first
    assert (
        "src/gate.test.ts > older\n      kills 1; all also killed by: src/gate.test.ts > adult"
        in subsumed
    )
    assert "\n  src/gate.test.ts > adult" not in subsumed and "child" not in subsumed
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


def _run(report, *args):
    return subprocess.run(
        ["node", str(SCRIPTS / "kill_matrix.mjs"), *args, str(report)],
        capture_output=True,
        text=True,
        check=True,
    ).stdout


def test_kill_matrix_separates_shared_kills_from_one_test_that_makes_them_all(tmp_path):
    # older kills mutants 0 and 1; adult also kills 0, child also kills 1: no single stand-in
    report = _stryker_report(tmp_path, [["0", "2"], ["1", "2"], ["0"], ["1"]])
    _, rest = _run(report).split("every kill also made by one other test")
    subsumed, shared = rest.split("no unique kill")
    assert "older" not in subsumed
    assert "src/gate.test.ts > older\n      kills 2" in shared


def test_kill_matrix_says_what_it_left_out(tmp_path):
    report = _stryker_report(tmp_path, [["0", "2"], ["0"], ["1"]])
    data = json.loads(report.read_text())
    mutants = data["files"]["src/gate.ts"]["mutants"]
    mutants[0]["static"] = True
    wide = [str(i) for i in range(10)]
    mutants.append(
        {"id": "9", "status": "Killed", "killedBy": wide[:6], "coveredBy": wide}
    )
    report.write_text(json.dumps(data))
    out = _run(report)
    assert "static mutants: 1" in out
    assert "left out as broad: 1 killed mutants" in out


def test_kill_matrix_judges_only_the_test_files_asked_for(tmp_path):
    report = _stryker_report(tmp_path, [["0"], ["0", "3"]])
    data = json.loads(report.read_text())
    data["testFiles"]["src/page.test.tsx"] = {"tests": [{"id": "3", "name": "renders"}]}
    for m in data["files"]["src/gate.ts"]["mutants"]:
        m["coveredBy"].append("3")
    report.write_text(json.dumps(data))
    assert "tests from 2 files cover these mutants" in _run(report)
    scoped = _run(report, "--tests", r"gate\.test")
    assert "not judged: 1 tests" in scoped
    assert "\n  src/page.test.tsx > renders" not in scoped
    assert "\n  src/page.test.tsx > renders" in _run(report)


def test_kill_matrix_refuses_tests_without_a_regex(tmp_path):
    report = _stryker_report(tmp_path, [["0"]])
    done = subprocess.run(
        ["node", str(SCRIPTS / "kill_matrix.mjs"), str(report), "--tests"],
        capture_output=True,
        text=True,
    )
    assert done.returncode == 2 and "--tests needs" in done.stderr

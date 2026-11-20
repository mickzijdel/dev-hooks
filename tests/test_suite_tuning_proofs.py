"""The test-suite-tuning skill's stack-neutral scripts: hand_bug.py, ci_failures.sh and
stryker_survivors.mjs, on hand-made inputs."""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPTS = (
    Path(__file__).resolve().parent.parent
    / "plugins/dev-hooks/skills/test-suite-tuning/scripts"
)
GATE = "def adult(age):\n    return age >= 18\n"
# stands in for a test runner: prints one pytest-style line per failing check
CHECK = (
    "import sys\n"
    "from gate import adult\n"
    "failed = [n for n, ok in (('test_adult', adult(18)), ('test_child', not adult(17))) if not ok]\n"
    "for n in failed:\n"
    "    print(f'FAILED test_gate.py::{n}')\n"
    "sys.exit(1 if failed else 0)\n"
)

needs_node = pytest.mark.skipif(not shutil.which("node"), reason="needs node")
needs_jq = pytest.mark.skipif(not shutil.which("jq"), reason="needs jq")


def _hand_bug(tmp_path, bugs, command=None):
    (tmp_path / "gate.py").write_text(GATE)
    (tmp_path / "check.py").write_text(CHECK)
    (tmp_path / "bugs.json").write_text(json.dumps(bugs))
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPTS / "hand_bug.py"),
            "bugs.json",
            "--",
            *(command or [sys.executable, "check.py"]),
        ],
        cwd=tmp_path,
        capture_output=True,
        text=True,
    )


def _bug(find, replace, name="B1"):
    return {"id": name, "bug": "words", "file": "gate.py", "edits": [[find, replace]]}


def test_hand_bug_names_the_tests_that_fail_and_restores_the_file(tmp_path):
    done = _hand_bug(
        tmp_path,
        [_bug(">= 18", "> 18"), _bug("age >= 18", "age >= 18 or False", "B2")],
    )
    assert done.returncode == 0, done.stderr
    first, second = done.stdout.split("\nB2: ")
    assert "failing (1):" in first and "    test_gate.py::test_adult\n" in first
    assert "test_child" not in first
    assert "NO TEST FAILS" in second
    assert (tmp_path / "gate.py").read_text() == GATE


def test_hand_bug_refuses_an_edit_that_is_not_unique_before_any_run(tmp_path):
    done = _hand_bug(tmp_path, [_bug(">= 18", "> 18"), _bug("age", "years", "B2")])
    assert done.returncode != 0
    assert "B2" in done.stderr and "2 times" in done.stderr
    assert "B1" not in done.stdout  # nothing ran
    assert (tmp_path / "gate.py").read_text() == GATE


def test_hand_bug_refuses_a_command_that_fails_before_any_bug(tmp_path):
    done = _hand_bug(tmp_path, [_bug(">= 18", "> 18")], command=["false"])
    assert done.returncode != 0
    assert "fails (exit 1) before any bug" in done.stderr
    assert (tmp_path / "gate.py").read_text() == GATE


def test_hand_bug_reads_a_failure_once_from_both_places_vitest_prints_it(tmp_path):
    lines = (
        " × |jsdom| src/a.test.tsx > Page > saves once 500ms",
        " FAIL  |jsdom| src/a.test.tsx > Page > saves once",
    )
    runner = tmp_path / "runner.py"
    runner.write_text(
        "import sys\nfrom gate import adult\n"
        f"if not adult(18):\n    print({lines[0]!r})\n    print({lines[1]!r})\n    sys.exit(1)\n"
    )
    done = _hand_bug(
        tmp_path, [_bug(">= 18", "> 18")], command=[sys.executable, "runner.py"]
    )
    assert "failing (1):" in done.stdout
    assert "    src/a.test.tsx > Page > saves once\n" in done.stdout


GH = r"""#!/usr/bin/env bash
# a stand-in for gh: answers from the JSON files beside it, filtered with the caller's --jq
case "$1 $2" in
"run list") cat "$FAKE/runs.json" ;;
"api repos/o/r/actions/runs/"*) jq -r "$4" "$FAKE/jobs-$(basename "$(dirname "$2")").json" ;;
"api repos/o/r/check-runs/"*) cat "$FAKE/annotations-$(basename "$(dirname "$2")").json" ;;
*) echo "unexpected: $*" >&2; exit 1 ;;
esac
"""


@needs_jq
def test_ci_failures_counts_distinct_commits_and_lists_silent_failed_jobs(tmp_path):
    fake = tmp_path / "fake"
    fake.mkdir()
    runs = [
        (1, "success", "aaa", "2026-11-01T10:00:00Z"),
        (2, "failure", "bbb", "2026-11-03T10:00:00Z"),
        (3, "failure", "bbb", "2026-11-04T10:00:00Z"),
    ]
    (fake / "runs.json").write_text(
        json.dumps(
            [
                {"databaseId": i, "conclusion": c, "headSha": s, "createdAt": d}
                for i, c, s, d in runs
            ]
        )
    )
    flaky = {"annotation_level": "failure", "title": "a.test.ts > saves once"}
    twice = {"annotation_level": "failure", "title": "b.spec.ts > loads"}
    retried = {
        "annotation_level": "warning",
        "title": "Passed only on retry",
        "message": "a.test.ts > saves once\nmore",
    }
    notice = {"annotation_level": "notice", "title": "Node 20 is deprecated"}
    for run, (name, conclusion, annotations) in {
        1: ("unit", "success", [retried, notice, twice]),
        2: ("unit", "failure", [flaky, flaky, twice]),
        3: ("lint", "timed_out", [notice]),
    }.items():
        (fake / f"jobs-{run}.json").write_text(
            json.dumps(
                {"jobs": [{"id": run * 10, "name": name, "conclusion": conclusion}]}
            )
        )
        (fake / f"annotations-{run * 10}.json").write_text(json.dumps(annotations))
    gh = tmp_path / "bin/gh"
    gh.parent.mkdir()
    gh.write_text(GH)
    gh.chmod(0o755)
    done = subprocess.run(
        ["bash", str(SCRIPTS / "ci_failures.sh"), "-R", "o/r", "-n", "3", "Checks"],
        capture_output=True,
        text=True,
        env=os.environ
        | {"PATH": f"{gh.parent}:{os.environ['PATH']}", "FAKE": str(fake)},
    )
    assert done.returncode == 0, done.stderr
    out = done.stdout
    assert (
        "runs: 3 (2 not green), from 2026-11-01T10:00:00Z to 2026-11-04T10:00:00Z"
        in out
    )
    table, silent = out.split("failed jobs with no test annotation")
    rows = [line.split() for line in table.splitlines() if "saves once" in line]
    # the same failure twice in one run is one run at one commit; the retried pass is its own line
    assert ["1", "1", "2026-11-03", "failure"] in [r[:4] for r in rows]
    assert ["1", "1", "2026-11-01", "warning"] in [r[:4] for r in rows]
    assert "deprecated" not in out
    assert "lint (timed_out)" in silent and "unit" not in silent
    # b.spec.ts failed at two different head commits: the candidate
    assert [
        r[:2]
        for r in table.splitlines()
        and [line.split() for line in table.splitlines() if "loads" in line]
    ] == [["2", "2"]]
    only_spec = subprocess.run(
        [
            "bash",
            str(SCRIPTS / "ci_failures.sh"),
            "-R",
            "o/r",
            "-m",
            r"\.spec\.ts",
            "Checks",
        ],
        capture_output=True,
        text=True,
        env=os.environ
        | {"PATH": f"{gh.parent}:{os.environ['PATH']}", "FAKE": str(fake)},
    )
    assert "b.spec.ts > loads" in only_spec.stdout, only_spec
    assert "saves once" not in only_spec.stdout
    (fake / "annotations-20.json").unlink()  # that call now fails
    partial = subprocess.run(
        ["bash", str(SCRIPTS / "ci_failures.sh"), "-R", "o/r", "Checks"],
        capture_output=True,
        text=True,
        env=os.environ
        | {"PATH": f"{gh.parent}:{os.environ['PATH']}", "FAKE": str(fake)},
    )
    assert "left out: 1" in partial.stdout and "Passed only on retry" in partial.stdout


def _report(tmp_path, name, statuses):
    source = "const MONTHS = ['Jan'];\nexport const adult = (age) => age >= 18;\n"
    mutants = [
        {
            "id": str(i),
            "status": status,
            "static": i == 0,
            "mutatorName": "EqualityOperator",
            "replacement": "age > 18",
            "coveredBy": ["0"],
            "location": {
                "start": {"line": 2, "column": 31},
                "end": {"line": 2, "column": 40},
            },
        }
        for i, status in enumerate(statuses)
    ]
    report = {
        "files": {"src/gate.ts": {"source": source, "mutants": mutants}},
        "testFiles": {"src/gate.test.ts": {"tests": [{"id": "0", "name": "adult"}]}},
    }
    path = tmp_path / name
    path.write_text(json.dumps(report))
    return path


def _survivors(*args):
    return subprocess.run(
        ["node", str(SCRIPTS / "stryker_survivors.mjs"), *map(str, args)],
        capture_output=True,
        text=True,
    )


@needs_node
def test_survivors_lists_one_line_per_mutant_not_killed_and_flags_static_ones(tmp_path):
    out = _survivors(
        _report(tmp_path, "r.json", ["Survived", "Killed", "Survived"])
    ).stdout
    assert (
        "src/gate.ts: 3 mutants, Survived 2, Killed 1, score 33.3 %"
        in out.splitlines()[0]
    )
    assert "static" in out and "1, of which 1 Survived" in out
    listed = [line for line in out.splitlines() if line.startswith("  Survived")]
    assert len(listed) == 2 and "(static)" in listed[0] and "(static)" not in listed[1]
    assert (
        "src/gate.ts:2:31 #2 EqualityOperator: `age >= 18` -> `age > 18`" in listed[1]
    )
    assert "test set" in out and "src/gate.test.ts (1)" in out


@needs_node
def test_killed_diff_fails_when_a_mutant_was_swapped_at_the_same_count(tmp_path):
    before = _report(tmp_path, "before.json", ["Killed", "Killed", "Survived"])
    swapped = _report(tmp_path, "after.json", ["Killed", "Survived", "Killed"])
    done = _survivors("--killed-diff", before, swapped)
    assert done.returncode == 1
    assert "killed before: 2, after: 2, lost: 1, gained: 1" in done.stdout
    assert "lost    src/gate.ts:2:31 #1" in done.stdout
    assert _survivors("--killed-diff", before, before).returncode == 0


def test_hand_bug_appends_the_scope_list_to_the_command(tmp_path):
    (tmp_path / "scope.txt").write_text("check.py\n")
    (tmp_path / "gate.py").write_text(GATE)
    (tmp_path / "check.py").write_text(CHECK)
    (tmp_path / "bugs.json").write_text(json.dumps([_bug(">= 18", "> 18")]))
    done = subprocess.run(
        [
            sys.executable,
            str(SCRIPTS / "hand_bug.py"),
            "--list",
            "scope.txt",
            "bugs.json",
            "--",
            sys.executable,
        ],
        cwd=tmp_path,
        capture_output=True,
        text=True,
    )
    assert "    test_gate.py::test_adult\n" in done.stdout, done


def test_hand_bug_restores_bytes_and_mtime_and_gives_each_bug_its_own_second(tmp_path):
    """Bytecode caches key on whole-second mtime and size: two same-size bugs in one second
    must not share a cache entry, and the restored file must look untouched."""
    (tmp_path / "gate.py").write_bytes(b"def adult(age):\r\n    return age >= 18\r\n")
    (tmp_path / "check.py").write_text(
        "import os\nprint(int(os.stat('gate.py').st_mtime))\n" + CHECK
    )
    before = os.stat(tmp_path / "gate.py")
    bugs = [_bug(">= 18", "<= 18"), _bug(">= 18", "== 19", "B2")]
    (tmp_path / "bugs.json").write_text(json.dumps(bugs))
    done = subprocess.run(
        [
            sys.executable,
            str(SCRIPTS / "hand_bug.py"),
            "bugs.json",
            "--",
            sys.executable,
            "check.py",
        ],
        cwd=tmp_path,
        capture_output=True,
        text=True,
    )
    assert done.returncode == 0, done.stderr
    logs = Path(done.stdout.split("logs in ")[1].splitlines()[0])
    stamps = [
        (logs / f"{n}.log").read_text().splitlines()[0]
        for n in ("baseline", "B1", "B2")
    ]
    assert len(set(stamps)) == 3, stamps
    assert (
        tmp_path / "gate.py"
    ).read_bytes() == b"def adult(age):\r\n    return age >= 18\r\n"
    # newer than every mutation, so nothing built from one is taken as current
    assert int(os.stat(tmp_path / "gate.py").st_mtime) > int(stamps[2])
    assert before.st_size == os.stat(tmp_path / "gate.py").st_size


@pytest.mark.parametrize("sig", ["SIGTERM", "SIGHUP", "SIGINT"])
def test_hand_bug_restores_the_file_when_interrupted_mid_run(tmp_path, sig):
    import signal
    import time

    (tmp_path / "gate.py").write_text(GATE)
    (tmp_path / "slow.py").write_text(
        "import pathlib, time\n"
        "if '> 18' in pathlib.Path('gate.py').read_text():\n"
        "    pathlib.Path('mutated').touch()\n    time.sleep(60)\n"
    )
    (tmp_path / "bugs.json").write_text(json.dumps([_bug(">= 18", "> 18")]))
    child = subprocess.Popen(
        [
            sys.executable,
            str(SCRIPTS / "hand_bug.py"),
            "bugs.json",
            "--",
            sys.executable,
            "slow.py",
        ],
        cwd=tmp_path,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    for _ in range(200):
        if (tmp_path / "mutated").exists():
            break
        time.sleep(0.05)
    assert (tmp_path / "mutated").exists()
    child.send_signal(getattr(signal, sig))
    child.wait(timeout=20)
    assert (tmp_path / "gate.py").read_text() == GATE


def test_hand_bug_kills_a_run_that_hangs_and_restores(tmp_path):
    (tmp_path / "gate.py").write_text(GATE)
    (tmp_path / "hang.py").write_text(
        "import pathlib, time\nif '> 18' in pathlib.Path('gate.py').read_text():\n    time.sleep(60)\n"
    )
    (tmp_path / "bugs.json").write_text(json.dumps([_bug(">= 18", "> 18")]))
    done = subprocess.run(
        [
            sys.executable,
            str(SCRIPTS / "hand_bug.py"),
            "--timeout",
            "1",
            "bugs.json",
            "--",
            sys.executable,
            "hang.py",
        ],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert "TIMED OUT after 1 s" in done.stdout, done
    assert (tmp_path / "gate.py").read_text() == GATE


RUNNER_OUTPUT = {
    "jest": (
        (
            "FAIL src/format.test.js\n  ● Console\n    console.log\n"
            "  ● formatDate › handles null\n    ✕ handles null (3 ms)\n  ● adds 1 + 2\n"
        ),
        ["adds 1 + 2", "formatDate › handles null"],
    ),
    "minitest": (
        (
            "Failure:\nOrderTest#test_cancel_twice [test/models/order_test.rb:12]:\nExpected false\n\n"
            "Error:\nOrderTest#test_refund_is_recorded?:\nNoMethodError: x\n"
            "OrderTest#test_total = 0.00 s = .\n"
        ),
        ["OrderTest#test_cancel_twice", "OrderTest#test_refund_is_recorded?"],
    ),
    "pytest": (
        (
            "FAILED tests/test_calc.py::test_add[1 2] - assert 3 == 4\n"
            "ERROR tests/test_calc.py::test_db - fixture 'db' not found\n"
        ),
        ["tests/test_calc.py::test_add[1 2]", "tests/test_calc.py::test_db"],
    ),
    "vitest": (
        (
            "FAIL to connect, retrying\n × formatDate > handles null 3ms\n"
            " FAIL  src/format.test.ts > formatDate > handles null\n"
        ),
        ["src/format.test.ts > formatDate > handles null"],
    ),
    "unittest": (
        "FAIL: test_a (test_calc.CalcTest)\n----\nFAILED (failures=1)\n",
        ["test_a (test_calc.CalcTest)"],
    ),
}


@pytest.mark.parametrize("runner", RUNNER_OUTPUT)
def test_hand_bug_reads_the_failing_tests_of_each_runner(tmp_path, runner):
    output, names = RUNNER_OUTPUT[runner]
    (tmp_path / "out.txt").write_text(output)
    fake = tmp_path / "fake.py"
    fake.write_text(
        "import sys\nfrom gate import adult\n"
        "if not adult(18):\n    print(open('out.txt').read())\n    sys.exit(1)\n"
    )
    done = _hand_bug(
        tmp_path, [_bug(">= 18", "> 18")], command=[sys.executable, "fake.py"]
    )
    listed = [
        line.strip() for line in done.stdout.split("failing (")[1].splitlines()[1:]
    ]
    assert listed == sorted(names), done.stdout


def test_hand_bug_times_out_while_a_process_the_command_left_behind_lives_on(tmp_path):
    (tmp_path / "gate.py").write_text(GATE)
    (tmp_path / "daemon.py").write_text(
        "import pathlib, subprocess, sys, time\n"
        "if '> 18' in pathlib.Path('gate.py').read_text():\n"
        "    subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'], start_new_session=True)\n"
        "    time.sleep(30)\n"
    )
    (tmp_path / "bugs.json").write_text(json.dumps([_bug(">= 18", "> 18")]))
    done = subprocess.run(
        [
            sys.executable,
            str(SCRIPTS / "hand_bug.py"),
            "--timeout",
            "1",
            "bugs.json",
            "--",
            sys.executable,
            "daemon.py",
        ],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert "TIMED OUT" in done.stdout, done
    assert (tmp_path / "gate.py").read_text() == GATE


def test_hand_bug_leaves_an_already_restored_file_alone(tmp_path):
    (tmp_path / "gate.py").write_text(GATE)
    (tmp_path / "other.py").write_text("LIMIT = 18\n")
    (tmp_path / "edit.py").write_text(
        "import pathlib\n"
        "if 'LIMIT = 19' in pathlib.Path('other.py').read_text():\n"
        "    pathlib.Path('gate.py').write_text(pathlib.Path('gate.py').read_text() + '# saved\\n')\n"
    )
    bugs = [
        _bug(">= 18", "> 18"),
        {"id": "B2", "bug": "w", "file": "other.py", "edits": [["18", "19"]]},
    ]
    (tmp_path / "bugs.json").write_text(json.dumps(bugs))
    done = subprocess.run(
        [
            sys.executable,
            str(SCRIPTS / "hand_bug.py"),
            "bugs.json",
            "--",
            sys.executable,
            "edit.py",
        ],
        cwd=tmp_path,
        capture_output=True,
        text=True,
    )
    assert done.returncode == 0, done.stderr
    assert (tmp_path / "gate.py").read_text() == GATE + "# saved\n"
    assert (tmp_path / "other.py").read_text() == "LIMIT = 18\n"
    late = subprocess.run(
        [
            sys.executable,
            str(SCRIPTS / "hand_bug.py"),
            "bugs.json",
            "--timeout",
            "5",
            "--",
            "true",
        ],
        cwd=tmp_path,
        capture_output=True,
        text=True,
    )
    assert late.returncode == 2 and "options go before" in late.stderr

"""The test-suite-tuning skill's Vitest helpers and timed_run.sh, on hand-made inputs."""

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

SCRIPTS = (
    Path(__file__).resolve().parent.parent
    / "plugins/dev-hooks/skills/test-suite-tuning/scripts"
)

needs_node = pytest.mark.skipif(not shutil.which("node"), reason="needs node")


def _run(*argv, cwd=None, env=None):
    return subprocess.run(argv, capture_output=True, text=True, cwd=cwd, env=env)


def _json_report(tmp_path, durations):
    """A Vitest/Jest JSON report: one file per entry, each a list of test durations in ms."""
    report = {
        "testResults": [
            {
                "name": f"{tmp_path}/src/{name}.test.ts",
                "assertionResults": [
                    {"title": f"t{i}", "fullName": f"{name} t{i}", "duration": ms}
                    for i, ms in enumerate(times)
                ],
            }
            for name, times in durations.items()
        ]
    }
    path = tmp_path / "run.json"
    path.write_text(json.dumps(report))
    return path


@needs_node
def test_top_gives_the_share_of_the_n_slowest_tests(tmp_path):
    report = _json_report(tmp_path, {"slow": [600, 300], "fast": [50, 50]})
    out = _run("node", SCRIPTS / "vitest_top.mjs", report, "1", cwd=tmp_path).stdout
    assert "tests: 4, files: 2, summed test time: 1.0 s" in out
    assert "top 1 tests: 0.6 s = 60.0 % of summed test time" in out
    assert "over 300 ms: 1" in out
    assert "longest file: 0.9 s of tests (src/slow.test.ts)" in out
    assert "over half the 5000 ms timeout: 0" in out
    near = _run(
        "node",
        SCRIPTS / "vitest_top.mjs",
        report,
        "1",
        "--timeout",
        "1000",
        cwd=tmp_path,
    ).stdout
    assert (
        "over half the 1000 ms timeout: 1\n    600  src/slow.test.ts > slow t0" in near
    )
    no_value = _run("node", SCRIPTS / "vitest_top.mjs", report, "--timeout")
    assert no_value.returncode == 2
    slowest = out.split("slowest tests (ms):")[1].splitlines()[1]
    assert slowest.split() == ["600", "src/slow.test.ts", ">", "slow", "t0"]
    assert "src/slow.test.ts" in out.split("slowest files")[1].splitlines()[1]


@needs_node
def test_top_refuses_a_report_with_no_tests(tmp_path):
    empty = tmp_path / "empty.json"
    empty.write_text("{}")
    assert _run("node", SCRIPTS / "vitest_top.mjs", empty).returncode == 1
    assert _run("node", SCRIPTS / "vitest_top.mjs").returncode == 2


@needs_node
def test_file_costs_lists_a_file_that_imports_for_longer_than_it_tests(tmp_path):
    rows = [
        {
            "file": "src/heavy.test.ts",
            "project": "node",
            "count": 3,
            "environment": 0,
            "import": 3000,
            "setup": 100,
            "tests": 4,
        },
        {
            "file": "src/even.test.ts",
            "project": "jsdom",
            "count": 9,
            "environment": 400,
            "import": 500,
            "setup": 100,
            "tests": 900,
        },
    ]
    costs = tmp_path / "costs.json"
    costs.write_text(json.dumps(rows))
    out = _run("node", SCRIPTS / "vitest_file_costs.mjs", costs).stdout
    assert "files: 2, worker-seconds: 5.0" in out
    assert "import           3.5 s   69.9 %" in out
    assert "project jsdom: files 1" in out
    heavy = out.split("over 10x their test time: 1")[1]
    assert "src/heavy.test.ts" in heavy and "src/even.test.ts" not in heavy


@needs_node
def test_file_costs_reporter_writes_one_row_per_test_file(tmp_path):
    """Drive the reporter the way Vitest does, with stand-ins for its module objects."""
    driver = tmp_path / "drive.mjs"
    driver.write_text(
        f'import Reporter from "{SCRIPTS / "vitest_file_costs.mjs"}";\n'
        "const r = new Reporter();\n"
        "r.onTestModuleEnd({ relativeModuleId: 'a.test.ts', project: { name: 'node' },\n"
        "  diagnostic: () => ({ environmentSetupDuration: 1, collectDuration: 20, setupDuration: 3 }),\n"
        "  children: { allTests: () => [{ diagnostic: () => ({ duration: 5 }) }, { diagnostic: () => undefined }] } });\n"
        "r.onTestRunEnd();\n"
    )
    out = tmp_path / "out.json"
    done = _run(
        "node",
        driver,
        env=os.environ | {"FILE_COSTS_OUT": str(out)},
    )
    assert done.returncode == 0, done.stderr
    assert json.loads(out.read_text()) == [
        {
            "file": "a.test.ts",
            "project": "node",
            "count": 2,
            "environment": 1,
            "import": 20,
            "setup": 3,
            "tests": 5,
        }
    ]


def test_timed_run_passes_each_listed_file_as_one_argument(tmp_path):
    files = tmp_path / "scope.txt"
    files.write_text("src/app/(group)/a b.test.ts\nsrc/c.test.ts\n")
    done = _run(
        "bash",
        SCRIPTS / "timed_run.sh",
        "-l",
        files,
        tmp_path / "r1",
        "printf",
        "[%s]\\n",
        "--seed=1",
    )
    assert done.returncode == 0, done.stderr
    assert (
        "wall " in done.stdout and "exit 0" in done.stdout and "files 2" in done.stdout
    )
    assert (tmp_path / "r1.log").read_text().splitlines() == [
        "[--seed=1]",
        "[src/app/(group)/a b.test.ts]",
        "[src/c.test.ts]",
    ]


def test_timed_run_returns_the_command_exit_code_and_summary_lines(tmp_path):
    done = _run(
        "bash",
        SCRIPTS / "timed_run.sh",
        tmp_path / "r2",
        "sh",
        "-c",
        "echo ' Test Files  1 failed (1)'; echo noise; exit 3",
    )
    assert done.returncode == 3
    assert "exit 3" in done.stdout and "Test Files  1 failed" in done.stdout
    assert "noise" not in done.stdout


def test_timed_run_refuses_a_missing_or_empty_list(tmp_path):
    empty = tmp_path / "empty.txt"
    empty.write_text("")
    for arg in (tmp_path / "missing.txt", empty):
        done = _run("bash", SCRIPTS / "timed_run.sh", "-l", arg, tmp_path / "r", "true")
        assert done.returncode == 2
    assert _run("bash", SCRIPTS / "timed_run.sh", "only-a-name").returncode == 2


def test_timed_run_flags_a_run_made_at_a_load_above_the_core_count(tmp_path):
    fake = tmp_path / "bin"
    fake.mkdir()
    (fake / "uptime").write_text(
        "#!/bin/sh\necho ' 0:05  up 2:30, 1 user, load averages: 9999.50 24.02 29.30'\n"
    )
    (fake / "uptime").chmod(0o755)
    busy = _run(
        "bash",
        SCRIPTS / "timed_run.sh",
        tmp_path / "r3",
        "true",
        env=os.environ | {"PATH": f"{fake}:{os.environ['PATH']}"},
    )
    assert "load before 9999.50 on" in busy.stdout and "LOAD ABOVE CORES" in busy.stdout
    (fake / "uptime").write_text(
        "#!/bin/sh\necho ' 00:05:00 up 1 day, load average: 0.00, 0.20, 0.30'\n"
    )
    quiet = _run(
        "bash",
        SCRIPTS / "timed_run.sh",
        tmp_path / "r4",
        "true",
        env=os.environ | {"PATH": f"{fake}:{os.environ['PATH']}"},
    )
    assert (
        "load before 0.00 on" in quiet.stdout and "LOAD ABOVE CORES" not in quiet.stdout
    )


@needs_node
def test_top_leaves_skipped_tests_out_of_the_counts(tmp_path):
    report = _json_report(tmp_path, {"a": [100, 200, 300]})
    data = json.loads(report.read_text())
    data["testResults"][0]["assertionResults"].append(
        {"title": "later", "status": "skipped"}
    )
    report.write_text(json.dumps(data))
    out = _run("node", SCRIPTS / "vitest_top.mjs", report, cwd=tmp_path).stdout
    assert "tests: 3, files: 1" in out and "median test: 200.0 ms" in out


@needs_node
def test_file_costs_reports_when_called_through_a_symlink(tmp_path):
    costs = tmp_path / "costs.json"
    costs.write_text(
        json.dumps(
            [
                {
                    "file": "a.test.ts",
                    "project": "",
                    "count": 1,
                    "environment": 0,
                    "import": 5,
                    "setup": 0,
                    "tests": 5,
                }
            ]
        )
    )
    (tmp_path / "scripts").symlink_to(SCRIPTS)
    out = _run("node", tmp_path / "scripts/vitest_file_costs.mjs", costs).stdout
    assert "files: 1, worker-seconds" in out


def test_timed_run_reads_the_load_whatever_the_locale(tmp_path):
    fake = tmp_path / "bin"
    fake.mkdir()
    (fake / "uptime").write_text(
        "#!/bin/sh\n[ \"$LC_ALL\" = C ] && echo 'load averages: 2.13 1.0 1.0' || echo 'load averages: 2,13 1,0 1,0'\n"
    )
    (fake / "uptime").chmod(0o755)
    done = _run(
        "bash",
        SCRIPTS / "timed_run.sh",
        tmp_path / "r5",
        "true",
        env=os.environ
        | {"PATH": f"{fake}:{os.environ['PATH']}", "LC_ALL": "nl_NL.UTF-8"},
    )
    assert "load before 2.13 on" in done.stdout, done.stdout

"""The test-suite-tuning skill's Ruby scripts, run on a four-test Minitest fixture."""

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "plugins/dev-hooks/skills/test-suite-tuning/scripts"
FIXTURE = Path(__file__).resolve().parent / "fixtures/test_suite_tuning"


def _has_ruby_with_prism_and_minitest():
    if not shutil.which("ruby"):
        return False
    probe = subprocess.run(
        ["ruby", "-e", 'require "prism"; require "minitest"'], capture_output=True
    )
    return probe.returncode == 0


pytestmark = pytest.mark.skipif(
    not _has_ruby_with_prism_and_minitest(), reason="needs Ruby with prism and minitest"
)


@pytest.fixture
def app(tmp_path):
    shutil.copytree(FIXTURE, tmp_path / "app")
    return tmp_path / "app"


def _env(**extra):
    return {**{k: v for k, v in os.environ.items() if k != "RUBYOPT"}, **extra}


def _ruby(app, script, *args):
    return subprocess.run(
        ["ruby", str(SCRIPTS / script), *args],
        cwd=app,
        capture_output=True,
        text=True,
        env=_env(),
    )


def _record_coverage(app, *test_files):
    env = _env(RUBYOPT=f"-r{SCRIPTS / 'per_test_coverage.rb'}")
    subprocess.run(
        ["./run_tests", *(test_files or ("test/gate_test.rb",))],
        cwd=app,
        check=True,
        capture_output=True,
        env=env,
    )
    lines = [
        line
        for f in (app / "tmp/pertest").glob("cov-*.jsonl")
        for line in f.read_text().splitlines()
    ]
    return {r["test"]: r["cov"]["lib/gate.rb"] for r in map(json.loads, lines)}


def _mutate(app, *args):
    return _ruby(
        app,
        "mutate.rb",
        "lib/gate.rb",
        "--cov",
        "tmp/pertest",
        "--runner",
        "./run_tests",
        *args,
    )


def test_lists_operator_guard_and_statement_mutants(app):
    out = _ruby(app, "mutate.rb", "lib/gate.rb", "--list").stdout.splitlines()
    assert [line.split("\t", 2)[2] for line in out] == [
        "delete `return false`",
        "false -> true",
        "unless -> if",
        ">= -> <",
        ">= -> >",
        "and -> or",
    ]


def test_records_which_lines_each_test_covers(app):
    covered = _record_coverage(app)
    assert covered["GateTest#test_unknown_age_may_not_enter"] == [3]
    assert covered["GateTest#test_adult_member_may_enter"] == [3, 4]


def test_kills_every_mutant_and_restores_the_file(app):
    original = (app / "lib/gate.rb").read_text()
    _record_coverage(app)
    run = _mutate(app, "--out", "kills.json")
    assert "summary: {killed: 6}" in run.stdout, run.stdout + run.stderr
    assert (app / "lib/gate.rb").read_text() == original
    killers = {
        r["desc"]: r["killers"]
        for r in json.loads((app / "kills.json").read_text())["results"]
    }
    assert killers["delete `return false`"] == [
        "GateTest#test_unknown_age_may_not_enter"
    ]


def test_a_missing_test_shows_as_a_survivor(app):
    test = app / "test/gate_test.rb"
    test.write_text(
        "".join(
            line
            for line in test.read_text().splitlines(keepends=True)
            if "unknown_age" not in line
        )
    )
    _record_coverage(app)
    run = _mutate(app)
    assert "survived   0 killers  delete `return false`" in run.stdout, (
        run.stdout + run.stderr
    )


def test_zero_tests_run_is_an_error_not_a_survivor(app):
    _record_coverage(app)
    for f in (app / "tmp/pertest").glob("cov-*.jsonl"):
        f.write_text(f.read_text().replace("GateTest#", "NoSuchTest#"))
    run = _mutate(app)
    assert run.returncode != 0
    assert "baseline not green" in run.stderr


def test_redundancy_counts_every_recorded_test(app):
    _record_coverage(app)
    assert "tests: 4" in _ruby(app, "redundancy.rb", "tmp/pertest").stdout


def test_restores_the_file_on_sigterm_mid_run(app):
    import signal
    import time

    original = (app / "lib/gate.rb").read_text()
    _record_coverage(app)
    slow = app / "slow_tests"
    # slow only while the file is mutated, so the signal lands mid-mutant, not in the baseline
    slow.write_text(
        '#!/bin/sh\ncmp -s lib/gate.rb lib/gate.rb.mutate-orig || sleep 29.71\nexec ./run_tests "$@"\n'
    )
    slow.chmod(0o755)
    proc = subprocess.Popen(
        [
            "ruby",
            str(SCRIPTS / "mutate.rb"),
            "lib/gate.rb",
            "--cov",
            "tmp/pertest",
            "--runner",
            "./slow_tests",
        ],
        cwd=app,
        env=_env(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    deadline = time.time() + 15
    while (app / "lib/gate.rb").read_text() == original and time.time() < deadline:
        time.sleep(0.05)
    assert (app / "lib/gate.rb").read_text() != original, "never saw a mutant on disk"
    proc.send_signal(signal.SIGTERM)
    proc.wait(timeout=10)
    assert (app / "lib/gate.rb").read_text() == original
    assert not (app / "lib/gate.rb.mutate-orig").exists()
    sleepers = subprocess.run(
        ["pgrep", "-fx", "sleep 29.71"], capture_output=True, text=True
    ).stdout.split()
    assert not sleepers, "the mutant's test run was left running"


def test_refuses_to_start_over_a_leftover_backup(app):
    _record_coverage(app)
    (app / "lib/gate.rb.mutate-orig").write_text("from a killed run")
    run = _mutate(app)
    assert run.returncode != 0
    assert "an earlier run was killed" in run.stderr


def test_runs_a_test_defined_in_an_included_module(app):
    # GateTest's only test comes from a module in another file; the other tests live elsewhere
    (app / "test/support").mkdir()
    (app / "test/support/gate_cases.rb").write_text(
        "module GateCases\n  def test_unknown_age_may_not_enter = refute(Gate.open?(nil, true))\nend\n"
    )
    test = app / "test/gate_test.rb"
    lines = test.read_text().splitlines(keepends=True)
    others = "".join(line for line in lines if "unknown_age" not in line).replace(
        "GateTest", "OtherTest"
    )
    (app / "test/other_test.rb").write_text(others)
    test.write_text(
        'require "minitest/autorun"\nrequire_relative "../lib/gate"\nrequire_relative "support/gate_cases"\n\n'
        "class GateTest < Minitest::Test\n  include GateCases\nend\n"
    )
    _record_coverage(app, "test/gate_test.rb", "test/other_test.rb")
    run = _mutate(app)
    assert "killed     1 killers  delete `return false`" in run.stdout, (
        run.stdout + run.stderr
    )


def test_parses_the_rails_reporter_format(app):
    rails_style = app / "rails_style"
    rails_style.write_text(
        "#!/bin/sh\n./run_tests \"$@\" 2>&1 | sed -E 's/^ *[0-9]+\\) (Failure|Error):$/\\1:/'\n"
    )
    rails_style.chmod(0o755)
    _record_coverage(app)
    run = _ruby(
        app,
        "mutate.rb",
        "lib/gate.rb",
        "--cov",
        "tmp/pertest",
        "--runner",
        "./rails_style",
        "--out",
        "k.json",
    )
    killers = {
        r["desc"]: r["killers"]
        for r in json.loads((app / "k.json").read_text())["results"]
    }
    assert killers["delete `return false`"] == [
        "GateTest#test_unknown_age_may_not_enter"
    ], run.stdout


def test_only_merges_into_the_existing_matrix(app):
    _record_coverage(app)
    _mutate(app, "--out", "k.json")
    _mutate(app, "--only", "0", "--out", "k.json")
    assert len(json.loads((app / "k.json").read_text())["results"]) == 6


def test_a_stale_index_is_not_reported_as_survivors(app):
    _record_coverage(app)
    test = app / "test/gate_test.rb"
    test.write_text(
        "".join(
            line
            for line in test.read_text().splitlines(keepends=True)
            if "child" not in line
        )
    )
    run = _mutate(app)
    assert run.returncode != 0
    assert "partial" in run.stderr


def test_recording_survives_a_class_whose_name_method_is_not_its_name(app):
    # Faker::Company.name returns a made-up company and Faker::Name.name raises; such gems load
    # before the test framework, while the recorder still inspects every class it sees
    test = app / "test/gate_test.rb"
    test.write_text(
        'class FakeCompany\n  def self.name = raise(NameError, "uninitialized constant")\nend\n'
        + test.read_text()
    )
    covered = _record_coverage(app)
    assert covered["GateTest#test_adult_member_may_enter"] == [3, 4]


def _has_activesupport():
    return (
        subprocess.run(
            ["ruby", "-e", 'require "active_support"'], capture_output=True
        ).returncode
        == 0
    )


@pytest.mark.skipif(not _has_activesupport(), reason="needs the activesupport gem")
@pytest.mark.parametrize("script", ["event_share.rb", "route_hits.rb"])
def test_hooks_install_on_the_real_activesupport_test_case(tmp_path, script):
    # ActiveSupport autoloads TestCase: a constant lookup inside the TracePoint loads it where
    # Ruby does not trace, so the hook never installed (seen in review, Nov 2026)
    probe = (
        'require "active_support"; require "active_support/test_case"\n'
        "p ActiveSupport::TestCase.ancestors.map(&:to_s).grep(/RouteHits|EventShare/)\n"
    )
    out = subprocess.run(
        ["ruby", "-e", probe],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        env=_env(RUBYOPT=f"-r{SCRIPTS / script}"),
    )
    assert out.stdout.strip() != "[]", out.stdout + out.stderr

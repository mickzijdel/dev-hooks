# Python: pytest

Thinner than the other two stack files: the commands below were run on a small pytest suite
(pytest 8, Nov 2026), and no full trial of the six phases has been done on a Python codebase.
`test_smells.py`, `timed_run.sh` and `hand_bug.py` work as for the other stacks.
`ci_failures.sh` finds pytest failures only where a plugin writes GitHub annotations
(`pytest-github-actions-annotate-failures`); otherwise it lists the job and you read the logs.
There is no script here for cost per file, for route coverage or for a kill matrix.

## Running

Use the repo's own entry (`uv run pytest`, `tox`, `make test`) and add the flags.

| Need | pytest |
|---|---|
| Seeded random order | plugin `pytest-randomly`: `-p randomly --randomly-seed=N` (with the plugin installed, every run is shuffled and prints its seed) |
| Serial | no `-n` (plugin `pytest-xdist` is what makes a run parallel) |
| Retries off | `-p no:rerunfailures` if `pytest-rerunfailures` is installed; look for `--reruns` in the config |
| One file, one test | `FILE`, `FILE::test_name` |
| Repeat | plugin `pytest-repeat`: `--count=N` |
| Slowest tests | `--durations=25` |
| Coverage | plugin `pytest-cov`: `--cov=PKG --cov-report=json` |

A plugin that is not in the project can be added for one run without changing the project
(`uv run --with pytest-randomly --with pytest-repeat pytest ...`).

The framework notes under Inventory were not run.

## Flaky

- **Failing tests in a GitHub log:** the `FAILED path::name` lines of the short summary.
- **Order dependence:** rerun with the seed the failing run printed
  (`-p randomly --randomly-seed=N`); no bisect, so halve the file list by hand.
- Usual leaks: module-level state, a monkeypatch outside a fixture, `os.environ`, the current
  working directory, a fixture with too wide a `scope`.

## Speed

`--durations=25` prints setup and teardown apart from the call: a slow `setup` on many tests is
a fixture that wants a wider `scope`. Parallel runs need `pytest-xdist` (`-n auto`), which
splits by test unless `--dist loadfile` is set.

## Inventory

Entry points: Django `urls.py` (`manage.py show_urls` with django-extensions), Flask
`app.url_map`, FastAPI `app.routes`. Each of the three is a route list the app can give at run
time, so the table-driven refusal test of inventory.md applies.

## Mutation

`mutmut` (not tried here beyond start-up: version 3 refuses to start until its config names the
code to mutate, and it is POSIX only). `mutmut results` gives each mutant's status, not its
killers, so there is no kill matrix: find gaps with it, and prune only by the hand-applied-bug
rule.

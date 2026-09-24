"""Behaviour of the v23 version-sync gate (templates/check_version_sync.sh).

The script is copied verbatim into every standard-tracking repo and run by both the hk
`versions` step and CI's `versions` job, so it is exercised here as a subprocess against
throwaway repos rather than by reading its source. Two properties matter most and are the
ones a template edit can silently break:

* it **fails** — naming the file and both values — when two pins disagree,
* it **degrades** on absence: a repo with no Dockerfile / no compose file exits 0 and says
  what it skipped, instead of erroring or silently appearing to have checked, and
* it checks **every** Dockerfile, not just the first one found — a repo with a production
  `Dockerfile` beside a `Dockerfile.dev` had the second one unchecked for months.
"""

import subprocess
import textwrap

import pytest

from conftest import DEV_HOOKS

SCRIPT = (
    DEV_HOOKS
    / "skills"
    / "dev-env-setup"
    / "references"
    / "templates"
    / "check_version_sync.sh"
)


def build(path, files):
    """Write `files` ({relative path: content}) into `path` and install the script at
    scripts/check_version_sync.sh, where every repo carries it (the script resolves the
    repo root as its own parent's parent)."""
    for name, content in files.items():
        target = path / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(textwrap.dedent(content).lstrip("\n"))
    scripts = path / "scripts"
    scripts.mkdir(exist_ok=True)
    (scripts / "check_version_sync.sh").write_text(SCRIPT.read_text())
    return scripts / "check_version_sync.sh"


def run(path, files):
    script = build(path, files)
    return subprocess.run(
        ["bash", str(script)], capture_output=True, text=True, cwd=path
    )


RUBY_REPO = {
    ".ruby-version": "ruby-3.4.10\n",
    ".node-version": "22.4.1\n",
    "mise.toml": """
        [tools]
        ruby = "3.4.10"
        node = "22.4.1"
        yarn = "1.22.19"
        hk = "latest"
    """,
    "Dockerfile": """
        ARG RUBY_VERSION=3.4.10
        FROM ruby:$RUBY_VERSION
        ARG NODE_VERSION=22.4.1
        ARG YARN_VERSION=1.22.19
    """,
    "docker-compose.yml": """
        services:
          db:
            image: "mysql:8.4"
          cache:
            image: redis:7.4
    """,
    ".github/workflows/ci.yml": """
        jobs:
          test:
            services:
              db:
                image: mysql:8.4@sha256:deadbeef
    """,
}


def test_agreeing_pins_pass_and_say_what_they_verified(tmp_path):
    """A repo whose pins all agree exits 0 — and prints a ✓ line per comparison, because a
    gate that says nothing when it passes teaches nobody what it covers."""
    r = run(tmp_path, RUBY_REPO)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "✓ ruby 3.4.10" in r.stdout
    assert "✓ node 22.4.1" in r.stdout
    assert "✓ yarn 1.22.19" in r.stdout
    # The image digest in ci.yml must be stripped before comparing, or nothing ever matches.
    assert "✓ mysql 8.4" in r.stdout


def test_ruby_version_prefix_is_normalised(tmp_path):
    """`.ruby-version` may be bare (3.4.10) or prefixed (ruby-3.4.10) and `.node-version` may
    carry a leading v; both spellings are valid for setup-* and mise, so neither may false-fail.
    RUBY_REPO already uses the prefixed form — assert the bare form behaves identically."""
    files = dict(
        RUBY_REPO, **{".ruby-version": "3.4.10\n", ".node-version": "v22.4.1\n"}
    )
    r = run(tmp_path, files)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "✓ ruby 3.4.10" in r.stdout and "✓ node 22.4.1" in r.stdout


def test_stale_dockerfile_arg_fails_and_names_the_file(tmp_path):
    """The negative test the upgrade guide insists on: break one pin and the gate must fail,
    naming the offending file and both values — not just exit non-zero."""
    files = dict(
        RUBY_REPO,
        Dockerfile="ARG RUBY_VERSION=3.3.3\nARG NODE_VERSION=22.4.1\nARG YARN_VERSION=1.22.19\n",
    )
    r = run(tmp_path, files)
    assert r.returncode == 1
    assert "✗ Dockerfile ARG RUBY_VERSION (3.3.3) != .ruby-version (3.4.10)" in r.stdout
    # The pins that still agree keep reporting, so one failure doesn't hide the rest.
    assert "✓ node 22.4.1" in r.stdout


def test_service_tag_drift_between_prod_and_ci_fails(tmp_path):
    """The drift that motivated the gate: CI green against a database server nobody deploys."""
    files = dict(
        RUBY_REPO,
        **{
            "docker-compose.yml": 'services:\n  db:\n    image: "mysql:8.3"\n',
        },
    )
    r = run(tmp_path, files)
    assert r.returncode == 1
    assert "✗ mysql tags disagree" in r.stdout
    assert "docker-compose.yml (8.3)" in r.stdout
    assert ".github/workflows/ci.yml (8.4)" in r.stdout


def test_service_in_only_one_file_is_reported_not_failed(tmp_path):
    """An image named in one file alone is not drift — CI may legitimately not need Redis."""
    r = run(tmp_path, RUBY_REPO)
    assert r.returncode == 0
    assert "- redis: pinned only in docker-compose.yml (7.4)" in r.stdout


def test_absent_files_are_skipped_out_loud(tmp_path):
    """A JS repo with no Dockerfile and no compose file must exit 0 — and must say so, so its
    pass never looks like more coverage than it is."""
    r = run(
        tmp_path,
        {
            ".node-version": "22.4.1\n",
            "mise.toml": '[tools]\nnode = "22.4.1"\n',
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "- no Dockerfile, so no image-build ARGs to cross-check" in r.stdout
    assert "- no compose / deploy / workflow files, nothing to cross-check" in r.stdout
    assert "✓ node 22.4.1" in r.stdout


def test_empty_repo_passes(tmp_path):
    """Nothing to check at all is a pass, not a crash."""
    r = run(tmp_path, {})
    assert r.returncode == 0, r.stdout + r.stderr
    assert "- no mise.toml" in r.stdout


def test_floating_mise_spec_is_not_compared(tmp_path):
    """`node = "latest"` names no fixed version (mise.lock is its real pin), so it must be
    reported as skipped rather than diffed against .node-version."""
    r = run(
        tmp_path,
        {
            ".node-version": "22.4.1\n",
            "mise.toml": '[tools]\nnode = "latest"\n',
            "Dockerfile": "ARG NODE_VERSION=22.4.1\n",
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert 'mise.toml spec is "latest"' in r.stdout
    assert "✓ node 22.4.1" in r.stdout


def test_mise_table_form_and_multi_manifest_repo(tmp_path):
    """The Kamal shape: `ruby = { version = … }` in mise.toml, a config/deploy.yml plus a
    devcontainer compose, no ARG NODE_VERSION at all. Every one of those must work, because
    forcing a Dockerfile style on adopters is explicitly out of scope."""
    r = run(
        tmp_path,
        {
            ".ruby-version": "4.0.2",  # no trailing newline, as written by some tools
            ".node-version": "24.13.0\n",
            "mise.toml": """
                [tools]
                ruby = { version = "4.0.2", compile = false }
                node = "24.13.0"
            """,
            "Dockerfile": "ARG RUBY_VERSION=4.0.2\nRUN setup_24.x\n",
            "config/deploy.yml": """
                image: acme/app
                accessories:
                  mysql:
                    image: mysql:8.4
                #   valkey:
                #     image: valkey/valkey:8
            """,
            ".devcontainer/compose.yaml": "services:\n  db:\n    image: mysql:8.4\n",
            ".github/workflows/ci.yml": "jobs:\n  t:\n    services:\n      db:\n        image: mysql:8.4\n",
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "✓ ruby 4.0.2" in r.stdout
    assert "✓ node 24.13.0" in r.stdout
    assert "✓ mysql 8.4" in r.stdout
    # An untagged image pins nothing and a commented-out one isn't real config.
    assert "acme/app" not in r.stdout
    assert "valkey" not in r.stdout


def test_package_manager_pin_is_compared(tmp_path):
    """package.json's `packageManager` is corepack's pin and drifts from a Dockerfile ARG
    exactly like every other version does."""
    r = run(
        tmp_path,
        {
            "package.json": '{"name": "x", "packageManager": "pnpm@9.1.0+sha512.abc"}\n',
            "Dockerfile": "ARG PNPM_VERSION=9.2.0\n",
        },
    )
    assert r.returncode == 1
    assert (
        "✗ Dockerfile ARG PNPM_VERSION (9.2.0) != package.json packageManager (9.1.0)"
        in r.stdout
    )


def test_go_mod_directive_is_not_compared(tmp_path):
    """go.mod's `go` directive is a *minimum*, not a pin, and is routinely older than the
    toolchain — comparing it would fail healthy repos."""
    r = run(
        tmp_path,
        {
            "go.mod": "module example.com/x\n\ngo 1.21\n",
            ".go-version": "1.22.5\n",
            "mise.toml": '[tools]\ngo = "1.22.5"\n',
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "✓ go 1.22.5" in r.stdout
    assert "go.mod" not in r.stdout


@pytest.mark.parametrize(
    "image",
    ["${DB_IMAGE}", "{{ db_image }}", "<%= db_image %>"],
    ids=["compose-var", "mustache", "erb"],
)
def test_templated_images_are_ignored(tmp_path, image):
    """A templated `image:` names no concrete tag; treating the template text as one would
    produce a permanent, unfixable failure."""
    r = run(
        tmp_path,
        {
            "docker-compose.yml": f"services:\n  db:\n    image: {image}\n",
            ".github/workflows/ci.yml": "jobs:\n  t:\n    services:\n      db:\n        image: mysql:8.4\n",
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "✗" not in r.stdout


# ── Every Dockerfile, not just the first ─────────────────────────────────────────────
# The gate used to `break` on the first of `Dockerfile Containerfile`, so a repo with more than
# one had all but one unchecked. In one repo that let `Dockerfile.dev` sit on node:22 for months
# while `.node-version`, `mise.toml` and the production `Dockerfile` all said 24 — with this gate
# green throughout, and that repo's own docs claiming Node 24 "everywhere".

TWO_DOCKERFILES = {
    ".node-version": "24.19.0\n",
    "mise.toml": '[tools]\nnode = "24.19.0"\n',
    "Dockerfile": "ARG NODE_VERSION=24.19.0\nFROM node:$NODE_VERSION-alpine\n",
    "Dockerfile.dev": "ARG NODE_VERSION=24.19.0\nFROM node:$NODE_VERSION-alpine\n",
}


def test_every_dockerfile_is_named_when_they_agree(tmp_path):
    """Both files are compared and both are named, so the pass says how much it covered."""
    r = run(tmp_path, TWO_DOCKERFILES)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "Dockerfile ARG NODE_VERSION" in r.stdout
    assert "Dockerfile.dev ARG NODE_VERSION" in r.stdout


def test_second_dockerfile_alone_disagreeing_fails(tmp_path):
    """The regression this fix exists for: the *first* Dockerfile agrees with every other pin,
    so a gate that stops at the first one passes. It must fail, and name Dockerfile.dev."""
    files = dict(
        TWO_DOCKERFILES,
        **{
            "Dockerfile.dev": "ARG NODE_VERSION=22.11.0\nFROM node:$NODE_VERSION-alpine\n"
        },
    )
    r = run(tmp_path, files)
    assert r.returncode == 1
    assert (
        "✗ Dockerfile.dev ARG NODE_VERSION (22.11.0) != .node-version (24.19.0)"
        in r.stdout
    )


def test_containerfile_variants_are_checked_too(tmp_path):
    """Podman's spelling gets the same treatment — `Containerfile` was already the fallback,
    so `Containerfile.dev` must not be the new blind spot."""
    r = run(
        tmp_path,
        {
            ".node-version": "24.19.0\n",
            "mise.toml": '[tools]\nnode = "24.19.0"\n',
            "Containerfile": "ARG NODE_VERSION=24.19.0\n",
            "Containerfile.dev": "ARG NODE_VERSION=20.1.0\n",
        },
    )
    assert r.returncode == 1
    assert "✗ Containerfile.dev ARG NODE_VERSION (20.1.0)" in r.stdout


def test_backup_and_template_dockerfiles_are_not_checked(tmp_path):
    """`Dockerfile.bak` / `.orig` are editor and VCS leftovers, not build inputs, and a
    `Dockerfile.j2` pins a placeholder no value could ever satisfy — comparing any of them
    would fail a healthy repo with no correct fix available. `.dockerignore` shares no prefix
    with either glob, so it can't be picked up at all."""
    r = run(
        tmp_path,
        {
            ".node-version": "24.19.0\n",
            "mise.toml": '[tools]\nnode = "24.19.0"\n',
            "Dockerfile": "ARG NODE_VERSION=24.19.0\n",
            ".dockerignore": "node_modules\n",
            "Dockerfile.bak": "ARG NODE_VERSION=18.0.0\n",
            "Dockerfile.dev.orig": "ARG NODE_VERSION=18.0.0\n",
            "Dockerfile.j2": "ARG NODE_VERSION={{ node_version }}\n",
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "✓ node 24.19.0" in r.stdout
    for ignored in (".bak", ".orig", ".j2", ".dockerignore"):
        assert ignored not in r.stdout, f"{ignored} must not be compared"


def test_single_dockerfile_is_listed_once(tmp_path):
    """`Dockerfile` needs a literal dot to match `Dockerfile.*`, so the two globs can never
    both yield it — but an unmatched `Dockerfile.*` also stays literal in POSIX sh, and only
    the `[ -f ]` guard drops it. Assert neither shows up in the output."""
    r = run(
        tmp_path,
        {
            ".node-version": "24.19.0\n",
            "mise.toml": '[tools]\nnode = "24.19.0"\n',
            "Dockerfile": "ARG NODE_VERSION=24.19.0\n",
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert r.stdout.count("Dockerfile ARG NODE_VERSION") == 1
    assert "Dockerfile.*" not in r.stdout


def test_one_dockerfile_declaring_two_defaults_is_reported_as_conflicting(tmp_path):
    """A multi-stage build that redeclares `ARG NODE_VERSION` with a *different* default pins
    two versions in one file, and no comparison against the other pins can be meaningful. The
    branch that says so was unreachable until the ARG reader stopped deleting the newline
    between values along with the surrounding whitespace: the two defaults arrived concatenated
    as one line, so the value reported was the nonsense `24.19.020.0.0`."""
    r = run(
        tmp_path,
        {
            ".node-version": "24.19.0\n",
            "mise.toml": '[tools]\nnode = "24.19.0"\n',
            "Dockerfile": "ARG NODE_VERSION=24.19.0\nFROM node:$NODE_VERSION\nARG NODE_VERSION=20.0.0\n",
        },
    )
    assert r.returncode == 1
    assert (
        "✗ Dockerfile declares ARG NODE_VERSION with conflicting defaults: 20.0.0 24.19.0"
        in r.stdout
    )
    assert "24.19.020.0.0" not in r.stdout


def test_crlf_dockerfile_still_compares(tmp_path):
    """The reader must keep stripping the CR of a CRLF-checked-out Dockerfile, or every pin in
    it compares as `24.19.0\\r` and never matches."""
    r = run(
        tmp_path,
        {
            ".node-version": "24.19.0\n",
            "mise.toml": '[tools]\nnode = "24.19.0"\n',
            "Dockerfile": "ARG NODE_VERSION=24.19.0\r\nFROM node:$NODE_VERSION\r\n",
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "✓ node 24.19.0" in r.stdout


# ── v26: mise.lock resolves a floating spec, and CI setup steps must read the pin ──────


def lock(**tools):
    return "".join(
        f'[[tools.{name}]]\nversion = "{ver}"\nbackend = "core:{name}"\n\n'
        for name, ver in tools.items()
    )


def workflow(steps, job="test"):
    """A one-job workflow whose steps are the given YAML snippets."""
    body = "".join(
        textwrap.indent(textwrap.dedent(s).strip("\n"), "      ") + "\n" for s in steps
    )
    return f"jobs:\n  {job}:\n    runs-on: ubuntu-latest\n    steps:\n{body}"


CHECKOUT = "- uses: actions/checkout@0000000000000000000000000000000000000000 # v7.0.0"


def test_floating_mise_spec_resolves_through_mise_lock(tmp_path):
    """`python = "latest"` names no version, but mise.lock records the exact release local and
    mise-action install, so that release is what the other pins must agree with."""
    r = run(
        tmp_path,
        {
            ".python-version": "3.14.6\n",
            "mise.toml": '[tools]\npython = "latest"\n',
            "mise.lock": lock(python="3.14.6"),
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "✓ python 3.14.6 — .python-version, mise.lock python" in r.stdout


def test_mise_lock_drift_from_a_version_file_fails(tmp_path):
    r = run(
        tmp_path,
        {
            ".node-version": "22.4.1\n",
            "mise.toml": '[tools]\nnode = "lts"\n',
            "mise.lock": lock(node="24.11.0"),
        },
    )
    assert r.returncode == 1, r.stdout
    assert "✗ mise.lock node (24.11.0) != .node-version (22.4.1)" in r.stdout


def test_setup_step_reading_the_pin_file_passes(tmp_path):
    r = run(
        tmp_path,
        {
            ".node-version": "24.11.0\n",
            ".github/workflows/ci.yml": workflow(
                [
                    CHECKOUT,
                    """
                    - uses: actions/setup-node@0000000000000000000000000000000000000000 # v6
                      with:
                        node-version-file: .node-version
                    """,
                ]
            ),
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert (
        "✓ .github/workflows/ci.yml test: actions/setup-node reads .node-version"
        in r.stdout
    )


@pytest.mark.parametrize("spec", ["lts/*", "latest", "22.x", "'*'"])
def test_floating_setup_version_fails(tmp_path, spec):
    """`node-version: lts/*` means CI runs whatever is newest on the day, not what local pins."""
    r = run(
        tmp_path,
        {
            ".node-version": "24.11.0\n",
            ".github/workflows/ci.yml": workflow(
                [
                    f"""
                    - uses: actions/setup-node@0000000000000000000000000000000000000000 # v6
                      with:
                        node-version: {spec}
                    """
                ]
            ),
        },
    )
    assert r.returncode == 1, r.stdout
    assert (
        "✗ .github/workflows/ci.yml test: actions/setup-node node-version" in r.stdout
    )
    assert "floats" in r.stdout


def test_literal_setup_version_joins_the_comparison(tmp_path):
    """A hardcoded version is one more pin: it must match the others, and the failure names the
    workflow line that carries it."""
    r = run(
        tmp_path,
        {
            ".python-version": "3.14.6\n",
            ".github/workflows/ci.yml": workflow(
                [
                    """
                    - uses: actions/setup-python@0000000000000000000000000000000000000000 # v6
                      with:
                        python-version: "3.12.4"
                    """
                ]
            ),
        },
    )
    assert r.returncode == 1, r.stdout
    assert (
        "✗ .github/workflows/ci.yml test actions/setup-python (3.12.4) != .python-version (3.14.6)"
        in r.stdout
    )


def test_matrix_expression_fails(tmp_path):
    """The standard tests one version, the pinned one; an expression can't be checked against it."""
    r = run(
        tmp_path,
        {
            ".python-version": "3.14.6\n",
            ".github/workflows/ci.yml": workflow(
                [
                    """
                    - uses: astral-sh/setup-uv@0000000000000000000000000000000000000000 # v8
                      with:
                        enable-cache: true
                        python-version: ${{ matrix.python }}
                    """
                ]
            ),
        },
    )
    assert r.returncode == 1, r.stdout
    assert "astral-sh/setup-uv python-version is an expression" in r.stdout


def test_setup_step_naming_no_version_fails(tmp_path):
    r = run(
        tmp_path,
        {
            ".github/workflows/ci.yml": workflow(
                [
                    "- uses: actions/setup-node@0000000000000000000000000000000000000000 # v6"
                ]
            ),
        },
    )
    assert r.returncode == 1, r.stdout
    assert (
        "✗ .github/workflows/ci.yml test: actions/setup-node names no version"
        in r.stdout
    )


def test_setup_uv_alone_runs_the_runners_python(tmp_path):
    """setup-uv installs uv, not Python: with nothing else in the job, uv takes the runner's
    system python3 — the drift that let one repo's CI test 3.12 while local ran 3.14."""
    r = run(
        tmp_path,
        {
            "mise.toml": '[tools]\npython = "latest"\nuv = "latest"\n',
            "mise.lock": lock(python="3.14.6", uv="0.9.0"),
            ".github/workflows/ci.yml": workflow(
                [
                    """
                    - uses: astral-sh/setup-uv@0000000000000000000000000000000000000000 # v8
                      with:
                        enable-cache: true
                    """
                ]
            ),
        },
    )
    assert r.returncode == 1, r.stdout
    assert (
        "✗ .github/workflows/ci.yml test: astral-sh/setup-uv names no Python"
        in r.stdout
    )


@pytest.mark.parametrize(
    "mise_step",
    [
        "- uses: jdx/mise-action@0000000000000000000000000000000000000000 # v4",
        """
        - uses: jdx/mise-action@0000000000000000000000000000000000000000 # v4
          with:
            install_args: python uv
        """,
    ],
)
def test_mise_action_installing_python_satisfies_uv(tmp_path, mise_step):
    r = run(
        tmp_path,
        {
            "mise.toml": '[tools]\npython = "latest"\nuv = "latest"\n',
            "mise.lock": lock(python="3.14.6", uv="0.9.0"),
            ".github/workflows/ci.yml": workflow(
                [
                    mise_step,
                    "- uses: astral-sh/setup-uv@0000000000000000000000000000000000000000 # v8",
                ]
            ),
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert (
        "✓ .github/workflows/ci.yml test: python from mise.toml via mise-action"
        in r.stdout
    )


def test_mise_action_limited_to_other_tools_does_not_count(tmp_path):
    """`install_args: shellcheck` installs only shellcheck; Python still comes from the runner."""
    r = run(
        tmp_path,
        {
            "mise.toml": '[tools]\npython = "latest"\nshellcheck = "latest"\n',
            ".github/workflows/ci.yml": workflow(
                [
                    """
                    - uses: jdx/mise-action@0000000000000000000000000000000000000000 # v4
                      with:
                        install_args: shellcheck
                    """,
                    "- uses: astral-sh/setup-uv@0000000000000000000000000000000000000000 # v8",
                ]
            ),
        },
    )
    assert r.returncode == 1, r.stdout
    assert "astral-sh/setup-uv names no Python" in r.stdout


def test_mise_action_in_another_job_does_not_count(tmp_path):
    wf = workflow(
        ["- uses: jdx/mise-action@0000000000000000000000000000000000000000 # v4"],
        job="lint",
    ) + workflow(
        ["- uses: astral-sh/setup-uv@0000000000000000000000000000000000000000 # v8"]
    ).removeprefix("jobs:\n")
    r = run(
        tmp_path,
        {"mise.toml": '[tools]\npython = "latest"\n', ".github/workflows/ci.yml": wf},
    )
    assert r.returncode == 1, r.stdout
    assert "ci.yml test: astral-sh/setup-uv names no Python" in r.stdout


def test_python_version_file_satisfies_setup_python_and_uv(tmp_path):
    """Both actions read .python-version on their own when given no version input."""
    r = run(
        tmp_path,
        {
            ".python-version": "3.14.6\n",
            ".github/workflows/ci.yml": workflow(
                [
                    "- uses: actions/setup-python@0000000000000000000000000000000000000000 # v6",
                    "- uses: astral-sh/setup-uv@0000000000000000000000000000000000000000 # v8",
                ]
            ),
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "actions/setup-python reads .python-version" in r.stdout
    assert "astral-sh/setup-uv reads .python-version" in r.stdout


def test_setup_ruby_reading_a_missing_file_fails(tmp_path):
    r = run(
        tmp_path,
        {
            ".github/workflows/ci.yml": workflow(
                [
                    """
                    - uses: ruby/setup-ruby@0000000000000000000000000000000000000000 # v1
                      with:
                        ruby-version: .ruby-version
                    """
                ]
            ),
        },
    )
    assert r.returncode == 1, r.stdout
    assert "ruby/setup-ruby reads .ruby-version, which does not exist" in r.stdout


def test_run_block_lines_do_not_start_steps(tmp_path):
    """A `- ` inside a run: block is script text, not a new step, and must not end the one the
    parser is in — nor may a `uses:` quoted in a script count as a step."""
    r = run(
        tmp_path,
        {
            ".node-version": "24.11.0\n",
            ".github/workflows/ci.yml": workflow(
                [
                    """
                    - name: notes
                      run: |
                        echo "- uses: actions/setup-node@v6"
                        echo "- item"
                    """,
                    """
                    - name: Node
                      uses: actions/setup-node@0000000000000000000000000000000000000000 # v6
                      with:
                        node-version-file: .node-version
                    """,
                ]
            ),
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "actions/setup-node reads .node-version" in r.stdout


def test_workflow_without_setup_steps_is_quiet(tmp_path):
    r = run(tmp_path, RUBY_REPO)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "no language setup steps" in r.stdout


@pytest.mark.parametrize("stack", ["ruby", "js", "python", "go", "shell"])
def test_each_stacks_templates_pass_their_own_gate(tmp_path, stack):
    """A repo freshly set up from the templates must pass the gate the templates ship: every CI
    setup step reads the pin (mise.toml via mise-action, or .ruby-version for Ruby)."""
    templates = SCRIPT.parent
    files = {
        "mise.toml": (templates / f"mise.{stack}.toml").read_text(),
        ".github/workflows/ci.yml": (templates / f"ci.{stack}.yml").read_text(),
    }
    if stack == "ruby":
        files[".ruby-version"] = "3.4.10\n"
    r = run(tmp_path, files)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "✗" not in r.stdout


def test_mise_only_workflow_says_where_the_toolchain_comes_from(tmp_path):
    r = run(
        tmp_path,
        {
            "mise.toml": '[tools]\npython = "latest"\n',
            ".github/workflows/ci.yml": workflow(
                [
                    "- uses: jdx/mise-action@0000000000000000000000000000000000000000 # v4"
                ]
            ),
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "install their toolchain with mise-action" in r.stdout


# ── Review findings on the v26 gate ─────────────────────────────────────────────────
SETUP_UV = "- uses: astral-sh/setup-uv@0000000000000000000000000000000000000000 # v8"
SETUP_PY = "- uses: actions/setup-python@0000000000000000000000000000000000000000 # v6"


def node_step(with_block):
    return (
        "- uses: actions/setup-node@0000000000000000000000000000000000000000 # v6\n"
        + textwrap.indent(textwrap.dedent(with_block).strip("\n"), "  ")
    )


@pytest.mark.parametrize(
    "files",
    [
        {
            ".python-version": "3.12\n",
            "mise.toml": '[tools]\npython = "3.12"\n',
            "mise.lock": lock(python="3.12.12"),
        },
        {
            ".python-version": "3.12\n",
            "mise.toml": '[tools]\npython = "latest"\n',
            "mise.lock": lock(python="3.12.12"),
        },
    ],
)
def test_major_minor_pin_read_by_ci_floats(tmp_path, files):
    """`3.12` in the file CI reads resolves to the newest 3.12.x there, while mise.lock pins
    3.12.12 locally: the gate passed with local and CI on different patch releases."""
    r = run(
        tmp_path,
        {**files, ".github/workflows/ci.yml": workflow([SETUP_UV])},
    )
    assert r.returncode == 1, r.stdout
    assert "astral-sh/setup-uv reads .python-version (3.12)" in r.stdout
    assert "newest 3.12" in r.stdout


def test_major_minor_mise_spec_agrees_with_its_lock(tmp_path):
    """`python = "3.12"` is a spec that 3.12.12 satisfies — not a disagreement — and the lock
    joins the comparison as the exact release."""
    r = run(
        tmp_path,
        {
            ".python-version": "3.12.12\n",
            "mise.toml": '[tools]\npython = "3.12"\n',
            "mise.lock": lock(python="3.12.12"),
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert (
        "✓ python 3.12.12 — .python-version, mise.toml python, mise.lock python"
        in r.stdout
    )


def test_exact_mise_spec_disagreeing_with_lock_fails(tmp_path):
    r = run(
        tmp_path,
        {
            "mise.toml": '[tools]\nnode = "24.10.0"\n',
            "mise.lock": lock(node="24.11.0"),
            ".node-version": "24.10.0\n",
        },
    )
    assert r.returncode == 1, r.stdout
    assert "mise.lock node (24.11.0)" in r.stdout


def test_other_version_file_contents_are_compared(tmp_path):
    """`.nvmrc` is not the tool's usual pin file, but CI reads it: its contents must agree."""
    r = run(
        tmp_path,
        {
            ".node-version": "24.11.0\n",
            ".nvmrc": "20.1.0\n",
            ".github/workflows/ci.yml": workflow(
                [node_step("with:\n  node-version-file: .nvmrc")]
            ),
        },
    )
    assert r.returncode == 1, r.stdout
    assert "(20.1.0) != .node-version (24.11.0)" in r.stdout


@pytest.mark.parametrize(
    "extra, step",
    [
        (
            {"package.json": '{"engines": {"node": ">=18"}}\n'},
            node_step("with:\n  node-version-file: package.json"),
        ),
        (
            {"pyproject.toml": '[project]\nrequires-python = ">=3.10"\n'},
            "- uses: actions/setup-python@0000000000000000000000000000000000000000 # v6\n"
            "  with:\n    python-version-file: pyproject.toml",
        ),
    ],
)
def test_range_files_cannot_pin_ci(tmp_path, extra, step):
    r = run(tmp_path, {**extra, ".github/workflows/ci.yml": workflow([step])})
    assert r.returncode == 1, r.stdout
    assert "a range" in r.stdout


def test_tool_versions_line_is_compared(tmp_path):
    r = run(
        tmp_path,
        {
            ".ruby-version": "3.4.1\n",
            ".tool-versions": "nodejs 24.11.0\nruby 3.3.0\n",
            ".github/workflows/ci.yml": workflow(
                [
                    "- uses: ruby/setup-ruby@0000000000000000000000000000000000000000 # v1\n"
                    "  with:\n    ruby-version: .tool-versions"
                ]
            ),
        },
    )
    assert r.returncode == 1, r.stdout
    assert "(3.3.0) != .ruby-version (3.4.1)" in r.stdout


def test_compact_job_level_list_does_not_swallow_steps(tmp_path):
    """`needs:` written with its dash at the key's own indent used to be taken as the step
    list, after which every real step merged into one and a floating setup step vanished."""
    wf = """
        jobs:
          test:
            needs:
            - build
            runs-on: ubuntu-latest
            steps:
              - uses: actions/checkout@0000000000000000000000000000000000000000 # v7
              - uses: actions/setup-node@0000000000000000000000000000000000000000 # v6
                with:
                  node-version: lts/*
              - uses: actions/cache@0000000000000000000000000000000000000000 # v6
        """
    r = run(tmp_path, {".node-version": "24.11.0\n", ".github/workflows/ci.yml": wf})
    assert r.returncode == 1, r.stdout
    assert "floats" in r.stdout


def test_setup_uv_after_setup_python_uses_its_interpreter(tmp_path):
    r = run(
        tmp_path,
        {
            "mise.toml": '[tools]\npython = "3.12.4"\n',
            ".github/workflows/ci.yml": workflow(
                [
                    SETUP_PY + '\n  with:\n    python-version: "3.12.4"',
                    SETUP_UV,
                ]
            ),
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "setup-uv uses setup-python's interpreter" in r.stdout


@pytest.mark.parametrize(
    "files, with_block",
    [
        ({".ruby-version": "3.4.1\n"}, "\n  with:\n    ruby-version: default"),
        ({"mise.toml": '[tools]\nruby = "3.4.1"\n'}, ""),
        ({".tool-versions": "ruby 3.4.1\n"}, ""),
    ],
)
def test_setup_ruby_defaults_are_pins(tmp_path, files, with_block):
    """setup-ruby with no input (or `default`) reads .ruby-version, then .tool-versions, then
    mise.toml — each is a real pin."""
    step = (
        "- uses: ruby/setup-ruby@0000000000000000000000000000000000000000 # v1"
        + with_block
    )
    r = run(tmp_path, {**files, ".github/workflows/ci.yml": workflow([step])})
    assert r.returncode == 0, r.stdout + r.stderr
    assert "✗" not in r.stdout


def test_empty_input_does_not_shift_columns(tmp_path):
    r = run(
        tmp_path,
        {
            ".python-version": "3.14.6\n",
            ".github/workflows/ci.yml": workflow(
                [
                    SETUP_PY
                    + "\n  with:\n    python-version: ''\n    python-version-file: .python-version"
                ]
            ),
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "reads .python-version" in r.stdout


def test_flow_style_with_is_parsed(tmp_path):
    r = run(
        tmp_path,
        {
            ".node-version": "22.4.1\n",
            ".github/workflows/ci.yml": workflow(
                [node_step("with: {node-version: 20.1.0}")]
            ),
        },
    )
    assert r.returncode == 1, r.stdout
    assert "(20.1.0) != .node-version (22.4.1)" in r.stdout


def test_block_scalar_install_args_are_read(tmp_path):
    r = run(
        tmp_path,
        {
            "mise.toml": '[tools]\npython = "latest"\nuv = "latest"\n',
            ".github/workflows/ci.yml": workflow(
                [
                    "- uses: jdx/mise-action@0000000000000000000000000000000000000000 # v4\n"
                    "  with:\n    install_args: >-\n      python\n      uv",
                    SETUP_UV,
                ]
            ),
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "python from mise.toml via mise-action" in r.stdout


def test_unquoted_float_version_is_flagged(tmp_path):
    """YAML reads an unquoted 3.10 as the float 3.1."""
    r = run(
        tmp_path,
        {
            ".github/workflows/ci.yml": workflow(
                [SETUP_PY + "\n  with:\n    python-version: 3.10"]
            ),
        },
    )
    assert r.returncode == 1, r.stdout
    assert "quote it" in r.stdout


def test_literal_pin_is_listed_under_ci_setup_steps(tmp_path):
    r = run(
        tmp_path,
        {
            ".python-version": "3.14.6\n",
            ".github/workflows/ci.yml": workflow(
                [SETUP_PY + '\n  with:\n    python-version: "3.14.6"']
            ),
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    ci = r.stdout.split("CI setup steps:", 1)[1]
    assert "actions/setup-python pins 3.14.6" in ci


def test_composite_actions_are_scanned(tmp_path):
    action = """
        name: setup
        runs:
          using: composite
          steps:
            - uses: actions/setup-node@0000000000000000000000000000000000000000 # v6
              with:
                node-version: lts/*
        """
    r = run(
        tmp_path,
        {
            ".node-version": "24.11.0\n",
            ".github/actions/setup/action.yml": action,
            ".github/workflows/ci.yml": workflow(["- uses: ./.github/actions/setup"]),
        },
    )
    assert r.returncode == 1, r.stdout
    assert ".github/actions/setup/action.yml" in r.stdout
    assert "floats" in r.stdout


def test_ruby_template_node_drift_against_a_dockerfile_is_reported(tmp_path):
    """Documented v26 behaviour: a floating mise spec now compares through mise.lock, so a
    Dockerfile building on an older Node than local/CI use is drift, not a skip."""
    r = run(
        tmp_path,
        {
            ".ruby-version": "3.4.7\n",
            "mise.toml": '[tools]\nnode = "latest"\n',
            "mise.lock": lock(node="24.11.0"),
            "Dockerfile": "ARG RUBY_VERSION=3.4.7\nARG NODE_VERSION=22.12.0\n",
        },
    )
    assert r.returncode == 1, r.stdout
    assert "Dockerfile ARG NODE_VERSION (22.12.0)" in r.stdout


# ── Second review ────────────────────────────────────────────────────────────────────
@pytest.mark.parametrize(
    "files",
    [
        {  # a loose file first hid mise vs Docker
            ".node-version": "24\n",
            "mise.toml": '[tools]\nnode = "24.10.0"\n',
            "Dockerfile": "ARG NODE_VERSION=24.11.0\n",
        },
        {  # a lock that does not satisfy the mise spec
            ".python-version": "3\n",
            "mise.toml": '[tools]\npython = "3.12"\n',
            "mise.lock": lock(python="3.13.1"),
        },
    ],
)
def test_every_pair_of_pins_is_compared(tmp_path, files):
    r = run(tmp_path, files)
    assert r.returncode == 1, r.stdout


def test_ci_literal_against_a_different_mise_release_fails(tmp_path):
    r = run(
        tmp_path,
        {
            ".python-version": "3.12\n",
            "mise.toml": '[tools]\npython = "3.12.5"\n',
            ".github/workflows/ci.yml": workflow(
                [SETUP_PY + '\n  with:\n    python-version: "3.12.4"']
            ),
        },
    )
    assert r.returncode == 1, r.stdout
    assert "(3.12.4) != " in r.stdout


@pytest.mark.parametrize("pin", ["3.13.0rc1", "pypy3.10-7.3.12"])
def test_exact_prerelease_and_pypy_pins_are_full(tmp_path, pin):
    r = run(
        tmp_path,
        {
            ".python-version": pin + "\n",
            ".github/workflows/ci.yml": workflow([SETUP_PY]),
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr


def test_setup_bun_reading_package_manager_passes(tmp_path):
    r = run(
        tmp_path,
        {
            "package.json": '{"packageManager": "bun@1.2.3"}\n',
            ".github/workflows/ci.yml": workflow(
                [
                    "- uses: oven-sh/setup-bun@0000000000000000000000000000000000000000 # v2\n"
                    "  with:\n    bun-version-file: package.json"
                ]
            ),
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "reads package.json" in r.stdout


def test_composite_action_covered_by_the_callers_mise_action(tmp_path):
    action = """
        runs:
          using: composite
          steps:
            - uses: astral-sh/setup-uv@0000000000000000000000000000000000000000 # v8
        """
    r = run(
        tmp_path,
        {
            "mise.toml": '[tools]\npython = "3.12.4"\n',
            ".github/actions/setup/action.yml": action,
            ".github/workflows/ci.yml": workflow(
                [
                    "- uses: jdx/mise-action@0000000000000000000000000000000000000000 # v4",
                    "- uses: ./.github/actions/setup",
                ]
            ),
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr


def test_version_input_wins_over_version_file(tmp_path):
    """setup-python/-node/-go use the version input when both are given."""
    r = run(
        tmp_path,
        {
            ".python-version": "3.12.4\n",
            ".github/workflows/ci.yml": workflow(
                [
                    SETUP_PY + '\n  with:\n    python-version: "3.11.9"\n'
                    "    python-version-file: .python-version"
                ]
            ),
        },
    )
    assert r.returncode == 1, r.stdout
    assert "(3.11.9) != .python-version (3.12.4)" in r.stdout


def test_dockerfile_arg_may_name_a_line(tmp_path):
    """Dockerfile style is the repo's choice: `ARG PYTHON_VERSION=3.12` building on a 3.12
    image agrees with mise.lock's 3.12.12."""
    r = run(
        tmp_path,
        {
            "mise.toml": '[tools]\npython = "3.12"\n',
            "mise.lock": lock(python="3.12.12"),
            "Dockerfile": "ARG PYTHON_VERSION=3.12\n",
        },
    )
    assert r.returncode == 0, r.stdout + r.stderr


def test_non_numeric_version_file_says_what_it_names(tmp_path):
    r = run(
        tmp_path,
        {
            ".nvmrc": "lts/*\n",
            ".github/workflows/ci.yml": workflow(
                [node_step("with:\n  node-version-file: .nvmrc")]
            ),
        },
    )
    assert r.returncode == 1, r.stdout
    assert 'names "lts/*", not a release' in r.stdout

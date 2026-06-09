# dev-env standard — upgrade guide

The current standard version is in [`../VERSION`](../VERSION). Each repo records the version
it targets via `DEV_ENV_VERSION` in its `mise.toml`. When a repo's stamp is behind, apply every
section **strictly newer** than the repo's current version, in order, then re-stamp
`DEV_ENV_VERSION` to the new version and re-run the checker.

To find a repo's current version:

```bash
grep DEV_ENV_VERSION mise.toml   # absent ⇒ treat as v0
```

---

## v0 → v1 (baseline)

v0 = "has hk + mise + CI but predates this standard" (ruff/pytest or rubocop/rails-test via hk,
CI mirroring it, but **no gitleaks step and no version stamp**). To reach v1:

1. **Add the version stamp.** Add to `mise.toml`:
   ```toml
   [env]
   DEV_ENV_VERSION = "1"
   ```
2. **Add gitleaks + large-file to hk `linters`.** Add the import and two builtin steps to
   `hk.pkl` (large-file runs on pre-commit; gitleaks runs everywhere):
   ```pkl
   import "package://github.com/jdx/hk/releases/download/v1.46.0/hk@1.46.0#/Builtins.pkl"
   // inside the `linters` mapping:
   ["gitleaks"] = Builtins.gitleaks
   ["check-added-large-files"] = Builtins.check_added_large_files
   ```
   (Match the `amends` version already pinned in the file; bump both together if you like.)
3. **Add the dead-code + duplication audits to the `check` hook only** (noisy, so NOT on
   pre-commit). Change `["check"] { steps = linters }` to amend `linters` with the per-stack
   audit steps (see `templates/hk.<stack>.pkl`):
   - **python**: `vulture` (`uv run vulture --min-confidence 80 --exclude '*/.venv/*,.venv,build,dist' .`,
     plus extensionless PEP 723 scripts via the `git ls-files ':!*.py' | … shebang` snippet) +
     `jscpd` (`npx --yes jscpd@latest .`, config in `.jscpd.json`)
   - **ruby**: `debride` (`bundle exec debride .`) + `flay` (`bundle exec flay .`, Ruby
     structural, advisory) + `jscpd` (`npx --yes jscpd@latest .`, polyglot gate over
     `.rb`/`.erb`/`.js`/`.css`/`.scss`, config in `.jscpd.json`)
   - **shell**: same `vulture` (via `uvx`) + `jscpd` over `**/*.sh` and `**/*.py`
4. **Tools/deps:**
   - mise `[tools]`: `gitleaks = "latest"`; python + shell + **ruby** also add `node = "latest"`
     (for the `npx` that runs jscpd — jscpd is **not** a mise tool, see note below).
   - python dev deps: add `vulture`. ruby Gemfile dev group: add `flay`, `debride`.
   - copy `templates/.jscpd.json` to the repo root (**all stacks**): `minTokens 70`,
     `threshold 0`, `reporters ["ai","threshold"]`, `gitignore true`.
   - **Ruby/Rails Node cost:** adding jscpd means a Node dependency in the repo — accepted
     because a Rails app's JS/CSS/SCSS/ERB also needs duplication coverage (flay only parses
     Ruby). See the "Duplication: flay vs jscpd" note in `../SKILL.md`.
5. **CI** mirroring the hooks (see `templates/ci.*.yml`): a `gitleaks` job
   (`gitleaks/gitleaks-action@v2`, `fetch-depth: 0`) and an `audit` job (dead-code + duplication
   + a large-file guard step).
6. **Verify:** `mise install && hk install && hk run check` (gitleaks + audits run clean), then
   confirm `hk run pre-commit --all` does **not** run vulture/jscpd/flay/debride (only linters +
   large-file), then `bash scripts/dev_env_check.sh .` → `status=compliant`.

**jscpd note (v5):** jscpd 5.x ships its engine as a Rust binary via npm *optional* platform
packages. `npx --yes jscpd@latest` resolves them; the mise `npm:` backend does **not**, so jscpd
runs via `npx` (needs `node`), not as a pinned mise tool. It uses the **`ai`** reporter
(token-efficient clone output for agents) and the **`threshold`** reporter (exit 1 when
duplication exceeds `threshold`). To auto-fix clones, agents can install jscpd's refactoring
skill: `npx skills add https://github.com/kucherenko/jscpd --skill dry-refactoring`.

Thresholds are tunable in `.jscpd.json` (`minTokens`, `threshold`) and on the CLI:
`--min-confidence` (vulture), `--mass` (flay), and the `limit` in the CI large-file guard
(default 500 KB).

A repo with **no** dev-env setup at all goes straight to the full v1 layout — copy
`templates/{mise,hk,ci}.<stack>.*` and fill in stack specifics.

**Claude Code plugin / script-bundle repos** additionally need (part of v1): a dev-only
`pyproject.toml` (`templates/pyproject.plugin.toml`), a `tests/` suite running each
bundled script as a subprocess (`templates/test_scripts.example.py`), and `uv run --script` +
PEP 723 inline metadata on every Python script. See the "Claude Code plugin repos" section in
`../SKILL.md`.

---

## v1 → v2 (mise lockfile + supply-chain verification)

v2 adds a committed `mise.lock` so the mise toolchain installs reproducibly and with checksum
verification (aqua-backed tools also bring Cosign / SLSA). Tools stay spec'd `"latest"`; the lock
just records what that resolved to. To reach v2:

1. **Turn on the lockfile.** Add to `mise.toml`:
   ```toml
   [settings]
   lockfile = true
   ```
2. **Generate and commit `mise.lock`.**
   ```bash
   mise install   # resolves "latest", writes mise.lock for this platform
   mise lock       # backfills checksums for the other common platforms (linux/mac × arch)
   ```
   Commit `mise.lock`. From now on `mise install` re-verifies every artifact against it.
3. **Bump the stamp.** Set `DEV_ENV_VERSION = "2"` in `mise.toml`.
4. **Shell stack only — pin CI's shellcheck/shfmt via mise.** The CI `lint` job otherwise uses the
   runner's preinstalled shellcheck (drifts from local). Switch it to install via mise and add an
   `shfmt` check (pin the action to its current latest — see SKILL.md › "Keeping GitHub Actions
   current"):
   ```yaml
   lint:
     runs-on: ubuntu-latest
     steps:
       - uses: actions/checkout@v6
       - uses: jdx/mise-action@v2   # installs shellcheck/shfmt honoring mise.lock
       - name: Run shellcheck
         run: |
           shopt -s globstar nullglob
           shellcheck **/*.sh
       - name: Check formatting (shfmt)
         run: shfmt -d .
   ```
   Leave the Ruby/Python CI as-is: their tools come from the trusted, cached `setup-ruby` /
   `setup-uv` actions and don't run through mise in CI.
5. **Verify:** `mise install` re-verifies checksums clean; `mise.lock` is committed (`git status`);
   `bash scripts/dev_env_check.sh .` → `status=compliant` with `has_lockfile=1`.

**Lockfile vs. "latest" — how upgrades work:** `mise install` reproduces the locked versions
(same on laptop and CI). To pick up newer releases, run `mise upgrade`, which re-resolves `"latest"`
and rewrites `mise.lock`; commit the diff (e.g. `hk 1.46.0 → 1.47.0` with changed hashes) as an
intentional, reviewable bump. The `latest-deps-reminder` hook still nudges toward current versions —
the lock just makes each bump explicit instead of silent drift.

**Scope:** v2 covers only mise-managed tools (`hk`, `pkl`, `gitleaks`, `node`, `uv`, `ruff`,
`shellcheck`, `shfmt`). The `npx --yes jscpd@latest` audit step stays unpinned (jscpd 5.x ships only
as npm-distributed Rust platform packages — no clean mise backend). Project deps already lock via
`uv.lock` / `Gemfile.lock`.

---

## v2 → v3 (project docs with pinned versions)

v3 requires a **README.md** and a **CLAUDE.md** at the repo root, both recording the current
versions of the project's key packages (main framework, Tailwind, Bootstrap, …). The checker now
reports `has_readme` / `has_claude` and flags `needs-upgrade` when either is absent on a v3 repo.
To reach v3:

1. **Ensure both docs exist.** Run the checker and read `has_readme` / `has_claude`. For each that
   is `0`, **dispatch a subagent** (the `Task` tool) to write it — don't write them inline. See the
   "Project docs (README + CLAUDE.md)" section in `../SKILL.md` for the full brief. The essentials:
   - **Read key-package versions from the resolved manifests/lockfiles** (`uv.lock`/`pyproject.toml`,
     `Gemfile.lock`, `package.json`) — never from memory.
   - **README.md** via the `dev-hooks:github-readme` skill, with a tech-stack section listing those
     packages **and their pinned versions**.
   - **CLAUDE.md** with run/test/lint instructions mirroring the hk/mise setup, plus the same
     key-package-versions list.
2. **If both already exist,** only refresh the version numbers if they're visibly stale vs. the
   manifests. The `latest-deps-reminder` hook keeps them current on later manifest edits, so this is
   a one-time bootstrap.
3. **Bump the stamp.** Set `DEV_ENV_VERSION = "3"` in `mise.toml`.
4. **Verify:** `bash scripts/dev_env_check.sh .` → `status=compliant` with `has_readme=1`
   `has_claude=1`.

---

## v3 → v4 (robust large-file CI guard)

v4 fixes the `audit` job's "Large files" step, which failed under `bash -e` on **every** push
where no file was oversized. Its `while`-loop body ended in `[ "$s" -gt "$limit" ] && echo …`, so
on the final under-limit file the `[ … ]` test returned 1; that propagated through the loop and the
enclosing `large=$(…)` command substitution, which then exited non-zero and tripped `set -e`. The
guard therefore failed in the passing case (and only "passed" when it found an oversized file). To
reach v4:

1. **Patch the step.** In `.github/workflows/ci.yml`, replace the one-line
   `large=$(… [ "$s" -gt "$limit" ] && echo … )` with the `if`-based form from
   `references/templates/ci.*.yml`, so the loop's last command returns `0` when a file is within the
   limit:
   ```sh
   large=$(git ls-files | while read -r f; do
     s=$(stat -c%s "$f" 2>/dev/null || echo 0)
     if [ "$s" -gt "$limit" ]; then echo "$f ($s bytes)"; fi
   done)
   ```
   The real guard (`if [ -n "$large" ]; then … exit 1; fi`) is unchanged.
2. **Bump the stamp.** Set `DEV_ENV_VERSION = "4"` in `mise.toml`.
3. **Verify:** the snippet exits `0` with no output on a clean tree
   (`bash -e -c '…'; echo "exit=$?"` → `exit=0`), and
   `bash scripts/dev_env_check.sh .` → `status=compliant`.

---

## Adding a future version

When the standard changes, bump `../VERSION`, then add a `## vN-1 → vN` section here listing the
exact migration steps. The skill and the reminder hook pick up the new number automatically (both
read `../VERSION`). Candidate future bumps are parked in
[`dropped-from-nate.md`](dropped-from-nate.md).

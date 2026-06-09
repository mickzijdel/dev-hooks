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
   (`gitleaks/gitleaks-action@v3`, `fetch-depth: 0`, with `env: GITHUB_TOKEN:
   ${{ secrets.GITHUB_TOKEN }}` — required to scan `pull_request` events, see v6 → v7) and an
   `audit` job (dead-code + duplication + a large-file guard step).
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

## v4 → v5 (audits on pre-commit + jscpd cooldown)

v5 moves the dead-code and duplication **audits onto pre-commit** (they previously ran in the
`check` hook + CI only), so the class of failure where a commit passes pre-commit but fails CI's
`audit` job is caught before push. The audits are fast warm (vulture ~0.15s, jscpd ~1s) and each is
glob-gated, so a docs-only commit still skips them. v5 also gives jscpd a **version policy**: track
latest on a **4-day cooldown** (the same supply-chain seasoning as the Bundler cooldown), floored
at v5, and degrade gracefully when the npm registry is unreachable. To reach v5:

1. **Move the audit steps into the `linters` mapping** in `hk.pkl`. Cut each audit out of the
   `["check"] { steps = (linters) { … } }` amendment and paste it into the shared `linters`
   mapping (just before `gitleaks`), then collapse the hook to `["check"] { steps = linters }`.
   The audits per stack (see `templates/hk.<stack>.pkl`):
   - **python / shell**: `vulture` (+ shell keeps it under `uvx`, python under `uv run`) and `jscpd`
   - **ruby**: `debride`, `flay`, and `jscpd`

   Since `pre-commit`, `fix`, and `check` all use `linters`, the audits now run on all three; each
   keeps its `glob`, so it only fires when a matching file is staged.
2. **Adopt the jscpd cooldown wrapper.** Replace each `npx --yes jscpd@latest . -f <fmts>` with the
   cooldown + v5-floor + offline-graceful command (copy verbatim from `templates/hk.<stack>.pkl`,
   keeping that stack's `-f` formats):
   ```sh
   cutoff=$(date -u -d '4 days ago' +%F 2>/dev/null || date -u -v-4d +%F); if curl -sf -m 3 https://registry.npmjs.org/ >/dev/null 2>&1; then ver=$(npx --before=$cutoff --yes jscpd --version 2>/dev/null | awk 'END{print $NF}'); case $ver in ''|0.*|1.*|2.*|3.*|4.*) ver=latest;; esac; npx --yes jscpd@$ver . -f <fmts>; elif npx --offline jscpd --version >/dev/null 2>&1; then npx --offline jscpd . -f <fmts>; else echo 'jscpd unavailable offline; skipping duplication check'; fi
   ```
   It resolves the newest jscpd published ≥4 days ago (`npx --before`); if that lands below the v5
   floor (true while the v5 line is still <4 days old) it falls back to `latest`; offline it runs the
   cached jscpd, and with no cache it warns and passes so a commit is never blocked.
3. **Bump the stamp.** Set `DEV_ENV_VERSION = "5"` in `mise.toml`.
4. **Verify:** `hk run pre-commit --all` now runs the audits (vulture/jscpd, plus debride/flay on
   Ruby) — they're no longer excluded; `hk run check --all` is the same set, green. Confirm the
   jscpd step resolves a v5 release. Simulate offline (stub `npx`/`curl` to exit 1 on `PATH`) and
   confirm the jscpd step prints `jscpd unavailable offline; skipping…` and exits `0`. Then
   `bash scripts/dev_env_check.sh .` → `status=compliant`.

---

## v5 → v6 (dependency cooldowns)

v6 adds a **4-day dependency cooldown** to a repo's own packages — the same supply-chain window the
standard already applies to its jscpd tooling and that the Bundler cooldown gives Ruby. The **uv
cooldown is checker-enforced** for Python repos; Ruby and JS cooldowns are recommended but not gated
(the checker can't reliably tell which JS package manager a repo uses). See the
"Dependency cooldown (supply-chain)" section in `../SKILL.md` for the full per-ecosystem reference.
To reach v6:

1. **Add the cooldown to the repo (the enforced part is uv).**
   - **Python (uv)** — add to `pyproject.toml`:
     ```toml
     [tool.uv]
     exclude-newer = "4 days"
     ```
     A rolling duration (not a fixed date) so the window moves with today. Urgent override for one
     package: `exclude-newer-package = { foo = "0 days" }`. Then re-resolve: `uv lock` (an existing
     lock is honoured as-is; the cooldown only gates *new* resolutions).
   - **Ruby (Bundler ≥ 4.0.13)** — `source "https://rubygems.org", cooldown: 4` in the `Gemfile`.
   - **JS** — `.npmrc` `min-release-age=4` (npm), `pnpm-workspace.yaml` `minimumReleaseAge: 5760`
     (pnpm), or `.yarnrc.yml` `npmMinimalAgeGate: 5760` (yarn). Minutes for pnpm/yarn; 5760 = 4 days.
2. **(Optional) set a machine-wide default if missing** so repos that haven't opted in still get a
   floor — `bundle config set --global cooldown 4`, `npm config set min-release-age 4
   --location=user`, `pnpm config set minimumReleaseAge 5760 --global`, or `exclude-newer = "4 days"`
   in `~/.config/uv/uv.toml`. The per-repo setting overrides the global one.
3. **Bump the stamp.** Set `DEV_ENV_VERSION = "6"` in `mise.toml`.
4. **Verify:** `bash scripts/dev_env_check.sh .` → `status=compliant` with `has_cooldown=1`
   (Python repos), and `uv lock` still resolves under the cooldown.

> **Future symmetry:** only uv is gated today. Enforcing the Ruby `Gemfile` cooldown (a simple
> `cooldown:` grep) or a JS lockfile-keyed check could land in a later version if wanted.

---

## v6 → v7 (gitleaks PR scan needs GITHUB_TOKEN)

`gitleaks/gitleaks-action` now hard-requires a `GITHUB_TOKEN` to scan **pull_request**
events — it calls the GitHub API to enumerate the PR's commits. Without it the `gitleaks`
job fails on every PR with `🛑 GITHUB_TOKEN is now required to scan pull requests` (push
events are unaffected, so the gap stays hidden until the first PR). v7 also bumps the
action major `@v2` → `@v3` to track its current release. To reach v7:

1. **Add the token to the gitleaks job** in `.github/workflows/ci.yml` and bump the pin:
   ```yaml
     gitleaks:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v6
           with:
             fetch-depth: 0
         - uses: gitleaks/gitleaks-action@v3
           env:
             GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }} # required to scan pull_request events
   ```
   The token is the auto-provisioned one — no secret to create. (See `templates/ci.*.yml`.)
2. **Bump the stamp.** Set `DEV_ENV_VERSION = "7"` in `mise.toml`.
3. **Verify:** open a PR (or re-run a PR check) — the `gitleaks` job scans instead of
   failing on the missing token; `bash scripts/dev_env_check.sh .` → `status=compliant`.

---

## v7 → v8 (shebang detector matches line 1 only)

The companion steps that lint extensionless scripts (`bin/foo`, hooks) detect them by **shebang**.
The detector used `git ls-files … | xargs -r grep -lE '^#!…' 2>/dev/null`, but `grep -lE '^#!…'`
matches a `#!` line **anywhere** in a file, not just line 1. So a markdown/docs file with a fenced
```` ```sh ```` block containing `#!/bin/bash` was misdetected as a script, and
shellcheck/shfmt/ruff/vulture then tried to parse the prose as code and failed (e.g.
`shfmt: a command can only contain words and redirects`). A shebang is only a shebang on line 1.
v8 replaces each detector with a `head -n1` per-file check. To reach v8:

1. **Fix the detectors in `hk.pkl` and `.github/workflows/ci.yml`.** In each companion step, replace
   the `xargs -r grep -lE 'REGEX' 2>/dev/null` detector with a line-1-only `head -n1` loop. The
   affected steps are `shellcheck-scripts`, `shfmt-scripts`, `ruff-check-scripts`,
   `ruff-format-scripts`, and `vulture` (hk), plus the `shellcheck`, `ruff`, and `vulture` steps in
   CI. The two shapes:

   **Pipe form** (hk lint companion steps) — before:
   ```sh
   git ls-files <excludes> | xargs -r grep -lE 'REGEX' 2>/dev/null | xargs -r <tool>
   ```
   after:
   ```sh
   git ls-files <excludes> | while IFS= read -r f; do head -n1 "$f" 2>/dev/null | grep -qE 'REGEX' && printf '%s\n' "$f"; done | xargs -r <tool>
   ```

   **Subshell form** (vulture, hk + CI) — before:
   ```sh
   $(git ls-files <excludes> | xargs -r grep -lE 'REGEX' 2>/dev/null)
   ```
   after:
   ```sh
   $(git ls-files <excludes> | while IFS= read -r f; do head -n1 "$f" 2>/dev/null | grep -qE 'REGEX' && printf '%s\n' "$f"; done)
   ```

   In `hk.pkl` the `check` is a double-quoted pkl string, so escape the inner quotes as `\"$f\"` and
   keep the doubled escapes (`\\b` in the regex, `\\n` in `printf '%s\\n'`). In `ci.yml` the detector
   sits in a `run: |` block (plain shell) — no extra escaping. Copy the exact lines from
   `templates/hk.<stack>.pkl` and `templates/ci.<stack>.yml`. (Ruby carries no shebang detectors, so
   a Ruby repo only bumps the stamp.)
2. **Bump the stamp.** Set `DEV_ENV_VERSION = "8"` in `mise.toml`.
3. **Verify:** add a throwaway `docs.md` with a fenced ```` ```sh ```` block containing `#!/bin/bash`
   and run `hk run check --all` — it must pass (the docs file is no longer misdetected as a script),
   while a real extensionless script with a line-1 shebang is still linted. Then
   `bash scripts/dev_env_check.sh .` → `status=compliant`.

---

## v8 → v9 (exclude bundled output from duplication + test nudges)

v9 adds `dist` and `build` to `.jscpd.json`'s `ignorePattern`, so bundled/compiled JS/CSS output
(webpack/rollup/`dist/`, `app/assets/builds`, generic `build/`) is excluded from the duplication
audit — generated artifacts aren't hand-written clones and only create noise. The same file is now
also read by the `missing-test-reminder` hook (dev-hooks plugin): it skips any directory listed in
the repo's `.jscpd.json` `ignorePattern` (plus minified `*.min.*` files) when nudging for missing
tests, so vendored/generated code no longer triggers false "add a test" prompts. To reach v9:

1. **Add `dist`/`build` to `.jscpd.json`** `ignorePattern` (all stacks):
   ```json
   "**/dist/**",
   "**/build/**",
   ```
   Keep any repo-specific excludes already present. (`node_modules`/`vendor` were added back in v1.)
2. **Bump the stamp.** Set `DEV_ENV_VERSION = "9"` in `mise.toml`.
3. **Verify:** the jscpd audit still runs clean (`hk run check --all`); a new file under `dist/` or
   `build/` no longer trips the duplication gate or the `missing-test-reminder` hook; then
   `bash scripts/dev_env_check.sh .` → `status=compliant`.

---

## v9 → v10 (gitleaks whole-tree allowlist + fnox nudge)

The hk `gitleaks` step runs `gitleaks dir` over the **whole working tree** — `dir` has no
respect-gitignore flag (verified with gitleaks 8.30.1), so it scans gitignored files too. In any
real repo with a local `.env`, `log/`, `tmp/cache/`, or a Rails `config/credentials/*.key`, that
means **every `git commit` fails** at the pre-commit hook and `hk run check` is permanently red,
even though none of those files are tracked (so `gitleaks git` is clean and CI — which scans
history — stays green, hiding the gap until a local commit). v10 ships a committed
`.gitleaks.toml` allowlist that fixes it, and adds an advisory nudge toward [[env-to-fnox]] when a
repo has plaintext secrets in use. To reach v10:

1. **Copy `.gitleaks.toml`** (all stacks) from `references/templates/.gitleaks.toml` → repo root.
   It `[extend]`s the default ruleset and allowlists the gitignored runtime/secret **paths**
   (`.env`, `log/`, `tmp/`, `.venv/`, `node_modules/`, `vendor/`, `config/credentials/*.key`).
   gitleaks auto-loads it from the scan root — no `--config` flag, no `hk.pkl`/CI change needed.
   Keep any repo-specific allowlist entries already present. (Path-scoped to gitignored locations
   only, so app/config **source** stays fully scanned — see SKILL.md › "gitleaks whole-tree
   allowlist", including the `git add -f` caveat.)
2. **Bump the stamp.** Set `DEV_ENV_VERSION = "10"` in `mise.toml`.
3. **fnox nudge (advisory).** The checker now emits `suggests_fnox=1` when the repo has secrets in
   use (a non-empty `.env`/`.env.local`, a Rails master key, or source references to credentials)
   and no `fnox.toml`. If set, recommend the [[env-to-fnox]] skill to migrate the plaintext
   secrets out of the repo. This never gates compliance.
4. **Verify:** create a dummy `.env` with a fake key and a `log/test.log` with a JWT-shaped
   string, then `hk run check` must **exit 0** ("no leaks found"); a real key hardcoded in
   `app/`/source is still caught. Then `bash scripts/dev_env_check.sh .` →
   `has_gitleaks_config=1` and `status=compliant`.

---

## v10 → v11 (mise upgrade cooldown)

v11 adds `minimum_release_age = "4d"` to `[settings]` in `mise.toml`, extending the same 4-day
supply-chain window to **mise tool upgrades** that the standard already applies to jscpd
(`npx --before=<4 days ago>`) and project deps (Bundler, uv, npm cooldowns). With `mise.lock`
committed, `mise install` always reproduces the locked versions — unaffected by this setting; it
only prevents `mise upgrade` from resolving a tool version published in the last 4 days, giving the
community time to catch and yank a malicious release before it lands. To reach v11:

1. **Add `minimum_release_age` to `[settings]` in `mise.toml`:**
   ```toml
   [settings]
   lockfile = true
   minimum_release_age = "4d"   # ← add this line
   ```
2. **Bump the stamp.** Set `DEV_ENV_VERSION = "11"` in `mise.toml`.
3. **Verify:** `mise install` still reproduces locked versions unchanged;
   `bash scripts/dev_env_check.sh .` → `status=compliant`.

---

## Adding a future version

When the standard changes, bump `../VERSION`, then add a `## vN-1 → vN` section here listing the
exact migration steps. The skill and the reminder hook pick up the new number automatically (both
read `../VERSION`). Candidate future bumps are parked in
[`dropped-from-nate.md`](dropped-from-nate.md).

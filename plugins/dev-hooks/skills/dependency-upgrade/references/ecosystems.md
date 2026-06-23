# Per-ecosystem upgrade commands

The exact read-only listing, upgrade, and lockfile-regeneration commands per ecosystem, plus
where to find the changelog/migration guide for a major bump. Always **regenerate the lockfile
through the package manager** — never hand-edit it. Every command runs inside the repo on the
upgrade worktree/branch.

The 4-day cooldown is already encoded in each repo's manifest (dev-env-setup), so these commands
will hold back releases younger than 4 days. That's intended — don't disable it to grab a fresher
version unless the user explicitly asks (e.g. an urgent CVE).

## JavaScript — npm / pnpm / yarn

Pick the manager by lockfile (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, else npm).

| | npm | pnpm | yarn (classic) | yarn (Berry 2+) |
|---|---|---|---|---|
| List outdated | `npm outdated` | `pnpm outdated` | `yarn outdated` | `yarn upgrade-interactive` |
| Patch/minor | `npm update --save` | `pnpm update` | `yarn upgrade` | `yarn up '*'` (review) |
| One package to latest (incl. major) | `npm install pkg@latest` | `pnpm add pkg@latest` | `yarn upgrade pkg@latest` | `yarn up pkg@latest` |
| Regenerate lockfile | `npm install` | `pnpm install` | `yarn install` | `yarn install` |

- `npm outdated` **exits 1** when anything is outdated — that's not an error; capture its output.
- Read the **Current / Wanted / Latest** columns. `Wanted` is what your semver range allows
  (patch/minor); a `Latest` whose leading number is higher than `Current` is a **major**.
- After bumping, run `npm audit` / `pnpm audit` / `yarn npm audit` and fold any safe fixes in.
- Changelogs: the package's npm page → "Changelog", its GitHub **Releases**, or `CHANGELOG.md` in
  its repo. `npm repo pkg` opens the source repo.

## Ruby — bundler

| Task | Command |
|---|---|
| List outdated | `bundle outdated --strict` (only what your `Gemfile` constraints allow) or `bundle outdated` (all) |
| Patch/minor (conservative) | `bundle update --conservative` |
| One gem | `bundle update <gem>` |
| Regenerate lockfile | bundler rewrites `Gemfile.lock` on any `bundle update`/`install` |

- For a **major**, widen the gem's constraint in the `Gemfile` (e.g. `"~> 3.0"` → `"~> 4.0"`),
  then `bundle update <gem>`.
- Rails apps: after upgrading run `bin/rails app:update` for framework defaults, and check
  `bin/rails db:migrate` / deprecation warnings. For a Rails version bump, use the rails-toolkit
  `rails-upgrade` skill if available — it generates a breaking-change report.
- Changelogs: the gem's GitHub **Releases** / `CHANGELOG.md`; `bundle open <gem>` to read its
  source; RubyGems.org page for version history.

## Python — uv / poetry / pip

Pick the manager by lockfile/manifest (`uv.lock` or `[tool.uv]` → uv; `poetry.lock` or
`[tool.poetry]` → poetry; else pip).

| Task | uv | poetry | pip |
|---|---|---|---|
| List outdated | `uv pip list --outdated` | `poetry show --outdated` | `pip list --outdated` |
| Upgrade all (within constraints) | `uv lock --upgrade` then `uv sync` | `poetry update` | (edit pins, then `pip install -U -r requirements.txt`) |
| One package | `uv lock --upgrade-package pkg` then `uv sync` | `poetry update pkg` | `pip install -U pkg` |
| Regenerate lockfile | `uv lock` | `poetry lock` | `pip freeze > requirements.txt` (or pip-tools `pip-compile`) |

- For a **major**, raise the version constraint in `pyproject.toml`/`requirements.txt`, then
  re-lock and `uv sync` / `poetry install`.
- `exclude-newer = "4 days"` in `[tool.uv]` is the cooldown — it gates new resolutions, leaving
  already-locked versions untouched.
- Changelogs: the project's PyPI page → "Release notes" / project links → GitHub **Releases** or
  `CHANGELOG.md`; many projects ship an `UPGRADING`/migration doc.
- **PEP 723 inline-script deps are a separate surface.** A single-file script with a
  `# /// script` block (run via `uv run --script`) declares its own `dependencies = [...]`.
  When those are **unpinned** names (`"python-docx"`, not `"python-docx>=1.2"`), each run already
  resolves them to latest-within-cooldown — there is nothing to bump, and the
  `upgrade_inventory.sh` preflight (which only reads `pyproject.toml`/`requirements.txt`) won't
  flag them. If a script instead **pins** a version in its inline block, upgrade it the same way
  as a manifest dep: edit the version in the `# /// script` block, then re-run the script
  (`uv run --script path` refreshes its own per-script lock) and run that script's tests.

## GitHub Actions — delegate to [[github-actions]]

Don't reimplement this — the github-actions skill owns it:

```bash
pinact run -u                                                   # bump every uses: to the latest SHA + version comment
bash "$CLAUDE_PLUGIN_ROOT/skills/dev-env-setup/scripts/check_action_refs.sh" .github/workflows  # verify the pins resolve
```

Pins are kept as `owner/repo@<40-hex-sha> # vX.Y.Z` (tags are mutable; a takeover repoints them).
A major action bump (e.g. `actions/checkout@v4 → v5`) can change inputs/runner — read that
action's release notes the same way as any other major. Commit the Actions bump separately
(`chore(ci): bump action pins to latest`).

## General notes

- **One ecosystem's patch/minor = one commit.** **One major = its own commit** with a migration
  note. Keeps the history bisectable and each breaking change reviewable in isolation.
- Run the suite after every commit-worth of change; a red tree is deferred, never committed.
- After upgrading, refresh the key-package versions recorded in `README.md` + `CLAUDE.md` from the
  resolved lockfiles (not from memory) — the `latest-deps-reminder` hook expects them in sync.

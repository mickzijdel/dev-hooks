---
name: dependency-upgrade
description: |
  Bring a repo's dependencies up to the latest versions across JavaScript (npm/pnpm/yarn),
  Ruby (bundler), Python (uv/poetry/pip), and GitHub Actions — reading changelogs/migration
  guides for major bumps, applying the needed code changes, and landing each step as its own
  verified commit. Use when the user wants to "update my packages", "upgrade dependencies",
  "bump deps to latest", "check for outdated packages", or do this across all their repos
  (fleet mode). Gates every commit on a green test suite; defers any major it can't get green
  to a written report. Pairs with the github-actions skill (Actions pins) and respects
  dev-env-setup's 4-day dependency cooldown.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
  - WebFetch
  - AskUserQuestion
  - Task
---

# dependency-upgrade

Update a repo to the latest packages **safely and incrementally**: patch/minor in batched
per-ecosystem commits, each major in its own commit after reading the migration guide, and
**nothing committed unless the tests are green**. Covers JavaScript, Ruby, Python, and (by
delegating to [[github-actions]]) GitHub Actions. This skill does the *upgrade* work that
[[dev-env-setup]] deliberately leaves alone — dev-env-setup pins the *tooling* and sets the
4-day cooldown; this skill moves the *project's own dependencies* forward within that policy.

Per-ecosystem commands (list-outdated, upgrade, regenerate lockfile, where changelogs live)
are in [references/ecosystems.md](references/ecosystems.md) — **read it before upgrading any
ecosystem**.

## Workflow (one repo)

1. **Isolate.** Work on a clean tree in a dedicated worktree+branch off the local HEAD (never
   on a dirty main) — see [[using-git-worktrees]]. Run the read-only preflight to see what's
   present and what to list:
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/skills/dependency-upgrade/scripts/upgrade_inventory.sh" .
   ```
   It reports `has_js`/`has_ruby`/`has_python`/`has_actions`, the chosen package manager per
   ecosystem, and the exact outdated-listing command for each. (`--run` also executes the
   read-only listing commands whose tool is installed.) It reads only manifests
   (`package.json`/`Gemfile`/`pyproject.toml`/…), so a Python repo whose single-file CLIs carry
   **PEP 723 inline-script deps** has a surface the preflight won't list — see the PEP 723 note
   in references/ecosystems.md (unpinned inline deps are already auto-latest; pinned ones you
   bump by hand).

2. **Green baseline — do this first.** Run the repo's test suite and confirm it passes *before
   touching anything*. Don't upgrade onto a red baseline — you won't be able to tell your bump
   from a pre-existing failure. Detect the runner from the stack: `uv run pytest` / `pytest`
   (Python), `bundle exec rspec` or `bin/rails test` (Ruby), `npm test` / `pnpm test` (JS). If
   there is **no** test suite, fall back to the build + linters and say so in the final report —
   a missing suite is a gap to surface, not a reason to skip verification. If a suite **exists but
   can't run locally** (it needs a Postgres/MySQL service, a browser, or other infra that isn't set
   up), treat that as a **local-setup gap to fix and flag to the user**, not something to work
   around — get the dependency running (e.g. start Postgres + create the role/DB so `bin/rails
   test` works) so you can actually verify the upgrade, and tell the user what was missing. Don't
   push an unverified bump on a boot check alone.

3. **Respect the 4-day cooldown.** The manifests already encode dev-env-setup's supply-chain
   window (`exclude-newer`/`cooldown`/`min-release-age`), so the package manager will hold back
   releases younger than 4 days — that's intended. Don't disable it to grab a fresher release
   unless the user asks (e.g. an urgent security fix). See the cooldown table in
   [[dev-env-setup]].

4. **Patch/minor pass — batch per ecosystem.** For each ecosystem, list outdated (step 1's
   command), apply the **patch + minor** upgrades together, and **regenerate the lockfile via the
   package manager** (never hand-edit it — see references/ecosystems.md for the exact commands).
   Run the tests. Green → **one commit per ecosystem** (`chore(deps): bump JS patch/minor deps`).
   Red → bisect the offending package out (pin it back), commit the rest, and note the held-back
   one in the report.

5. **Major pass — one major at a time.** Majors carry breaking changes, so handle them singly:
   - `WebFetch` the changelog / release notes / migration guide (npm package "Changelog",
     RubyGems/GitHub releases, PyPI "Release notes", the project's UPGRADING/CHANGELOG).
   - Apply the required code changes for that one bump.
   - Run the full suite. **Green → its own commit** (`chore(deps)!: upgrade <pkg> 2 → 3`, with a
     one-line migration note in the body).
   - **Can't get green → revert that single major**, append it to a deferred-upgrades report
     (`plans/deferred-upgrades.md` in the repo) with *why* and the manual steps, and move on. Do
     not leave the tree red.

6. **GitHub Actions.** Hand the Actions part to **[[github-actions]]** (`pinact run -u` to bump
   pins to the latest SHAs, then `check_action_refs.sh` to verify). Commit it separately
   (`chore(ci): bump action pins to latest`).

7. **Sync the docs.** Update the key-package versions recorded in `README.md` and `CLAUDE.md`
   from the resolved manifests/lockfiles (this is what the `latest-deps-reminder` hook nudges
   for). Fold it into the relevant commit or its own `docs:` commit.

8. **Finish — and deploy if asked.** Summarize **upgraded vs deferred (and why)**. If everything
   is green, merge the branch back and clean up the worktree (see
   [[finishing-a-development-branch]]). Then handle deploy per the repo's model (see Fleet mode
   step 3 for the full split): a **push-to-deploy** app only gets pushed if the user wants it
   deployed (else leave it on a branch/PR); a **separate-deploy** app (Kamal etc.) is pushed
   normally, and — **if the user asked to deploy it** — you then **run the deploy** (`kamal deploy`)
   and report the outcome. **Pause and ask the user first** when a major touched a public API /
   data migration / schema, or the diff is large enough to want a second look. **Always confirm the
   deploy intent before deploying** (a single repo upgraded on its own counts too, not just fleet
   runs).

## Fleet mode ("update all my repos")

To sweep every repo, mirror the cadence in the [[dev-env-bump-backfill-fleet]] memory and the
[[github-actions]] fleet bump — but **one isolated agent per repo** so they never share state:

1. **Enumerate + confirm.** Start from the dev-env fleet (repos carrying `DEV_ENV_VERSION` in
   `mise.toml`; the [[dev-env-bump-backfill-fleet]] memory lists the current set) and cross-check
   with live discovery:
   ```bash
   gh repo list "$(gh api user -q .login)" --source --no-archived --limit 200 --json nameWithOwner -q '.[].nameWithOwner'
   ```
   **Show the user the target set and confirm before touching anything** — don't sweep in repos
   they don't want changed.
2. **Ask up front, before upgrading anything** — an upgrade only matters once it's deployed, so
   get the user's intent first. Ask two things:
   - **(a) Which repos to exclude** from the upgrade entirely.
   - **(b) Which deployed apps to deploy** after upgrading. Name each deployed app and its deploy
     model (below), and confirm per app — don't assume.
   Carry the answers into the dispatch.
3. **Know each repo's deploy model** — it decides what "finish" means:
   - **Push-to-deploy** (Vercel / Netlify / GitHub Pages / Streamlit Cloud — the push to the
     default branch *is* the deploy): the push ships it. So **only push if the user said to deploy
     this repo**; otherwise leave the upgrade on a branch / PR and don't merge to default.
   - **Separate deploy** (Kamal, a `deploy.yml` workflow, `bin/deploy`): pushing is safe — it does
     **not** ship. Push as normal, then **if the user opted to deploy this app, run its deploy
     step** (for Kamal: `kamal deploy`) and report the result.
   - **No deploy** (library / CLI / plugin): just merge + push.
4. **Dispatch one agent per repo**, each in its **own worktree/branch** (the Task tool's
   `isolation: "worktree"`, or [[dispatching-parallel-agents]]), each running the per-repo workflow
   above. Pass each agent its **exclude / push / deploy disposition** from steps 2–3, and a stable,
   **correct agent↔repo mapping** — if you later message an agent mid-run (e.g. to change the deploy
   plan), triple-check the agent id matches the repo, or the instruction lands on the wrong repo.
5. **Report** a one-line summary per repo at the end — upgraded / deferred, push state (pushed /
   PR #), and deploy state (deployed / not).

## Guardrails

- `gh`/`pinact`/a package manager missing or unauthenticated → stop and surface it; never guess a
  version or a SHA.
- A repo with a deliberately bespoke/pinned setup → flag it, don't force upgrades.
- Never disable the cooldown or commit a red tree to "make progress" — defer instead.
- Don't auto-run from a hook; this writes commit-tracked changes. It's invoked by the user (the
  `latest-deps-reminder` hook only nudges that deps may be stale).

## How this skill is reached

- The `latest-deps-reminder` hook flags that a manifest's versions may be stale → run this skill
  to actually move them forward.
- The user asks to "update packages" / "upgrade dependencies" / "bump deps" / do it across all
  their repos → this skill's description triggers directly.

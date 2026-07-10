---
name: worktree-setup
description: |
  Provision a freshly-created git worktree so it's actually ready to work in — trust its
  mise.toml, copy gitignored-but-needed files (Rails config/master.key, .env, …) from the main
  checkout, and re-mark shebang scripts executable. Use right after creating a worktree (native
  EnterWorktree or `git worktree add`), or when a new worktree errors with "mise.toml not
  trusted", is missing secrets/.env, can't load the app, or has non-executable scripts. Also
  when parallel worktrees collide on the same dev-server port or database — opt into per-worktree
  ports + databases via a `.worktree-isolate.conf`. Pairs with using-git-worktrees (which creates
  the worktree; this provisions it).
allowed-tools:
  - Read
  - Bash
  - Glob
---

# worktree-setup

A fresh worktree is a clean `git` checkout — and that's the problem. The committed files are
there, but everything the working tree needs that git *doesn't* track is not: the `mise.toml`
is untrusted, gitignored secrets/config (`config/master.key`, `.env`, service-account JSON) are
absent, and `core.fileMode=false` checkouts can land shebang scripts without `+x`. So the app
won't boot and the tooling errors until you fix each by hand — every single time.

This skill closes those gaps in one step. It **provisions** a worktree; it does not create one
(only the harness can switch the session into a worktree). Use it *with* [[using-git-worktrees]],
not instead of it.

## Workflow

1. **Ensure `.worktrees/` is ignored.** Before creating any project-local worktree, confirm the
   directory is gitignored so its contents never get tracked:
   ```bash
   git check-ignore -q .worktrees || printf '.worktrees/\n' >>.gitignore   # then commit it
   ```
   (The native `EnterWorktree` tool uses `.claude/worktrees/`, which is already kept out of
   status; only the manual `git worktree add` fallback needs this.)

2. **Branch from local HEAD, not origin.** Your local `main` often leads or lags `origin`; a
   worktree branched from origin silently drops local commits.
   ```bash
   git config worktree.baseref head
   ```
   (`setup-worktree.sh` also sets this, idempotently, for next time.)

3. **Create the worktree.** Prefer the native tool so the session switches into it:
   - **Native:** `EnterWorktree` (with `worktree.baseref head` set, it branches from local HEAD).
   - **Fallback:** `git worktree add .worktrees/<name> -b <branch> HEAD && cd .worktrees/<name>`

4. **Provision it** — run from inside the new worktree:
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/skills/worktree-setup/scripts/setup-worktree.sh"
   ```
   It trusts the worktree's `mise.toml` (safe — it's a worktree of a repo you already trust, so
   this does **not** contradict [[dev-env-setup]]'s "never auto-trust unknown configs" rule),
   copies the gitignored files, and re-marks shebang scripts executable. It reports `copied`,
   `skipped_heavy`, `mise_trusted`, `exec_fixed`, and `isolated`. Pass `--source DIR` to override
   the copy origin, or a positional worktree path to provision one you're not currently inside.
   If the repo carries a `.worktree-isolate.conf`, this step also allocates the worktree its own
   port + database (see [Per-worktree isolation](#per-worktree-isolation) below).

5. **Verify, then work.** Confirm the toolchain loads (`mise exec -- <tool> --version`) and the
   baseline tests pass, then proceed with the worktree-per-agent workflow (incremental commits →
   merge to main → clean up via [[finishing-a-development-branch]]).

## What gets copied

Everything gitignored **and present** in the main checkout is copied into the worktree, with one
exclusion list: known-heavy build/dependency dirs (`node_modules`, `.venv`, `venv`,
`vendor/bundle`, `tmp`, `dist`, `build`, `.next`, `.nuxt`, `target`, `__pycache__`,
`.pytest_cache`, `.ruff_cache`, `.mypy_cache`, `coverage`, `.git`) and the worktree dirs
themselves (`.worktrees`, `.claude/worktrees`). The script uses `git ls-files --others --ignored
--directory`, so a fully-ignored `node_modules/` is one entry to skip, not 40k files to walk.

These are **copies, not commits** — the secrets land in the worktree's working tree (itself
gitignored there too) so the app runs; they're never staged. If a repo carries a gitignored dir
you *do* want (uploads, fixtures) it comes along automatically unless its name is on the heavy
list; if it's huge and unwanted, delete it from the worktree after.

## Per-worktree isolation

Copying `.env` verbatim means every worktree points at the **same** port and the **same**
database — so two dev servers fight over `:3000` and parallel migrations stomp one shared DB.
Opt in by committing a `.worktree-isolate.conf` at the repo root; `setup-worktree.sh` then hands
off to `isolate-worktree.sh`, which allocates each worktree a stable, collision-free offset and
writes the derived values into a gitignored `mise.local.toml` overlay (layering over the
committed `mise.toml` — the copied `.env` is never touched).

```sh
# .worktree-isolate.conf — committed; declares what to isolate (ports/hostnames aren't secrets)
WT_BASE_PORT=3000                    # PORT = base + per-worktree offset (offset 0 = main checkout)
WT_DB_SUFFIX_VAR=WORKTREE_DB_SUFFIX  # export "_<slug>" for database.yml to read
WT_REDIS_URL_VAR=REDIS_URL           # redis://localhost:6379/<offset>
WT_COMPOSE_NAME=myapp                # emit COMPOSE_PROJECT_NAME=<name>_<slug> for compose/devcontainers
```

The offset is stable across re-runs and self-heals: a shared registry in the git *common* dir
tracks slug→offset, and removing a worktree frees its offset for the next one. Host-native runs
read `PORT` + the DB suffix; a per-worktree devcontainer reads `COMPOSE_PROJECT_NAME`. See
[references/isolation.md](references/isolation.md) for the full Rails recipe (`database.yml`
suffix + `bin/rails db:prepare`), the devcontainer notes, and the dotenv alternative.

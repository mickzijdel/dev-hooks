---
name: worktree-setup
description: |
  Provision a freshly-created git worktree so it's actually ready to work in — trust its
  mise.toml, copy gitignored-but-needed files (Rails config/master.key, .env, …) from the main
  checkout, and re-mark shebang scripts executable. Use right after creating a worktree (native
  EnterWorktree or `git worktree add`), or when a new worktree errors with "mise.toml not
  trusted", is missing secrets/.env, can't load the app, or has non-executable scripts. Pairs
  with using-git-worktrees (which creates the worktree; this provisions it).
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
   `skipped_heavy`, `mise_trusted`, and `exec_fixed`. Pass `--source DIR` to override the
   copy origin, or a positional worktree path to provision one you're not currently inside.

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

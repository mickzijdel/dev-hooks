---
name: github-actions
version: 1.0.0
description: |
  Write, review, and harden GitHub Actions workflows against supply-chain attacks, and bump a
  whole fleet of repos' action pins to the latest versions. Use when writing or editing a
  workflow YAML (.github/workflows/*.yml, ci.yml), when asked to review a CI workflow or audit
  GitHub Actions security, when the ci-action-ref-reminder hook fires, or when Mick wants to
  "bump my actions", "update the fleet", "pin actions to SHAs", or close supply-chain /
  pull_request_target / script-injection / GITHUB_TOKEN-permissions gaps. Pairs with
  references/security-checklist.md (the full checklist) and dev-env-setup's CI templates.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
  - Task
  - AskUserQuestion
---

# github-actions

The canonical home for everything GitHub Actions in Mick's repos: the security checklist to
apply when writing or reviewing a workflow, and the fleet-wide procedure for bumping action
pins to their latest versions. The full checklist lives in
[references/security-checklist.md](references/security-checklist.md); read it whenever you touch
a workflow. This skill is the security layer over [[dev-env-setup]], which owns the CI
*templates* (already hardened to this standard).

## The five that matter most

If you do nothing else when writing or reviewing a workflow, get these right:

1. **Pin every `uses:` to a full commit SHA**, not a tag or branch —
   `owner/repo@<40-hex-sha> # vX.Y.Z`. Tags are mutable; a compromised maintainer can repoint
   `@v3` to malicious code and every downstream run picks it up silently (tj-actions, Trivy).
2. **Default `GITHUB_TOKEN` to read-only.** Add `permissions: { contents: read }` at the
   workflow level; grant more only on the specific job that needs it, at the job level.
3. **Never `pull_request_target` (or `workflow_run`) in public repos.** They run with secret
   access on fork-PR-controlled input. Use plain `pull_request`, or gate on the upstream event.
4. **Never interpolate `${{ github.* }}` into `run:`.** Branch names, PR titles, issue bodies
   are attacker-controlled. Assign to an `env:` var first, then reference `$VAR` in the shell
   (Ultralytics, Nx/s1ngularity). Same rule for LLM output and anything written to
   `$GITHUB_ENV` / `$GITHUB_PATH`.
5. **Use OIDC for cloud credentials** (AWS/Azure/GCP) instead of long-lived static secrets —
   short-lived, job-scoped, nothing to steal.

## Writing or reviewing one repo's workflow

1. Read [references/security-checklist.md](references/security-checklist.md) and walk the
   workflow against it. The most common real finding is unpinned actions and a missing
   `permissions:` block.
2. **Pin/verify the refs.** Resolve each action's latest release SHA and pin it with a version
   comment:
   ```bash
   a=actions/checkout
   tag=$(gh release view --repo "$a" --json tagName -q .tagName)   # e.g. v7.0.0
   sha=$(gh api "repos/$a/commits/$tag" --jq .sha)                 # dereferences annotated tags
   echo "uses: $a@$sha # $tag"
   ```
   `pinact` automates this across a whole file (`pinact run` to pin tags→SHA with comments,
   `pinact run -u` to update to latest). Install it with `mise use -g pinact` or
   `mise exec -- pinact` if a repo pins it.
3. **Verify the pins resolve and the comments are honest** before finishing:
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/skills/dev-env-setup/scripts/check_action_refs.sh" .github/workflows
   # SHA-pinned refs with a `# vX.Y.Z` comment are checked: the tag is resolved on the remote
   # and its SHA must match the pin. A mismatch (lying comment / wrong SHA) FAILs.
   ```
   If `gh`/`pinact` is unavailable or unauthenticated, say so and ask Mick — never guess a SHA.

## Fleet-wide bump

Turn the per-repo recipe into one cross-repo pass (this is the "bump my fleet's actions"
request). Mirror the cadence in the [[dev-env-bump-backfill-fleet]] memory: do the whole fleet
in one session — branch, bump, verify, commit, push — so the repos stay in lockstep.

1. **Enumerate the fleet.** Start from the dev-env fleet (repos carrying `DEV_ENV_VERSION` in
   `mise.toml`; the [[dev-env-bump-backfill-fleet]] memory lists the current set), and
   cross-check with live discovery:
   ```bash
   gh repo list mickzijdel --source --no-archived --limit 200 --json nameWithOwner -q '.[].nameWithOwner'
   ```
   Keep only repos that actually have `.github/workflows/`. **Show Mick the target set and
   confirm it before changing anything** — don't sweep in repos he doesn't want touched.
2. **Per repo** (work in a temp clone or worktree, never on a dirty main):
   ```bash
   git switch -c chore/bump-actions
   pinact run -u                       # pin + update every uses: to the latest SHA + comment
   bash "$CHECKER" .github/workflows   # verify refs resolve and comments match
   git diff                            # eyeball before committing
   ```
   Also add a `permissions: { contents: read }` block to any workflow missing one, and apply
   any other checklist gaps you spot.
3. **Commit + push/PR** with a consistent message per repo (e.g.
   `chore(ci): pin actions to SHAs and bump to latest`). Open a PR unless Mick wants direct
   pushes. Do all repos in the same session, then report a one-line summary per repo.

Guardrails: `gh`/`pinact` missing or unauthenticated → stop and surface it. A repo whose CI
is intentionally bespoke → flag it, don't force the standard. Never push to a repo's default
branch directly.

## How this skill is reached

- **Editing a workflow** → the `ci-action-ref-reminder` hook fires and points here.
- **Setting up / upgrading the dev env** → dev-env-setup's CI templates ship pre-hardened to
  this standard (SHA pins + `permissions:`) and link back here; the dev-env v16 bump is where
  this became the default.
- **"Review this CI workflow" / "audit my GitHub Actions"** → this skill's description triggers
  directly.

# GitHub Actions security checklist

Distilled from Aikido's "The complete GitHub Actions security checklist"
(<https://www.aikido.dev/blog/checklist-github-actions>). The defaults favour convenience over
safety, and these vectors are actively scanned for and exploited. You can't fully protect
against a compromised maintainer or a GitHub zero-day, but closing these closes what attackers
are actually using.

**Top five — do these first:**

1. Pin all third-party actions to a full commit SHA.
2. Set default `GITHUB_TOKEN` permissions to read-only.
3. Never `pull_request_target` in public repos.
4. Never interpolate `${{ github.* }}` directly into `run:` steps.
5. Use OIDC for cloud credentials instead of long-lived secrets.

## Trigger configuration

- **Never `pull_request_target` in public repos.** It runs in the *base* repo context with
  secret access even for fork PRs, and anyone can open a PR. Any secret referenced is loaded
  into a runner executing attacker-controlled code. (Trivy, March 2026: secrets exfiltrated;
  attackers then scanned GitHub for the trigger and opened hundreds of PRs in a day.) In
  private repos, require maintainer approval for first-time-contributor PRs
  (Settings → Actions → Fork pull request workflows).
- **Avoid `workflow_run` in public repos.** The downstream workflow runs privileged regardless
  of what triggered the upstream one, so a poisoned artifact from a fork PR reaches a
  secret-bearing context one hop later. Prefer triggering directly (`push` on `main`). If you
  must, gate on the upstream event:
  ```yaml
  jobs:
    deploy:
      if: github.event.workflow_run.event == 'push'
  ```
- **Audit other privileged triggers** — `issue_comment`, `issues`, `pull_request_review`,
  `pull_request_review_comment` all run with secret access and can be influenced by outsiders.
  The untrusted-input rules below apply to all of them.

## Handling untrusted input

- **Treat all branch names, PR titles, commit messages, and issue bodies as untrusted.** Like
  SQL injection: user-controlled values interpolated into a shell get run as code.
  ```yaml
  # vulnerable
  - run: echo "Branch is ${{ github.head_ref }}"
  # safe — assign to env first, reference the shell var
  - run: echo "Branch is $BRANCH"
    env:
      BRANCH: ${{ github.head_ref }}
  ```
  Applies to `github.head_ref`, `github.event.pull_request.title`, `github.event.issue.body`,
  `github.event.commits[0].message`, etc. (Ultralytics: a curl command as a branch name. Nx: combined with `pull_request_target` to leak a read/write `GITHUB_TOKEN`.)
- **AI agents in workflows: read-only tokens, no raw user input in prompts.** An agent has the
  same secret access as any step; prompt injection via an issue title can make it exfiltrate
  secrets through its own tools (PromptPwnd). Don't grant agents beyond read, and keep raw
  issue/PR/commit text out of prompts.
- **Treat LLM-generated output as untrusted** — assigning model output straight into `run:` is
  the same injection risk. Assign to an env var, validate, never pipe into a shell.
- **Never write untrusted data to `$GITHUB_ENV` or `$GITHUB_PATH`.** They set env vars / PATH
  for all later steps; an attacker can set `NODE_OPTIONS` for code execution or front-run a
  trusted tool with a malicious binary.

## Artifact handling

- **Exclude secret files from uploads; avoid `path: .`** in `upload-artifact`. A bare `.`
  sweeps up `.env`, credential configs, and `*.pem`. List explicit paths, and keep `.env`,
  `*.pem`, etc. in `.gitignore` and artifact-exclusion patterns.

## Mutable action references

- **Pin all third-party actions to a full commit SHA, not a tag or branch.** Tags are mutable;
  a compromised maintainer can repoint `@v3` to malicious code and every downstream run picks
  it up with no PR. Pin `uses: owner/repo@<sha> # vX.Y.Z` and keep them current with
  Dependabot / Renovate / pinact. (tj-actions/Trivy: 76 of 77 tags repointed to an
  infostealer.)
- **Vet third-party actions before adoption** — verified creator? recently maintained?
  contributor count? OpenSSF Scorecard? An unverified single-maintainer action is a takeover
  target.
- **Prefer actions with fewer transitive dependencies.** SHA-pinning your direct dep doesn't
  help if it pulls its own deps by mutable tag (tj-actions → reviewdog).

## Mutable package dependencies

- **Pin npm/PyPI versions explicitly** (`1.2.3`, not `^1.2.0` / `>=2.0.0`) so a compromised
  new release in-range isn't auto-installed (Ultralytics).
- **Set a minimum release age** where supported (pnpm, yarn — typically 72h) so the community
  can catch a malicious release first. (npm lacks this natively.) Mirrors Mick's 4-day
  dependency cooldown.
- **Verify package provenance / attestations** where the registry supports it (npm via GitHub
  Actions).

## Secrets handling

- **Reference secrets through env vars, never command-line args** (args are visible in
  `/proc`). Set in an `env:` block, use `$SECRET_NAME`.
- **Scope secrets to GitHub Environments** so e.g. `PROD_DB_PASSWORD` is only readable by
  workflows targeting production (Settings → Environments).
- **Scope secrets at the step level, not the job level** — a job-level `env:` secret is
  readable by every step including third-party actions (Shai-Hulud reused workflow-scope
  tokens across victims).
- **Use OIDC for short-lived cloud credentials** (AWS/Azure/GCP) instead of indefinitely-valid
  static secrets — configure a trust relationship to GitHub's OIDC endpoint.
- **Scope npm trusted-publisher rules to a specific workflow file + protected branch**, not the
  whole repo (Mini Shai-Hulud / TanStack: an orphaned commit minted a publish token because the
  rule trusted the entire repo).
- **Require human approval on production-environment runs** for smaller/infrequent-ship teams;
  OIDC + short-lived creds is the scalable version.
- **Never echo secrets, even in debug.** Masking only catches exact matches — base64-encoded or
  split secrets leak. Check for non-empty, don't print the value.

## Runners

- **No self-hosted runners on public repos** — any fork PR can trigger code execution on your
  infrastructure (PyTorch: a trivial PR got root on a self-hosted runner). Use GitHub-hosted
  runners and require approval for outside collaborators.
- **Use ephemeral runners**, not static persistent ones — a static runner carries state
  (poisoned caches, modified binaries) between jobs (Shai-Hulud used persistent runners as a C2
  channel). Use Actions Runner Controller, or `--ephemeral` when registering.
- **Restrict runner network egress to an allowlist** (Harden-Runner / bullfrog on hosted
  runners; firewall rules on self-hosted) to make secret exfiltration harder.

## Token permissions

- **Default `GITHUB_TOKEN` to read-only** at the org/repo level
  (Settings → Actions → General), then grant write explicitly only where needed.
- **Declare explicit `permissions:` blocks** — workflow-level read-only default, and a
  job-level block only on jobs that need more:
  ```yaml
  jobs:
    deploy:
      permissions:
        contents: read
        id-token: write
  ```

## Org and repo settings

- **Disable "Allow GitHub Actions to create and approve pull requests"** — otherwise a
  compromised workflow can approve its own changes. Give Dependabot a dedicated bot reviewer
  instead of enabling org-wide approval.
- **Restrict action sources to verified creators / an allowlist**
  (Settings → Actions → General) so a newly published malicious action can't be adopted
  silently (tj-actions hit 23,000 repos partly from no source restriction).
- **Monitor for unexpected self-hosted runner registrations and new public repos** — stream the
  audit log to a SIEM and alert on `self_hosted_runners.register` and repo-creation events
  (Shai-Hulud registered `SHA1HULUD` runners and created public repos as exfil buckets).
- **Use CODEOWNERS for `.github/workflows/`** so workflow changes (which run with secret access)
  require security-aware review; pair with branch protection requiring CODEOWNERS approval.

# Open-PR triage across the fleet

Use when the user wants every open PR on their repos surveyed with a merge or close verdict
each ("triage my open pull requests", "which of my PRs can I close"). Most of them are
Dependabot bumps, which is why this lives with dependency-upgrade. One named PR is a review,
not a triage.

The whole pass is **read-only until the user approves**. Done when every PR in scope has a
verdict (merge / close / fix / leave) with a one-line reason, and each repo-level finding
(below) is in the report.

## 1. Scope: whose PRs, which repos

```bash
me=$(gh api user -q .login)
orgs=$(gh api user/memberships/orgs --paginate \
  -q '.[] | select(.state == "active" and .role == "admin") | .organization.login')
fields=repository,number,title,author,url,createdAt,isDraft
gh search prs --owner "$me" --state open --archived=false --limit 1000 --json "$fields"
for o in $orgs; do gh search prs --owner "$o" --state open --archived=false --limit 1000 --json "$fields"; done
gh search prs --author @me --state open --limit 1000 --json "$fields"   # elsewhere
```

PRs the user opened on repos they don't administer go in a separate list, **not mine to
merge**: the verdict there is "ping the maintainer", "close" or "leave".

## 2. Bulk-fetch the merge facts into one JSONL

`gh search` doesn't return merge state or checks, so fetch each PR once:

```bash
gh pr view "$n" -R "$repo" --json \
  number,baseRefName,headRefName,mergeable,mergeStateStatus,statusCheckRollup,additions,deletions,changedFiles \
  >> prs.jsonl
```

Retry the fetches that time out or come back `mergeable: UNKNOWN` (GitHub computes it lazily)
before judging anything; a 90-PR sweep loses a few on the first pass. Work from the file, not
from repeated API calls.

## 3. Repo-level checks before PR-level ones

- **Fork with a stale default branch.** For each fork, compare its default branch with
  upstream's (`gh api repos/<repo> -q .parent.full_name`, then the compare API). PRs that target
  a branch hundreds of commits behind upstream are noise: on one fork all 19 Dependabot PRs
  targeted a branch 893 commits behind. The fix is in the fork's settings (sync it, or switch
  Dependabot version updates off there), not in the PRs.
- **Dependabot slots full.** `open-pull-requests-limit` (default 5 per ecosystem, often raised
  to 10) counts open version-update PRs. When a repo sits at its limit, new bumps stop, and
  security fixes queue behind stale ones. Report each repo at its limit.
- **Security updates switched off.** `gh api repos/<repo>/automated-security-fixes` returns
  `enabled`. A repo with it off gets no security PRs at all, whatever the cooldown says.

## 4. One read-only agent per repo group

Fan out (dispatching-parallel-agents), one agent per repo or group of small repos, each with
its rows of `prs.jsonl`. For each PR the agent answers:

- **Is the target version already on the default branch?** (a later bump or a manual upgrade
  landed it) → close as superseded.
- **Does a failing check fail on the default branch too?** Compare with the latest run on the
  default branch (`gh run list -R <repo> -b <default> -L 1`). Failing there too = pre-existing,
  not caused by this PR; failing only here = the bump broke something.
- **Conflicts** (`mergeable: CONFLICTING`): a Dependabot PR can be recreated (the
  `@dependabot recreate` comment, so step 5 applies); a human's PR needs its author.
- **Size** (`additions`/`deletions`/`changedFiles`): a lockfile-only patch bump with green
  checks is a merge; a major goes through the dependency-upgrade major pass instead of a
  blind merge.

The agents change nothing: no merge, no comment, no close.

## 5. Report, then act only on approval

One table per repo: PR, verdict, reason. Repo-level findings first. Then ask before acting.
Close the obvious noise (superseded, stale-fork) only once the user says so. Every comment or
close posted under their account opens with a line saying Claude wrote and posted it on their
behalf. Merges follow the repo's deploy model (SKILL.md Fleet mode step 3): a push-to-deploy
repo is deployed by the merge.

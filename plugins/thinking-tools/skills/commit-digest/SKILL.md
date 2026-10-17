---
name: commit-digest
description: Use on a weekly (or on-demand) cadence to review recent commits from tracked external repos (e.g. dotfiles, framework repos) and optionally Atom/RSS feeds and curated web pages, then pull in improvements applicable to the current project. Opens a separate PR for each implementation and logs skipped suggestions to a dedicated branch for searchable, dedup-safe history. Triggers on "check for new ideas", "what changed upstream", "any improvements to pull in from <repo>", "review dotfiles commits", or as a scheduled agent. Companion to weekly-automation-review, which reviews the local repo's own activity.
---

# Commit Digest

On a regular cadence, review recent commits from tracked external repositories (and optional
Atom/RSS feeds and curated web pages), identify improvements applicable to the current project, implement the relevant
ones as separate PRs, and log everything you skip — so the history is searchable and each run
never re-logs the same suggestion twice.

## Configuration

Override defaults via `.claude/settings.local.json` `"env"`:

| Variable | Default | Meaning |
|---|---|---|
| `COMMIT_DIGEST_REPOS` | `nateberkopec/dotfiles` | Space-separated `owner/repo` list to watch |
| `COMMIT_DIGEST_FEEDS` | `https://epoch-research.github.io/ai-productivity-digest/feed.xml https://upliftai.substack.com/feed https://code.claude.com/docs/en/changelog/rss.xml https://claude.dev/rss.xml` | Space-separated Atom/RSS feed URLs to include |
| `COMMIT_DIGEST_PAGES` | `https://ai-automations-db.vercel.app/database` | Space-separated web pages without a feed (curated lists, databases) to include |
| `COMMIT_DIGEST_DAYS` | `7` | Look-back window in days |
| `COMMIT_DIGEST_LOG_BRANCH` | `claude/skipped-log` | Branch that accumulates skipped-suggestions.md |

## Procedure

### 1. Fetch sources

**Git repos** — for each entry in `COMMIT_DIGEST_REPOS`:
```bash
git clone --depth 50 https://github.com/<owner>/<repo> /tmp/commit-digest/<repo>
git -C /tmp/commit-digest/<repo> log --since="${DAYS} days ago" -p
```
If the clone is blocked by network policy, fall back to `WebFetch` on
`https://github.com/<owner>/<repo>/commits/main` and individual diff pages at
`https://github.com/<owner>/<repo>/commit/<sha>`.

**Atom/RSS feeds** — for each URL in `COMMIT_DIGEST_FEEDS`, fetch and parse items whose
`<published>`, `<updated>` or `<pubDate>` date falls within the look-back window. Read the body
from `<content:encoded>` when `<description>` is empty (the Claude Code changelog feed puts its
release notes there).

**Web pages** — for each URL in `COMMIT_DIGEST_PAGES`, fetch the raw HTML with `curl` rather
than `WebFetch`: a summarising fetch drops the per-entry metadata you filter on. Many such pages
(Next.js and similar) embed their records as JSON in the page; pick out the entries whose date
field (e.g. `dateAdded` on the automations database) falls within the look-back window. If a page
carries no per-entry dates, treat every entry as a candidate and let the log's dedup (step 4) keep
already-seen ones out. Follow an entry's own links (repo, demo) when judging it.

### 2. Evaluate each change

For every commit or feed item, assess three things:
- **Relevance** — does it address a skill, hook, workflow, or tooling area that this project covers?
- **Novelty** — is it already present? Check skills, hooks, README, and the existing `skipped-suggestions.md` log on `COMMIT_DIGEST_LOG_BRANCH`.
- **Applicability** — does it generalise beyond the author's personal environment?

Classify each as one of: **Implement** | **Deferred** | **Rejected** | **Duplicate** | **Out of scope** | **Problem** (source unreachable).

Ruby-specific (Bundler, RubyGems, gem management, Rails tooling) and JS/TS-specific changes count
as in-scope for a polyglot project — don't skip them just because they aren't generic.

### 3. Implement improvements

For each **Implement** decision, open a **separate PR**:

1. Create a feature branch from `main`:
   ```bash
   git checkout main && git pull origin main
   git checkout -b feat/<short-descriptive-name>
   ```
2. Make the change (new skill, hook update, doc improvement, etc.), following the target
   repo's own conventions — read its `CLAUDE.md`/`AGENTS.md` for version-bump rules, doc-sync
   checklists, and where things live. Don't assume a layout; the digest runs against whatever
   project is current.
3. Verify the change the way the target repo verifies itself — run its CI-mirroring checks
   (its pre-commit hook / `hk`, its test suite, its linters). Let the repo's own config tell
   you what to run; a green local run before pushing is the bar.
4. Commit, push, and open a PR with a clear title and description referencing the source
   commit SHA or feed item URL.

### 4. Log everything to the skipped-log branch

**Every run must update the log — even when nothing was skipped:**

```bash
git fetch origin "$COMMIT_DIGEST_LOG_BRANCH" 2>/dev/null \
  && git checkout "$COMMIT_DIGEST_LOG_BRANCH" \
  || git checkout -b "$COMMIT_DIGEST_LOG_BRANCH"
```

Read the existing `skipped-suggestions.md` on that branch **first**. Dedup against the entire
file — do not append any row whose `Suggestion` text is already present anywhere in the history.

Append a dated section:

```markdown
## YYYY-MM-DD

| Suggestion | Source | Decision | Reasoning |
|---|---|---|---|
| … | commit `af41383`, feed item URL, or page entry title + URL | Rejected / Deferred / Duplicate / Out of scope | one-line reason |
```

- If nothing was skipped, add one row that says so and links to every PR opened this run.
- If a source was unreachable, add a row with Decision `Problem`.

Commit and push to `COMMIT_DIGEST_LOG_BRANCH`.

### 5. Open / update the skipped-log PR

If no PR from `COMMIT_DIGEST_LOG_BRANCH` to `main` is open yet, open one with title
`chore: skipped-suggestions log`.

If the PR already exists, the push updates it automatically. Then **add a PR comment**
summarising this run so it surfaces in notifications:

> **Commit-digest run — YYYY-MM-DD**
> Repos: `<list>` · Feeds: `<list or none>` · Pages: `<list or none>` · Window: `<N>` days
> Commits / items reviewed: `<N>` · PRs opened: `<links or "none">` · Rows logged: `<N>`

## Output

Report to the user at the end of each run:
- Repos, feeds and pages scanned, window used
- PRs opened (with links), or "none"
- Count of suggestions logged to the skipped-log branch

## Scheduling

Register as a recurring **weekly remote agent** via the [[schedule]] skill (`CronCreate`).
A Monday-morning cadence pairs naturally with [[weekly-automation-review]] — one reviews
the local repo's own history, the other reviews external repos for ideas to pull in. Each run
appends to the skipped-suggestions log, so the history compounds over time.

---
name: repo-review
description: |
  Whole-repository review/audit of an existing or inherited codebase. Use when the user
  says "review this repository", "audit this codebase", "do a full code review of the
  repo", "what's wrong with this app", "I just inherited this project", or asks for a
  multi-axis sweep (e.g. "review for 1. performance 2. code smells 3. structure"). NOT
  for reviewing a single diff/PR (use the /code-review command) or a one-file change.
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
  - AskUserQuestion
  - Task
  - WebFetch
---

# repo-review

A top-level, **whole-repository** health-check for an existing or inherited codebase. This is
the entry point for *reviewing a repo as a whole* — the stack-agnostic counterpart to
[[rails-audit]] (which does the same for Rails apps). It is deliberately distinct from the
`/code-review` command: `/code-review` reviews the **current diff**; this skill reviews the
**whole repo** across many axes and ends in a written, severity-ranked report.

**The design principle is delegate, don't re-derive.** Wherever a specialist skill or command
already owns an axis, run only the cheap detection here and hand the deep work to it. The new
value this skill adds is (a) the whole-repo scoping, (b) the orchestration across axes, and
(c) the axes nobody else covers (performance, architecture, secrets-scan, suite *runnability*,
genericization).

**Report-only.** This skill diagnoses; it does not change code. Surfacing findings the user
can triage is the goal — auto-fixing across a whole unfamiliar repo is too high blast-radius.
If the user wants fixes after reading the report, that's a separate, scoped follow-up (e.g.
run `/simplify` on a specific area, or the relevant fix skill).

## How to run

1. **Confirm the repo root** and get the lay of the land. Run the preflight to see which
   stacks and surfaces are present and which delegated skills apply:
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/skills/repo-review/scripts/detect_stack.sh" .
   ```
   It reports the language(s), whether there's a web frontend, a CI workflow, a test suite, a
   Dockerfile, a mise/hk dev-env setup, whether it's a Rails app — and any **sub-projects**
   (nested project roots, the monorepo signal).

2. **If it's a monorepo holding several projects** (the preflight's `subprojects` lists more
   than one — e.g. a `frontend/` and a `backend/` each with their own manifest), **offer to
   review each project separately** rather than treating the whole tree as one. Ask the user
   whether to review all of them or pick specific ones; then run the per-project flow (steps
   3–5) **once per chosen project**, rooted at that sub-directory. Review genuinely
   repo-wide concerns (CI workflows, the root dev-env setup, top-level secrets/docs) once at
   the root, and write **one report per project** plus the shared-root findings — a single
   blended report across two unrelated stacks is hard to act on.

3. **Pick the per-project flow by stack:**
   - **Rails app** (`Gemfile` with `gem "rails"` + `app/` + `config/`) → hand the
     Rails-*shaped* axes — correctness, security, performance, schema/indexes, test health,
     architecture, dependencies — to **[[rails-audit]]**, which audits those far more deeply
     than the generic axes here. But repo-review is the **broader umbrella**: rails-audit does
     **not** cover the cross-cutting axes, so **still run** dev-env compliance (7), CI
     supply-chain (9), accessibility (11), docs (12), and genericization (13) yourself, and
     fold rails-audit's findings into the same severity-ranked report. (A future stack may grow
     its own specialist audit; the pattern is the same — delegate the stack-shaped axes, keep
     the cross-cutting ones.)
   - **Any other stack** → work the full axis set below directly.

4. **Run the axes.** They're independent, so for a large repo dispatch them as **parallel
   subagents** (one per axis, see [[dispatching-parallel-agents]]) and collect their findings —
   this is how you cover a big codebase without one context holding all of it. For every
   finding, record four things (no evidence, no finding — see Common mistakes):
   - **Severity** — 🔴 high (security / data loss / broken in prod), 🟡 medium (tech debt,
     performance, missing safety net), 🟢 low (polish, style, docs).
   - **Where** — `file:line` (point at real code, not generalities).
   - **Finding + evidence** — what's wrong and the grep hit / command output that shows it.
   - **Fix** — the concrete remediation, and **→ which skill/command** owns the deep fix.

5. **Produce the report** (see [Producing the report](#producing-the-report)).

## Axis set

Detection lives here; the authoritative checklist for a delegated axis lives in the named
skill — run the quick detection, then note the handoff (shown as "→ [[skill]]" / "→ /command").

### Always

**1. Correctness / bugs → `/code-review`**
The `/code-review` command is the authoritative bug finder. It is diff-scoped by design, so to
cover a whole repo either run it against the full history range (`/code-review` after staging a
review of the working tree) or, for an unfamiliar repo with no meaningful diff, spot-review the
riskiest modules by hand and note that a diff-scoped pass should run on future changes. Record
its high-confidence findings here.

**2. Code smells / refactor → `/simplify`**
Duplication, dead code, over-complex functions, poor naming. `/simplify` is the authoritative
cleanup pass (quality, not bugs). In report-only mode, don't apply it — run a read-only review
and record what it *would* change so the user can decide. Cheap signals:
```bash
grep -rinE 'todo|fixme|hack|xxx' --include='*.*' . 2>/dev/null | wc -l   # tech-debt markers
```

**3. Performance**
The axis no other skill owns generically. Look for the language-agnostic footguns: N+1-shaped
loops issuing per-iteration I/O (DB/HTTP calls inside `for`/`map`), unbounded result sets,
missing pagination, synchronous work that belongs in a job/queue, and absent timeouts on
network clients (a degraded dependency with a 30s default timeout can take the whole app down).
Cite the file:line and explain the mechanism.

**4. Architecture / structure**
Cheap size heuristics surface the files most likely to hide problems:
```bash
find . -type f \( -name '*.py' -o -name '*.rb' -o -name '*.ts' -o -name '*.js' -o -name '*.go' \) \
  -not -path '*/node_modules/*' -not -path '*/.git/*' -exec wc -l {} + 2>/dev/null | sort -rn | head -15
```
Flag god-files, circular/leaky module boundaries, business logic in the wrong layer
(controllers/views/handlers doing model work), and missing separation of concerns. Keep it to
structural observations — naming/style churn is axis 2.

**5. Application security**
Code-level vulnerabilities: string-interpolated SQL, command injection (`os.system`/backticks
on user input), unsafe deserialization, missing authz checks, unvalidated redirects, secrets
logged. Cheap signals:
```bash
grep -rnE '(execute|query)\(.*[%+].*(params|request|input|argv)' --include='*.*' . 2>/dev/null | head
grep -rnE 'os\.system|subprocess.*shell=True|eval\(|exec\(' --include='*.py' . 2>/dev/null | head
```

**6. Test health — coverage *and* runnability**
Two distinct checks. First, **does the suite even run from a clean checkout?** A suite that
needs a Postgres role, a browser, or unset env that isn't provisioned is a real gap — note
exactly what's missing (this is the spotify-tools `role "mick" does not exist` class of
problem). Don't report coverage on a suite you couldn't run. Second, coverage and staleness:
```bash
ls -d test tests spec __tests__ 2>/dev/null
git log -1 --pretty=format:'%ci %s' -- test tests spec 2>/dev/null; echo
```
No suite, or tests last touched long before app code → flag it. For the deep testing strategy
on a Rails repo this would route to rails-testing, but this skill only reaches non-Rails repos
(Rails goes to rails-audit at step 2).

**7. Dev-env / tooling compliance → [[dev-env-setup]]**
Is the repo set up to the standard — `mise.toml` pinning tools, an `hk` pre-commit hook running
linters + gitleaks, a CI workflow mirroring them, and project docs recording pinned versions?
Run the cheap detection, then hand the gap analysis + setup to dev-env-setup:
```bash
ls mise.toml hk.pkl .pre-commit-config.yaml 2>/dev/null
grep -l DEV_ENV_VERSION mise.toml 2>/dev/null && echo "dev-env standard tracked"
```

**8. Dependencies — outdated + known vulns → [[dependency-upgrade]]**
Flag stale pins and known CVEs; **don't bump** (report-only — bumping is dependency-upgrade's
job, run separately). Use that skill's read-only preflight to list what's outdated:
```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/dependency-upgrade/scripts/upgrade_inventory.sh" . --run 2>/dev/null
```
Record the outdated set and any audit advisories (`npm audit`, `pip-audit`, `bundler-audit`) as
findings; the fix is "run [[dependency-upgrade]]".

**9. CI / supply-chain security → [[github-actions]]**
For each `.github/workflows/*.yml`: are third-party actions **SHA-pinned** (not `@v4`), is the
`GITHUB_TOKEN` scoped with a read-only `permissions:` block, and are there
`pull_request_target` / script-injection gaps? Run the quick check, then route the hardening to
github-actions:
```bash
ls .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null
grep -rnE 'uses:\s+[^@]+@v[0-9]' .github/workflows/ 2>/dev/null | head   # unpinned (tag, not SHA)
```

**10. Secrets hygiene**
The highest-impact, easiest-to-miss finding: plaintext secrets in committed files, and `.env` /
key files not gitignored. (This is the standing concern behind the `secret-plaintext-reminder`
hook; the fix path is [[env-to-fnox]].)
```bash
grep -rinE '(password|secret|api[_-]?key|access[_-]?key|token)\s*[:=]\s*["'\''][^"'\'' ]{8,}' \
  --include='*.*' . 2>/dev/null | grep -vE '\.env\.example|example|placeholder|xxx|your_' | head
grep -nE '\.env($|[^.])|master\.key|credentials' .gitignore 2>/dev/null || echo "check .gitignore covers .env / keys"
```

### Conditional — only when the repo matches

**11. Accessibility → [[accessibility]] — web/frontend repos only**
Only fire when the preflight found frontend files (`.html`/`.erb`/`.jsx`/`.tsx`/`.vue`). Run
the accessibility skill's heuristic audit on the changed/representative templates; skip
entirely for a CLI/library/backend-only repo.

**12. Documentation health**
README quality (clear what/why/how to run — see [[github-readme]]), a `CLAUDE.md` that matches
reality (stale pinned-version mentions, dead instructions), and orphaned docs. Low severity
unless onboarding is genuinely blocked.

**13. Genericization / personal-reference leakage — opt-in**
Only when the user intends to **share or publish** the repo (ask if unclear). Scan for
hardcoded personal/setup-specific references — usernames, absolute home paths, machine names,
private URLs — that would break a generic clone:
```bash
grep -rnE '/(home|Users)/[a-z]+|[a-z_]+@[a-z.]+|hardcoded-owner-name' \
  --include='*.*' . 2>/dev/null | grep -vE '\.git/' | head
```

### Out of scope

- **Database/schema audit** — arrives via the Rails → [[rails-audit]] delegation (which routes
  to rails-database-performance). Not a separate generic axis here.
- **Applying fixes** — report-only by design. The report names the fix skill per finding.

## Producing the report

Write a single report grouped by severity (🔴 → 🟡 → 🟢) to
`plans/repo-review-YYYY-MM-DD.md` in the repo. Each item:

```
### 🔴 <short title>
- **Where:** path/to/file.ext:42  (or: package.json, .github/workflows/ci.yml)
- **Finding:** what's wrong, with the evidence (the grep hit / command output / file:line).
- **Impact:** why it matters (security / perf / maintainability / onboarding).
- **Fix:** the concrete change, and **→ which skill/command** to run for the deep fix.
```

Close with a one-paragraph **summary**: overall health, the top 3 things to fix first, and the
recommended order (security & exposed secrets before refactors). Because the report is on disk,
a follow-up "continue reviewing" / "fix the next one" picks up from it instead of re-deriving
scope.

## Quick reference

| # | Axis | Detection signal | Owner |
|---|---|---|---|
| 1 | Correctness | risky modules, diff range | `/code-review` |
| 2 | Code smells | duplication, dead code, TODO markers | `/simplify` |
| 3 | Performance | per-iteration I/O, missing timeouts/pagination | — (this skill) |
| 4 | Architecture | fattest files, layer leaks | — (this skill) |
| 5 | App security | interpolated SQL, shell/eval on input | — (this skill) |
| 6 | Test health | suite runs from clean checkout? staleness | — (this skill) |
| 7 | Dev-env | mise/hk/CI/gitleaks present? | [[dev-env-setup]] |
| 8 | Dependencies | outdated pins, CVEs | [[dependency-upgrade]] |
| 9 | CI supply-chain | actions SHA-pinned, token perms | [[github-actions]] |
| 10 | Secrets | plaintext creds, `.env` gitignored | [[env-to-fnox]] |
| 11 | Accessibility* | frontend files present | [[accessibility]] |
| 12 | Docs | README/CLAUDE.md accuracy | [[github-readme]] |
| 13 | Genericization* | personal paths/usernames | — (this skill) |

\* conditional — fire only when the repo matches.

## Common mistakes

- **Reporting from memory instead of running the detection.** Every finding cites a real grep
  hit / command output / `file:line`. No evidence, no finding.
- **Re-deriving a delegated axis inline.** Axes 1, 2, 7, 8, 9, 11, 12 have an owner — run the
  cheap detection, then hand off. Don't reimplement dev-env-setup or github-actions here.
- **Re-running rails-audit's axes on a Rails repo — or, the opposite, stopping at rails-audit.**
  Hand the Rails-shaped axes (correctness, security, perf, schema, tests, architecture, deps) to
  [[rails-audit]] — don't re-derive those. But it doesn't cover the cross-cutting axes (dev-env,
  CI supply-chain, accessibility, docs, genericization), so don't stop there either; run those
  yourself and merge the reports.
- **Blending unrelated sub-projects into one report.** A monorepo's `frontend/` and `backend/`
  get reviewed (and reported) separately — see step 2. One mixed-stack report is hard to act on.
- **Applying fixes.** This skill is report-only. Fixes are a separate, scoped follow-up.
- **Reporting coverage on a suite you couldn't run.** Suite runnability is its own finding —
  surface the missing infra (DB role, service, env) rather than glossing over it.
- **Findings without severity or location.** A report the user can't triage is noise. Lead with
  🔴 security/secrets; refactors and style come last.

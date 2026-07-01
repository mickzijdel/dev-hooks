# Skipped Suggestions Log

Maintained by the `commit-digest` skill. Each dated section records every suggestion reviewed
that was **not** implemented, plus a "nothing skipped" row (with PR links) for runs where
everything was acted on.

Dedup rule: a suggestion already present anywhere in this file is never re-logged.

---

## 2026-07-01 (Run 9)

Sources scanned:
- `nateberkopec/dotfiles` — commits since 2026-06-25: none new (most recent commits on `main`, `0eddfc2`/`54757ec`/`270dfe8` from Jun 25, already reviewed in Run 8)
- Atom feed: https://epoch-research.github.io/ai-productivity-digest/feed.xml — new items 2026-06-29 to 2026-07-01 (7 items)

PRs opened this run:
- rails-toolkit [#6 feat: add rails-mailers skill](https://github.com/mickzijdel/rails-toolkit/pull/6) — own idea (gap: no dedicated ActionMailer guide despite deep coverage of jobs/API/migrations)

| Suggestion | Source | Decision | Reasoning |
|---|---|---|---|
| Add `rails-mailers` skill (own idea) | own idea | **Implement** | rails-toolkit PR #6 opened. Shallow mailers triggered from commit hooks, multipart+i18n templates, previews, `letter_opener` local delivery, delivery-job error handling (reusing `rails-jobs` Pattern 7), bounce/complaint suppression, and mailer testing patterns. |
| Chain agent slash-commands (`/ultracode` → `/deep-research` → one-shot implementation → `/code-review` → PR) to build small personal tools | feed item 2026-06-30 (https://x.com/nibzard/status/2072070854825963782) | Duplicate | Composes existing Claude Code skills already present in this session's toolset (`deep-research`, `code-review`); no new hook/skill capability to add. |
| Ship agent PRs from a single Slack message by layering CI, lint, security scans, e2e tests, and an automated QA bot that records GIFs of itself testing | feed item 2026-06-30 (https://x.com/alvinsng/status/2072078751010316372) | Deferred | The CI/lint/test-before-ship half is already covered by `verify-work.sh` + `but-for-real`; the GIF-recording QA bot needs browser-recording infra beyond a shell hook's scope, and the Slack trigger is environment-specific. Revisit if a lightweight "attach visual proof of testing" pattern emerges for `verify-work.sh`. |
| Five concrete agent workflows: inspect codebase, monitor Slack for customer signal, prep meetings, pressure-test decisions, build throwaway agents for messy ops | feed item 2026-06-29 (https://x.com/petergyang/status/2071690793899974773) | Duplicate / Out of scope | "Pressure-test decisions" is covered by `premortem` + `board`; Slack monitoring, meeting prep, and throwaway ops agents are business/personal workflows with no dev-hook surface. |
| When going AI-first, layer small autonomous agent loops (triage, PR review, comment-to-commit) onto your existing process incrementally rather than rebuilding from scratch | feed item 2026-06-29 (https://x.com/dexhorthy/status/2071649145077874983) | Duplicate | `weekly-automation-review` already recommends 1–2 incremental automation opportunities per run rather than a wholesale rebuild. |
| Build a personal 4-part model benchmark (notes→PRD, prototypes, bug hunting, persona) to decide whether to adopt a new LLM instead of vibe-checking | feed item 2026-06-30 (https://x.com/clairevo/status/2072101101021847962) | Out of scope | About evaluating and switching underlying LLM providers/models; this plugin suite is Claude Code-specific tooling, not a multi-model evaluation harness. |
| Prep talks by recording a draft video, then have Claude Code convert it to a Notion page with slides+transcript and attach reviewer feedback as inline comments | feed item 2026-07-01 (https://x.com/geoffreylitt/status/2072110805089435973) | Out of scope | Personal talk-prep/Notion workflow; no dev-workflow hook surface. |
| Use Riverside's Claude MCP integration to record, transcript-edit, auto-clip, draft a newsletter, and schedule social posts in one agentic workflow | feed item 2026-06-30 (https://x.com/itsolelehmann/status/2072031800134943078) | Out of scope | Podcast/media production and social-scheduling workflow; not dev. |

---

## 2026-06-29 (Run 8)

Sources scanned:
- `nateberkopec/dotfiles` — commits since 2026-06-25: `0eddfc2` (merge #457), `54757ec`, `270dfe8` (all Jun 25)
- Atom feed: https://epoch-research.github.io/ai-productivity-digest/feed.xml — new items 2026-06-26 to 2026-06-29 (16 items)

PRs opened this run:
- dev-hooks [#13 feat(thinking-tools): add quiz-me skill](https://github.com/mickzijdel/dev-hooks/pull/13) — inspired by geoffreylitt feed item 2026-06-28
- rails-toolkit [#5 feat: add rails-logging skill](https://github.com/mickzijdel/rails-toolkit/pull/5) — own idea (gap: no dedicated observability/logging guide)

| Suggestion | Source | Decision | Reasoning |
|---|---|---|---|
| Have coding agents quiz developers on their code changes | feed item 2026-06-28 (https://x.com/geoffreylitt/status/2071319131144790064) | **Implement** | dev-hooks PR #13 opened. Added `quiz-me` to thinking-tools: surveys diff, constructs 4–6 targeted questions (recall/reasoning/implication/trace/edge-case), presents one at a time, scores and explains each answer, ends with a comprehension rating. |
| Add `rails-logging` skill (own idea) | own idea | **Implement** | rails-toolkit PR #5 opened. No dedicated observability guide existed; `rails-performance` covers ETags/fragment caching but not Lograge, tagged logging, Sentry integration, health check endpoints, or log rotation. |
| Speed up system package checks (bulk `brew list`) | dotfiles commit `270dfe8` (Jun 25) | Out of scope | macOS Homebrew-specific optimization; dev-hooks uses mise for all tool management. |
| Merge PR #457 (bulk system package checks) | dotfiles commit `0eddfc2` (Jun 25) | Out of scope | Merge commit for `270dfe8`; same reasoning. |
| Pin fish version in integration tests (redux) | dotfiles commit `54757ec` (Jun 25) | Duplicate | Same commit message as `ecec1d4` already logged in Run 7; fish-specific regardless. |
| Notion + Cursor task decomposition into a Notion board | feed item 2026-06-26 (https://x.com/geoffreylitt/status/2070621331838918802) | Out of scope | Notion-specific integration; no Claude Code plugin surface. |
| Configure agents to push status updates rather than being polled | feed item 2026-06-26 (https://x.com/intellectronica/status/2070458678575346008) | Deferred | Interesting inversion (push vs poll) but no concrete hook trigger. `commit-digest` + `weekly-automation-review` already use PushNotification for agent-initiated updates. Revisit if a generalized "agent pushes to X" sink pattern emerges. |
| Browser agents complete vendor signup flows | feed item 2026-06-26 (https://x.com/thdxr/status/2071367699955945704) | Out of scope | Browser automation for account creation; no dev-workflow hook surface. |
| Agents auto-update changelogs from PRs, monitor Sentry errors, review code, test workflows | feed item 2026-06-26 (https://x.com/amirmxt/status/2070326611715461391) | Deferred | Four-part tip; Sentry monitoring addressed in rails-logging PR #5. Auto-changelog from PRs has no hook trigger (Stop hooks don't see merged PRs). Code review covered by `review-reminder.sh`; workflow testing by `verify-work.sh`. |
| Browser trip research (flight/hotel scraping) | feed item 2026-06-26 (https://x.com/petergyang/status/2070353698140958818) | Out of scope | Personal travel planning; no dev-workflow surface. |
| GitHub Copilot code review now reads AGENTS.md | feed item 2026-06-27 (https://x.com/github/status/2070980235873694138) | Deferred | dev-env-setup already documents the AGENTS.md/CLAUDE.md symlink convention; worth noting Copilot reads AGENTS.md in the skill when it's next touched, but too small for its own PR now. |
| Health data automation digest via MCP server | feed item 2026-06-27 (https://x.com/petergyang/status/2070906940352520477) | Out of scope | Personal health/wearable data workflow; not dev. |
| Run an agent team via Telegram with scheduled tasks and escalation | feed item 2026-06-28 (https://x.com/Saboo_Shubham_/status/2071293463447097625) | Out of scope | Telegram-specific agent orchestration; no Claude Code equivalent. |
| PMs grant agents read-only repository access to track PRs | feed item 2026-06-28 (https://x.com/petergyang/status/2071292628302434361) | Out of scope | Workflow/role tip for managers; no hook surface. |
| Use Codex desktop for remote agent work (syncs sessions across devices) | feed item 2026-06-28 (https://x.com/HamelHusain/status/2071266938375016515) | Out of scope | Codex (ChatGPT) desktop feature; no Claude Code equivalent. |
| Unified agent notification aggregator (centralized dashboard) | feed item 2026-06-28 (https://x.com/intellectronica/status/2071175551440875582) | Out of scope | Personal dashboard concept; no hook/skill surface in a code-workflow plugin. |
| Binary pass/fail LLM eval judges instead of numeric scales | feed item 2026-06-28 (https://x.com/HamelHusain/status/2071049082723020900) | Out of scope | LLM evaluation methodology; no dev-workflow hook surface. |

---

## 2026-06-25 (Run 7)

Sources scanned:
- `nateberkopec/dotfiles` — commits 2026-06-18 to 2026-06-25: `31a9810` (merge), `0a15edd`, `798875a` (merge), `08a905c`, `ecec1d4`, `2d21bb6`, `eddeeda`, `ddac100` (merge), `9f2cedd` (merge), `c92dc1d`, `a669b5f`, `0524b66` (merge), `bca6e90`, `b75e646` (merge), `e78c087` (merge), `8ac49b7` (merge), `d1c1fc9` (merge), `68f88d6`, `cc2f46b`, `8be6615`, `8835cdb`, `efbb3e2`, `03bc379`, `dd469f7` (merge), `fa6b927`, `4d203e3` (merge), `fcadb4d` (merge), `59e7c25`, `c17c16a`, `dd9f6ff` (merge), `e64ae06` (merge), `09dd7c4` (merge), `6f08a99`, `b01bd96` (merge), `32d8898` (merge)
- Atom feed: https://epoch-research.github.io/ai-productivity-digest/feed.xml — new items 2026-06-21 to 2026-06-25 (21 items; includes 2 Jun 21 items not captured in Run 6)

PRs opened this run:
- dev-hooks [#12 feat(thinking-tools): add adr skill](https://github.com/mickzijdel/dev-hooks/pull/12) — inspired by nateberkopec/dotfiles commit `bca6e90` ("Add ADRs for project philosophy")
- rails-toolkit [#4 feat: add rails-migrations skill](https://github.com/mickzijdel/rails-toolkit/pull/4) — own idea (gap: toolkit covers performance/DB performance but had no dedicated safe migration guide)

| Suggestion | Source | Decision | Reasoning |
|---|---|---|---|
| Add ADRs for project philosophy | dotfiles commit `bca6e90` (Jun 22) | **Implement** | dev-hooks PR #12 opened. Added `adr` skill to thinking-tools: Nygard format (Context / Decision / Consequences), storage in `docs/decisions/`, CLAUDE.md integration tip, composition with `board` / `premortem` / `agent-handoff`. |
| Add `rails-migrations` skill (own idea) | own idea | **Implement** | rails-toolkit PR #4 opened. `rails-core` rule 5 covers the nullable-column multi-step; added full treatment: `strong_migrations`, concurrent indexes, `ignored_columns` column removal, dual-write column rename, `in_batches` backfills, column type changes, reversibility. |
| Update CLAUDE.md | dotfiles commit `c92dc1d` (Jun 22) | Out of scope | Personal dotfiles Claude config; no generalizable hook surface. |
| Remove beautiful mermaid skill | dotfiles commit `a669b5f` (Jun 22) | Out of scope | dev-hooks does not include this skill; no change needed. |
| Run aube migration with aube on PATH | dotfiles commit `68f88d6` (Jun 22) | Deferred | aube adoption deferred in Runs 2, 3, 4; changing the invocation path doesn't change the feature assessment. |
| Limit brew upgrades to managed formulae | dotfiles commit `cc2f46b` (Jun 22) | Out of scope | macOS Homebrew-specific; dev-hooks uses mise. |
| Raise on migration command failures | dotfiles commit `8be6615` (Jun 22) | Out of scope | Nate's dotfiles runner framework; not related to Rails migrations or dev-hooks hooks. |
| Skip migrations on fresh machines | dotfiles commit `8835cdb` (Jun 22) | Out of scope | Nate's dotfiles runner; same as above. |
| Skip system packages when installed | dotfiles commit `efbb3e2` (Jun 22) | Out of scope | System package management outside dev-env-setup scope. |
| Add CI no-op convergence test | dotfiles commit `03bc379` (Jun 22) | Deferred | Verifying that `dev_env_check.sh` is idempotent (running twice produces no changes) is sound, but adding a full convergence run to CI requires provisioning a dev environment inside CI — more infrastructure than this skill adds alone. Revisit if a lightweight check-mode emerges for `dev_env_check.sh`. |
| Refactor duplicated launchctl checks | dotfiles commit `fa6b927` (Jun 22) | Out of scope | macOS launchctl-specific helper refactoring. |
| Route runner validation through collect_errors | dotfiles commit `c17c16a` (Jun 22) | Out of scope | Nate's Ruby dotfiles runner internals. |
| Extract shared CommandHelpers and PlatformRestrictable modules | dotfiles commit `6f08a99` (Jun 22) | Out of scope | Nate's Ruby dotfiles runner internals. |
| dotf-lockfile | dotfiles commit `b01bd96` (Jun 22) | Duplicate | dev-hooks uses `mise.lock` for pinned tool checksums/Cosign/SLSA — same goal. |
| find-fish-path memoization | dotfiles commit `32d8898` (Jun 22) | Out of scope | Fish shell-specific. |
| dotf-upgrade-mise-updates | dotfiles commit `09dd7c4` (Jun 22) | Out of scope | Nate's dotfiles runner handling of `mise` upgrades; not applicable. |
| shared-config-injection | dotfiles commit `dd9f6ff` (Jun 22) | Out of scope | Nate's Ruby dotfiles runner internals. |
| Pin fish to 4.7.1 | dotfiles commit `0a15edd` (Jun 25) | Out of scope | Fish shell-specific. |
| Pin fish version in integration tests | dotfiles commit `ecec1d4` (Jun 25) | Out of scope | Fish shell-specific. |
| Skip macOS update notice step in CI | dotfiles commit `08a905c` (Jun 25) | Out of scope | macOS-specific CI tweak. |
| Allow GPG signing fingerprints in secret scan | dotfiles commit `2d21bb6` (Jun 25) | Out of scope | Personal GPG fingerprint allowlist for gitleaks; dev-hooks' `.gitleaks.toml` template does not include personal signing keys. |
| Update Git signing key | dotfiles commit `eddeeda` (Jun 25) | Out of scope | Personal Git config. |
| Agents can self-poison context via stray words written into your repo; watch for terms the agent keeps reintroducing and blocklist them | feed item 2026-06-25 (https://x.com/nibzard/status/2070065202091966671) | Deferred | Genuine risk in hook-heavy repos where agents write to CLAUDE.md and skill files. No concrete hook surface — a hook can't enumerate reintroduced terms without project-specific blocklists. Revisit if a PostToolUse(Write/Edit) pattern emerges that can check for placeholder or meta-instruction text leaking into production files. |
| Use Codex with the Chrome tool and a /goal command to triage and clean out your LinkedIn inbox automatically | feed item 2026-06-24 (https://x.com/clairevo/status/2069843321032466720) | Out of scope | LinkedIn/Codex-specific; no dev-workflow hook surface. |
| Run open-weights GLM 5.2 as your default in Claude Code and Cursor via OpenRouter for near-Opus quality at a fraction of the cost | feed item 2026-06-24 (https://x.com/clairevo/status/2069828122640548204) | Rejected | About replacing Claude with non-Claude models inside Claude Code; outside the scope of a Claude Code plugin. |
| Three reusable AI workflows: nightly Obsidian web-clipper digest, weekly cron security/codebase audits, and scraped "domain expert" skills for new tools | feed item 2026-06-24 (https://x.com/chasing_next/status/2069823113202684309) | Deferred | Security audits covered by dev-env-setup CI templates + `rails-audit`; weekly reviews by `commit-digest` + `weekly-automation-review`. The "scraped domain expert skills" technique (building skills from a tool's own docs automatically) is interesting but meta-applies to how this plugin is built rather than being a skill in it. Revisit if a concrete target emerges. |
| Gemini 3.5 Flash computer use can audit a docs page by navigating it, running its code snippets, and returning an issues report | feed item 2026-06-24 (https://x.com/_philschmid/status/2069819170477293863) | Out of scope | Gemini-specific feature; no Claude Code equivalent. |
| Eight concrete ways to use Claude-in-Slack as a teammate | feed item 2026-06-24 (https://x.com/itsolelehmann/status/2069704768138744200) | Out of scope | Slack integration patterns; no dev-workflow hook surface. |
| Build org-specific Claude skills (e.g., a /treasury skill) to automate domain workflows | feed item 2026-06-23 (https://x.com/emollick/status/2069486790075908261) | Out of scope | The concept is exactly what dev-hooks already does; no new hook surface. |
| Stop iterating on one-off prompts; build a reusable artifact (rubric, checklist, PRD template) and version-control edits based on eval results | feed item 2026-06-23 (https://x.com/Saboo_Shubham_/status/2069473303992115607) | Deferred | Sound prompt-engineering principle; no concrete hook trigger (can't fire on "iterate on a prompt"). Revisit if a "skill eval" pattern emerges. |
| Use ChatGPT/Claude browser & computer-use plugins for real-world chores like taxes, legal paperwork, shopping, and ticket buying | feed item 2026-06-23 (https://x.com/0xSero/status/2069472414736765107) | Out of scope | Consumer task automation; no dev-workflow hook surface. |
| A reusable sales-call workflow: auto-transcribe with Tactiq, then run a structured prompt extracting pains, objections, fit, and follow-ups | feed item 2026-06-23 (https://x.com/chasing_next/status/2069454029420397047) | Out of scope | Sales/CRM workflow; not dev. |
| Disable Claude Code's runaway deep-research skill by adding Skill(skill:deep-research) to the deny list in ~/.claude/settings.json | feed item 2026-06-23 (https://x.com/kr0der/status/2069392784919015557) | Out of scope | Meta-tip about managing Claude Code skill permissions via settings.json; already supported by Claude Code's built-in allowlist system. No plugin hook surface. |
| Store AI agent context docs (plans, research) outside your git repo so they survive branch switches and stay easy to share/archive | feed item 2026-06-22 (https://x.com/dexhorthy/status/2069143768901791934) | Deferred | Interesting complement to `plan.md`-in-repo, but contradicts the current agent-handoff pattern (plan.md lives in the repo so it's part of the git context Claude reads). Revisit if a persistent out-of-repo context store (e.g. `~/.claude/project-context/`) becomes a first-class Claude Code feature. |
| Install Gemini's official 'skills' package in Claude Code/Cursor/Codex to give agents up-to-date API rules and auto-migrate apps with one prompt | feed item 2026-06-22 (https://x.com/_philschmid/status/2069137029359645007) | Out of scope | Gemini-specific skills package; not applicable to a Claude Code plugin. |
| For agentic work on huge codebases, use a goal/loop pattern with a verifier to kill false positives | feed item 2026-06-22 (https://x.com/clairevo/status/2069129613427831169) | Duplicate | Covered by `but-for-real` + `verify-work.sh`. |
| Generate videos in Codex/Claude Code by installing HyperFrames, gathering assets, and writing a frame.md | feed item 2026-06-22 (https://x.com/petergyang/status/2069074216406954034) | Out of scope | Video generation workflow; not dev. |
| Use Codex's /side thread to check progress, get summaries of done/blocked work, then push refined instructions back to the main thread | feed item 2026-06-22 (https://x.com/gabrielchua/status/2069063939908841626) | Out of scope | Codex (ChatGPT desktop) feature; no Claude Code equivalent. |
| OpenAI's moderation endpoint is free for both text and images — useful for adding content safety checks to AI features at no cost | feed item 2026-06-22 (https://x.com/kr0der/status/2068997679229927848) | Out of scope | OpenAI-specific API; no bearing on a dev-workflow hooks plugin. |
| For agentic video/visual generation, have the LLM output HTML/CSS/JS as the substrate — LLMs lack visual intelligence but express aesthetics natively in code | feed item 2026-06-21 (https://x.com/petergyang/status/2068755908319236338) | Out of scope | Visual/design methodology; no dev-workflow hook surface. |
| For non-code knowledge work in agentic tools, prompt to preserve process artifacts (alternatives, failed attempts, learning loops), not just final deliverables | feed item 2026-06-21 (https://x.com/emollick/status/2068729258176819253) | Deferred | Principle complements `memory-reminder.sh` (captures structured memories) and `agent-handoff` (plan.md coordination). A concrete extension would be adding guidance to capture failed attempts in the memory format. Revisit if a specific "capture-what-didn't-work" event pattern is identified. |

---

## 2026-06-21 (Run 6)

Sources scanned:
- `nateberkopec/dotfiles` — commits 2026-06-18 to 2026-06-21: `bf75247`, `4f9464f`, `baba474`, `e8cca35`, `6f0a951`, `fa7a72d`, `6678423`, `a468864`, `13d1dcf`, `77c479a`, `bce944f`, `4daad56`, `a44493f`, `09af58d`, `fac3b04`, `920b98a`, `1fb8f31`, `8fc04ef`, `9ad0c0d`, `897e500`, `2516a51`, `777ecd5`, `094b0dd`, `041aca7`, `ca5138d` (all since Run 5; heavy activity around `mise system`, fish, GitHub Actions pinning, aqua)
- Atom feed: https://epoch-research.github.io/ai-productivity-digest/feed.xml — new items 2026-06-18 to 2026-06-21 (17 items)

PRs opened this run:
- dev-hooks [#11 feat(thinking-tools): add grill-me adversarial code review skill](https://github.com/mickzijdel/dev-hooks/pull/11)
- rails-toolkit [#3 feat: add rails-action-mailer skill](https://github.com/mickzijdel/rails-toolkit/pull/3) — own idea (gap: `rails-jobs` references mailers; no dedicated guide existed)

| Suggestion | Source | Decision | Reasoning |
|---|---|---|---|
| Matt Pocock's `/grill-me` skill: parallel adversarial subagents attack code for bugs, edge cases, and security holes, then a chairman synthesises | feed item 2026-06-21 (https://x.com/ivanfioravanti/status/2068592504023461967) | **Implement** | dev-hooks PR #11 opened. Added `grill-me` skill to thinking-tools: Bug Hunter / Security Auditor / Edge-Case Seeker / Performance Skeptic panel, distinct from `code-simplifier` (style) and `board` (idea critique). |
| Add `rails-action-mailer` skill (own idea) | own idea | **Implement** | rails-toolkit PR #3 opened. `rails-jobs` already references `ExportMailer.completed(self).deliver_later` and `AccountMailer.invitation(self)` without a companion guide. Added 9 patterns: shallow mailers, `deliver_later` everywhere, multi-part templates, `ApplicationMailer` defaults, URL generation, previews, testing, storage-URL attachments, SMTP credentials. |
| Fix `mise system` package commands | dotfiles commits `bf75247`/`4f9464f` (Jun 21) | Out of scope | macOS `mise system` command bugs; dev-env-setup standard focuses on project-level tool management, not system packages. |
| Fix fish path lookup when `mise fish` is missing | dotfiles commits `baba474`/`e8cca35` (Jun 20) | Out of scope | fish shell-specific; dev-hooks targets bash/zsh. |
| Move CLI packages to aqua | dotfiles commit `fa7a72d` (Jun 20) | Deferred | aqua is a provenance-checking tool manager; dev-env-setup standard uses mise for all tool pinning and already achieves the same provenance goals via `mise.lock` + Cosign/SLSA (v11+). Same reasoning as the aube deferred entries in Runs 2 and 3. |
| Install fish with mise on macOS | dotfiles commits `6678423`/`a468864` (Jun 20) | Out of scope | fish shell-specific. |
| Skip fish check without fish in non-admin CI / Keep non-admin integration lightweight | dotfiles commits `13d1dcf`/`bce944f`/`4daad56` (Jun 20) | Out of scope | Nate's non-admin CI variant; dev-hooks CI has no such mode. |
| Teach dev env audit to pin GitHub Actions | dotfiles commits `77c479a`/`a44493f` (Jun 20) | Deferred | dev-env-setup already has `check_action_refs.sh` (a separate compliance script that `git ls-remote`s every `uses:` pin) plus the `ci-action-ref-reminder` hook. Integrating pinning into `dev_env_check.sh`'s compliance output would be nice but duplicates existing coverage. Revisit if the checker grows a machine-readable report format. |
| Pin GitHub Actions to SHAs | dotfiles commit `920b98a` (Jun 20) | Duplicate | Same theme as `a44493f`; both already covered by `check_action_refs.sh` + `ci-action-ref-reminder`. |
| Retry Homebrew bundle installs | dotfiles commit `09af58d` (Jun 20) | Out of scope | macOS Homebrew-specific; dev-hooks uses mise. |
| Simplify large file check (replace Ruby script with awk one-liner) | dotfiles commits `fac3b04`/`9ad0c0d` (Jun 20) | Out of scope | dev-hooks already uses the `check-added-large-files` hk builtin, which is already simpler than Nate's old approach. No change needed. |
| Fallback when `mise system` is unavailable | dotfiles commit `1fb8f31` (Jun 20) | Out of scope | macOS `mise system` fallback; same as `4f9464f`. |
| Use `mise system` for system package installs | dotfiles commits `8fc04ef`/`897e500` (Jun 20) | Out of scope | System-package management is outside dev-env-setup's scope. |
| Extract home file set resolution | dotfiles commit `2516a51` (Jun 20) | Out of scope | Refactoring of Nate's dotfiles runner internals. |
| Route web providers back to Exa | dotfiles commits `777ecd5`/`041aca7` (Jun 20) | Out of scope | Pi agent web provider config; not applicable. |
| Remove missing repo intent doc reference | dotfiles commits `094b0dd`/`ca5138d` (Jun 20) | Out of scope | Documentation cleanup in Nate's dotfiles skill; not applicable. |
| Use cron jobs to trigger Codex `/goal` commands for automated recurring tasks | feed item 2026-06-21 (https://x.com/intellectronica/status/2068644098970644925) | Duplicate | Covered by `commit-digest` + `weekly-automation-review` as scheduled recurring agents. |
| Auto-generate feature documentation from repositories with Cognition's DeepWiki | feed item 2026-06-21 (https://x.com/kr0der/status/2068556522888761685) | Out of scope | Cognition/DeepWiki-specific tool; no Claude Code equivalent hook/skill surface. |
| Feed older academic papers to frontier models to identify errors and extend arguments | feed item 2026-06-21 (https://x.com/emollick/status/2068507998343885284) | Out of scope | Academic research methodology; no dev-workflow surface. |
| Use Visual Plan skills to make Claude produce structured agent-native plans before coding | feed item 2026-06-20 (https://x.com/Saboo_Shubham_/status/2068349529855078619) | Duplicate | Covered by `board` (adversarial planning critique) + `plan-reminder` hook (keeps plan.md current). |
| Configure global AGENTS.md to automatically spawn and manage Codex subagents | feed item 2026-06-20 (https://x.com/intellectronica/status/2068321664903823458) | Out of scope | Codex/ChatGPT-specific; no Claude Code equivalent. |
| Add "Use sub agents as needed" to prompts to parallelise workstreams | feed item 2026-06-20 (https://x.com/Dimillian/status/2068228064572588056) | Out of scope | Prompting tip; no hook surface. |
| Use Codex browser and computer-use capabilities to build web UI automation workflows | feed item 2026-06-20 (https://x.com/petergyang/status/2068175172960690266) | Out of scope | Codex-specific; no Claude Code equivalent. |
| Transfer Codex environment between machines by copying the home folder | feed item 2026-06-19 (https://x.com/Dimillian/status/2068066242997477567) | Out of scope | Codex/ChatGPT home-folder migration; no Claude Code equivalent. |
| Structure agent work as loops reading current/desired state for incremental changes | feed item 2026-06-19 (https://x.com/dexhorthy/status/2067973141289414862) | Out of scope | Methodology tip; no concrete hook surface. |
| Codex Record-and-Replay converts manual task execution into reusable automation | feed item 2026-06-19 (https://x.com/0xSero/status/2067852273955328373) | Out of scope | Codex feature; no Claude Code equivalent. |
| Demonstrate recurring tasks once and convert to repeatable Codex skills | feed item 2026-06-19 (https://x.com/gabrielchua/status/2067769585739378808) | Duplicate | Covered by `commit-digest` + `weekly-automation-review`. |
| Capture meeting notes in Notion, convert to specs, hand to coding agent | feed item 2026-06-18 (https://x.com/geoffreylitt/status/2067705198630355105) | Out of scope | Notion-specific integration; no dev-workflow hook surface. |
| Share Claude Code Artifacts for visual explanations and diagrams | feed item 2026-06-18 (https://x.com/bcherny/status/2067700226669060207) | Out of scope | Use pattern; no hook/skill surface. |
| Build personalized advisor skills using SKILL.md + plan.md + learnings.md + eval.md | feed item 2026-06-18 (https://x.com/petergyang/status/2067612053293191515) | Deferred | Interesting 4-file pattern for accumulating learnings across sessions; too personal/coaching-oriented for a dev-workflow hook trigger. Revisit if a dev-events-triggered "session learnings" file pattern emerges (e.g. a Stop hook that captures learnings into learnings.md). |
| Maintain one persistent orchestrator thread per project, spawn subthreads for tasks | feed item 2026-06-18 (https://x.com/Dimillian/status/2067584223691579462) | Duplicate | Covered by `board` + `agent-handoff` skills. |
| Create subagents to mine past chat conversations and extract reusable workflows | feed item 2026-06-18 (https://x.com/davis7/status/2067496813406609755) | Duplicate | Covered by `weekly-automation-review` + `prompt-log.sh`. |

---

## 2026-06-17 (Run 5)

Sources scanned:
- `nateberkopec/dotfiles` — commits 2026-06-13 to 2026-06-17: none found (all commits through Jun 13 already reviewed in Run 4)
- Atom feed: https://epoch-research.github.io/ai-productivity-digest/feed.xml — new items 2026-06-12 to 2026-06-17 (20 items)

PRs opened this run:
- dev-hooks [#10 feat: docs-context SessionStart hook — index project docs/ for Claude](https://github.com/mickzijdel/dev-hooks/pull/10)
- rails-toolkit [#2 feat: add rails-api skill](https://github.com/mickzijdel/rails-toolkit/pull/2) — own idea (gap in rails-toolkit skill set)

| Suggestion | Source | Decision | Reasoning |
|---|---|---|---|
| Have Codex run a docs-list script at chat start to pull YAML-frontmatter docs from /docs as context, and write new ones as it works | feed item 2026-06-15 (https://x.com/kr0der/status/2066649703312421322) | **Implement** | dev-hooks PR #10 opened. Translated to a SessionStart hook (`docs-context.sh`) that scans `docs/` for Markdown files and emits a title index into `additionalContext`. |
| Add rails-api skill (own idea) | own idea | **Implement** | rails-toolkit PR #2 opened. The toolkit had no dedicated JSON API guide; added `Api::BaseController` setup, namespace versioning, Jbuilder/Blueprinter, rack-cors, pagy, standardized errors, auth guidance, and a pre-ship checklist. |
| Useful Codex prompt pattern: ask it to review recent commits/changes and document what worked well into an analysis | feed item 2026-06-13 (https://x.com/boringmarketer/status/2065799449473868101) | Deferred | `commit-digest` (this skill) already covers external-repo commit review; `weekly-automation-review` covers local session history. Not enough novel surface for a separate skill. |
| Agents can hit specs but produce poorly-designed code; invest in program design (architecture, abstractions) via memory/agents.md | feed item 2026-06-17 (https://x.com/dexhorthy/status/2067086534927683710) | Deferred | The principle is sound, but "invest in program design" is too broad for a hook trigger. The `memory-reminder.sh` + CLAUDE.md already capture architectural decisions. Revisit if a concrete triggerable pattern emerges (e.g. a new-file hook that checks for missing ADRs). |
| Block 2 hours weekly to review your AI coding agent's session history and update agents.md | feed item 2026-06-14 (https://x.com/0xSero/status/2066251897464406398) | Duplicate | Covered by `weekly-automation-review` skill. |
| Point Codex at its own session logs (JSONL + SQLite) to analyze your prompting patterns and surface workflow friction | feed item 2026-06-15 (https://x.com/maddiedreese/status/2066325751729922355) | Duplicate | `prompt-log.sh` captures Claude Code prompts to JSONL; `weekly-automation-review` clusters them. Claude Code doesn't have a SQLite session log but the same outcome is achieved. |
| Feed an AI model deep context on your work/life, then ask: what am I missing, what should I stop, where am I lying to myself | feed item 2026-06-12 (https://x.com/petergyang/status/2065446074228290007) | Out of scope | Personal reflection/life coaching; no dev-workflow hook surface. |
| Wire an AI agent into analytics, call transcripts, ads, and invoicing, then schedule via GitHub Actions to close the marketing feedback loop | feed item 2026-06-12 (https://x.com/boringmarketer/status/2065452521984757970) | Out of scope | Marketing/analytics workflow; no dev-workflow hook surface. |
| To avoid AI design slop: feed it a positive reference site, a negative reference, and crank thinking to max | feed item 2026-06-12 (https://x.com/itsolelehmann/status/2065453971477836072) | Out of scope | UI design methodology; no hook surface. |
| Enable Codex Browser Developer Mode (CDP access) to let Codex inspect live page state | feed item 2026-06-14 (https://x.com/maddiedreese/status/2065995021330051363) | Out of scope | Codex (ChatGPT desktop) specific; no Claude Code equivalent. |
| Curated list of free agentic tools: Compound Engineering, Printing Press, last30days | feed item 2026-06-15 (https://x.com/petergyang/status/2066309730138726752) | Out of scope | Tool recommendations list; no hook/skill surface. |
| Ask your agent 'what does business success look like, and how can we measure it?' for better feedback loops | feed item 2026-06-15 (https://x.com/dexhorthy/status/2066319076432179357) | Out of scope | Business strategy prompt technique; no dev-workflow hook. |
| Don't read agents' full plans—ask targeted questions like 'what files will you touch?' and 'what's most likely to break?' | feed item 2026-06-15 (https://x.com/petergyang/status/2066528666511987059) | Out of scope | Prompting tip; no hook surface (can't intercept human review of agent plans). |
| Record a bug-bash/meeting, have an agent turn it into tasks, assign easy fixes to coding agents over the weekend | feed item 2026-06-15 (https://x.com/geoffreylitt/status/2066571560794611942) | Out of scope | Meeting-to-tasks workflow; no dev-workflow hook surface. |
| For LLM-assisted media editing: ask for a range of options, give reference files, iterate by picking the best | feed item 2026-06-15 (https://x.com/0xSero/status/2066623331244343472) | Out of scope | Media editing workflow; not dev. |
| Use Codex to spawn scheduled sub-chats (9am/9pm pings) that auto-run recurring analysis tasks | feed item 2026-06-15 (https://x.com/kr0der/status/2066627059812905120) | Out of scope | Codex-specific scheduling; Claude Code has no equivalent scheduled sub-chat API. |
| Stop having agents click through websites; pipe site contents into a CLI your agent can run | feed item 2026-06-16 (https://x.com/petergyang/status/2066710220945096804) | Out of scope | General agent ergonomics tip; no hook surface. |
| Use Cursor or similar harnesses to run adversarial reviews across GPT, Claude, and Composer in the same loop | feed item 2026-06-16 (https://x.com/petergyang/status/2066919332500951271) | Out of scope | Cursor-specific multi-LLM workflow; no Claude Code hook. |
| Use Claude Code with ffmpeg and Wispr to auto-sort, transcribe, trim, and rename raw video clips | feed item 2026-06-16 (https://x.com/itsolelehmann/status/2066945778665292096) | Out of scope | Media/video workflow; not dev. |
| Set up Bing Webmaster Tools for your site to improve visibility in ChatGPT results | feed item 2026-06-16 (https://x.com/chasing_next/status/2067001470566986219) | Out of scope | SEO/marketing; no dev-workflow. |
| In Codex CLI v0.140.0, run /usage to see a token activity graph | feed item 2026-06-17 (https://x.com/Dimillian/status/2067213206934687806) | Out of scope | Codex (ChatGPT) CLI specific; not Claude Code. |

---

## 2026-06-13 (Run 4)

Sources scanned:
- `nateberkopec/dotfiles` — commits 2026-06-09 through 2026-06-13: `facd980` (merge), `d6887f6`, `b9e01cf`, `0b3219d` (merge), `cd611a9`, `609e48c`
- Atom feed: https://epoch-research.github.io/ai-productivity-digest/feed.xml — new items 2026-06-10 to 2026-06-11, plus three June 9 items not captured in previous runs (`alexalbert__`, `bcherny` self-verification, `dexhorthy` queue-model)

PRs opened this run:
- rails-toolkit [#1 feat: add Content Security Policy to rails-security](https://github.com/mickzijdel/rails-toolkit/pull/1) — completes the Run 3 blocked implement
- dev-hooks [#8 feat: add agent-handoff skill + autoMemoryEnabled doc note](https://github.com/mickzijdel/dev-hooks/pull/8)

| Suggestion | Source | Decision | Reasoning |
|---|---|---|---|
| Document `autoMemoryEnabled: false` in memory-reminder README note | dotfiles commit `609e48c` ("Disable Claude Code auto memory", Jun 10) | **Implement** | Bundled into dev-hooks PR #8. `memory-reminder.sh` already owns structured memory capture; auto-memory running concurrently produces redundant entries. |
| New `agent-handoff` skill for plan.md multi-session/multi-agent coordination | feed item 2026-06-10 (https://x.com/NickADobos/status/2064640830980374897) | **Implement** | dev-hooks PR #8 opened. `plan-reminder.sh` already exists; this skill documents the plan.md format and handoff protocol. |
| Install aube from jdx repo | dotfiles commit `b9e01cf` (Jun 12) | Deferred | aube adoption already deferred in Run 3; changing the install source doesn't change the feature assessment. |
| Reinstall stale dotfiles hk hook | dotfiles commit `d6887f6` (Jun 12) | Out of scope | Specific to Nate's dotfiles runner setup mechanism. |
| Remove jq-based deny-rm-rf PreToolUse hook | dotfiles commit `cd611a9` (Jun 10) | Out of scope | dev-hooks' `dangerous-command-guard.sh` already uses a better `ask`-not-`deny` approach for `rm -rf` paths; Nate removing his simpler hook doesn't change this. |
| Sourcegraph's 5 repeatable agent-run failure patterns in large codebases | feed item 2026-06-11 (https://x.com/Sourcegraph/status/2065212260637868389) | Problem | Source unreachable (403). Could not evaluate content. |
| Use Linear's Slack/agent integration for ticket management via chat | feed item 2026-06-11 (https://x.com/forgebitz/status/2065159504371622384) | Out of scope | Linear-specific project management; no dev-workflow hook surface. |
| Portfolio of recurring AI loops: morning brief, codebase sweeps, Sentry watchers | feed item 2026-06-11 (https://x.com/NickADobos/status/2065136188697280887) | Deferred | `commit-digest` + `weekly-automation-review` already cover the recurring-agent-loop pattern. A dedicated codebase-sweep skill remains possible but would largely duplicate `verify-work.sh` + the weekly review skills. |
| Analyze research paper datasets with multiple LLMs to surface mislabeled data | feed item 2026-06-11 (https://x.com/xeophon/status/2065128113344835821) | Out of scope | Academic research methodology; no dev-workflow surface. |
| Codex loop waking every 5 minutes for hands-off background upkeep | feed item 2026-06-11 (https://x.com/RayFernando1337/status/2065081065304453156) | Duplicate | Covered by `commit-digest` (external repos on a schedule) and `weekly-automation-review` (local repo). |
| Codex orchestrator loop + triage/autoreview skills for autonomous PR landing | feed item 2026-06-11 (https://x.com/steipete/status/2064998499780084154) | Duplicate | Same as above; PR triage/review covered by `review-reminder.sh` + `board`. |
| OpenCode `references` config for cross-repo agent context | feed item 2026-06-10 (https://x.com/thdxr/status/2064785435239276761) | Out of scope | OpenCode-specific configuration; no Claude Code equivalent. |
| Build personal house manager agent via Telegram/iMessage | feed item 2026-06-10 (https://x.com/cathrynlavery/status/2064749512371876287) | Out of scope | Personal task management; no dev-workflow surface. |
| Queue 5–7 short steering messages during long agent refactor sessions | feed item 2026-06-10 (https://x.com/dexhorthy/status/2064747631885398231) | Out of scope | Prompting technique; no hook surface (can't fire mid-session based on elapsed length). |
| Export Xcode Agent Skills with `xcrun agent skills export` | feed item 2026-06-10 (https://x.com/ivanfioravanti/status/2064724124270838097) | Out of scope | Xcode/iOS-specific; no overlap with this plugin. |
| Ask Claude to report in plain English on long multi-agent runs to avoid internal jargon | feed item 2026-06-10 (https://x.com/emollick/status/2064542441848422611) | Out of scope | Prompting tip; no hook surface. |
| Fable 5 tips: bigger tasks, high/xhigh effort, rewrite stale CLAUDE.md, objectives+verification not steps | feed item 2026-06-09 (https://x.com/alexalbert__/status/2064467657483829441) | Deferred | "Objectives + verification not steps" is useful for CLAUDE.md writing guidance in dev-env-setup, but no concrete hook surface and too small for its own PR now. Revisit when touching the project-docs section of dev-env-setup. |
| Self-verification loops in prompts for long-running agent stability | feed item 2026-06-09 (https://x.com/bcherny/status/2064426115255730578) | Duplicate | Covered by `but-for-real` + `verify-work.sh`. Different post from Run 1's Duplicate entry (`bcherny` "Five tips") but same substance. |
| Model agent workflows as queues/backlogs/processing nodes for incremental automation | feed item 2026-06-09 (https://x.com/dexhorthy/status/2064344668079579364) | Out of scope | Methodology tip; no concrete hook or skill surface. |

---

## 2026-06-09 (Run 3)

Sources scanned:
- `nateberkopec/dotfiles` — commits from before the 7-day window (May 30–June 1): `d2a00c5`, `9eadd66`, `837cb02`, `60afa1f`, `d47fa8a`, `1e7827f`, `7487651`, `425afcf`, `3f43c89`, `dab8552`, `6559bca`, `bb155de`, `b921367`, `a47f0d6`, `04db2c8`, `0ef0cb2`, `b50a9b8`, `afc320d`, `bc31bb1`, `f4c1ae8`, `5fed8f4`. All 7-day-window items (June 2–9) already logged in Runs 1 and 2. Outside-window commits evaluated as own-idea candidates.
- Atom feed: https://epoch-research.github.io/ai-productivity-digest/feed.xml — no new items since Run 2.

PRs opened this run:
- [#6 feat: dev-env standard v11 — mise upgrade cooldown + fix template version drift](https://github.com/mickzijdel/dev-hooks/pull/6)
- rails-toolkit CSP section: **could not push** — GitHub integration lacked write access to rails-toolkit in this session; full content ready to apply.

| Suggestion | Source | Decision | Reasoning |
|---|---|---|---|
| Add `minimum_release_age = "4d"` to mise.toml `[settings]` | dotfiles commit `d2a00c5` ("Set mise minimum release age", May 30) | **Implement** | Extends the existing 4-day supply-chain cooldown to `mise upgrade`. PR #6 opened. |
| Use `aube` as npm package manager for mise tools (`npm.package_manager = "aube"`) | dotfiles commits `bc31bb1`, `b50a9b8`, `afc320d` (May 31) | Deferred | Provenance-checking goal is already largely served by `minimum_release_age` (now v11) + `mise.lock` checksums/Cosign/SLSA. `npm.package_manager` is a mise experimental setting not yet stable. Revisit if it matures. |
| Enable aube paranoid mode | dotfiles commit `a47f0d6` (May 31) | Deferred | Downstream of the aube adoption row above; same reasoning applies. |
| Add Content Security Policy section to `rails-security` skill | Own idea (gap: Rails has built-in `config.content_security_policy` since 5.2 but rails-toolkit skill didn't cover it) | **Implement** (blocked) | Wrote full section: initializer with nonce for Importmap, report-only rollout, common mistakes. Could not push — GitHub integration lacked write access to rails-toolkit in this session. |
| Fix template version drift (DEV_ENV_VERSION `"9"` in templates vs VERSION `10`) | Own observation | **Implement** | Bundled into PR #6. |
| Remove qmd from dotfiles | dotfiles commit `9eadd66` (June 1) | Out of scope | Personal quarto/qumd tooling; no bearing on dev-workflow hooks. |
| Avoid opening apps during dotf run / Skip file associations in CI | dotfiles commits `7487651`, `60afa1f` (May 31) | Out of scope | Specific to Nate's macOS dotfiles runner; no hook surface in dev-hooks. |
| Update Pi todos extension from upstream | dotfiles commit `1e7827f` (May 31) | Out of scope | Pi personal agent tool; not applicable. |
| Fix Pi OpenRouter env var reference | dotfiles commit `3f43c89` (May 31) | Out of scope | Pi personal agent tool; not applicable. |
| Pin pi to a provenance-preserving release | dotfiles commit `6559bca` (May 31) | Out of scope | Pi personal agent; release-pinning strategy for pi has no generalizable surface. |
| Run migrations during dotf run | dotfiles commit `5fed8f4` (May 31) | Out of scope | Specific to Nate's `dotf run` automation workflow; dev-hooks has no equivalent runner. |

---

## 2026-06-09 (Run 2)

Sources scanned:
- `nateberkopec/dotfiles` — last 7 days (commits `cfdeb74`, `2181091`, `b5905c0`, `42c9454`, plus merge commits `e058fd5`, `d46633d`, `09af2cc`)
- Atom feed: https://epoch-research.github.io/ai-productivity-digest/feed.xml — items 2026-06-08 to 2026-06-09 (new since Run 1)

PRs opened this run: none

| Suggestion | Source | Decision | Reasoning |
|---|---|---|---|
| Add Anthropic code-simplifier skill | dotfiles commit `cfdeb74` ("Add Anthropic code simplifier skill") | Duplicate | Already present in dev-hooks as `skills/code-simplifier/SKILL.md`, with credit to Nate's dotfiles. |
| Configure Parallel.ai as primary web-search/answer/research provider | dotfiles commit `2181091` ("Configure Parallel web providers") | Out of scope | Personal Pi home-automation agent config (`~/.pi/agent/web-providers.json`); no bearing on dev-workflow hooks or Claude Code plugin. |
| Track macOS Time Machine settings declaratively in dotfiles (24h interval, cache exclusions) | dotfiles commit `b5905c0` ("Track Time Machine settings") | Out of scope | macOS-specific personal backup config; too environment-specific to generalise into a dev-env-setup skill. |
| Wrap npm/yarn/pnpm/pip/uv/cargo installs through Socket Firewall for supply-chain security | dotfiles commit `42c9454` ("Integrate Socket firewall defaults") | Deferred | Socket Firewall (`sfw`) is a legitimate supply-chain security tool, but the implementation is Fish-shell-specific; dev-hooks targets bash/zsh users too. Revisit if a shell-agnostic wrapper or mise plugin appears. Also worth evaluating Socket's Bundler integration for rails-toolkit separately. |
| Build a `/teach` skill: maintain local learning notes, personalise lessons based on gaps | ai-productivity-digest item (2026-06-09), https://x.com/itsolelehmann/status/2064315451631681634 | Deferred | Novel idea with no existing skill equivalent, but the concept is personal-learning oriented rather than dev-workflow oriented; no clear hook trigger. Revisit if a concrete pairing with a dev event (e.g. post-review lesson) emerges. |
| Build interactive dashboards / morning briefings as live Claude artifacts that auto-refresh | ai-productivity-digest item (2026-06-09), https://x.com/kr0der/status/2064285631405265334 | Out of scope | Personal productivity dashboard concept; no dev-workflow hook surface. |
| Implement a pinned "Chief of Threads" meta-thread to organise and rename Claude conversations | ai-productivity-digest item (2026-06-09), https://x.com/Dimillian/status/2064263176611348657 | Out of scope | Claude conversation management pattern; no hook/skill surface in a code-workflow plugin. |
| Maintain one long-lived conversation thread per feature rather than creating separate chats | ai-productivity-digest item (2026-06-09), https://x.com/kr0der/status/2064241837762863546 | Out of scope | Usage-pattern tip; no implementable hook or skill surface. |
| ~50% of queries need no reasoning; medium reasoning matches full quality at lower cost | ai-productivity-digest item (2026-06-09), https://x.com/0xSero/status/2064205966061515266 | Rejected | Prompt-cost tip with no concrete hook/skill surface; model and reasoning-budget selection is user-controlled via Claude Code config. |
| Deploy agent loops for routine commit reviews, message triage, and task delegation | ai-productivity-digest item (2026-06-08), https://x.com/kr0der/status/2063844734418960427 | Duplicate | Already covered by `weekly-automation-review` (local repo history review) and `commit-digest` (external repo scanning) skills. |

---

## 2026-06-09

Sources scanned:
- `nateberkopec/dotfiles` — last 4 days (commits `af41383`, `9703294`, merge commits `464f40e`, `514e4cf`)
- Atom feed: https://epoch-research.github.io/ai-productivity-digest/feed.xml — items 2026-06-07 to 2026-06-09

PRs opened this run: [#3 feat: add commit-digest skill](https://github.com/mickzijdel/dev-hooks/pull/3)

| Suggestion | Source | Decision | Reasoning |
|---|---|---|---|
| Add `BUNDLE_COOLDOWN: "3"` to `.bundle/config` for faster Ruby dev loops | dotfiles commit `af41383` ("3 day bundler cooldown") | Duplicate | `dev-env-setup` skill already covers this in full (§ "Ruby: Bundler cooldown") with `cooldown: 4` in the Gemfile source declaration and the equivalent `BUNDLE_COOLDOWN: "4"` global; the 3 vs 4 day delta follows the official RubyGems blog recommendation already cited there. |
| Remove auto-setting `GEM_HOST_API_KEY` from fnox config | dotfiles commit `9703294` ("Don't always set gemhost") | Out of scope | Specific to Nate's 1Password + RubyGems publisher workflow; dev-hooks uses Bitwarden Secrets Manager and has no gem-publishing flow. |
| Agentic workflow: invest in detailed specs, use visual HTML plans for inline feedback, run isolated parallel agents, have an agent pre-review PRs | ai-productivity-digest item (2026-06-08), https://x.com/petergyang/status/2063988122720055772 | Deferred | Too methodology-level to implement as a hook or skill without a concrete trigger. The parallel-agent and pre-review-PR parts are already partially covered by `board` and `review-reminder`. Revisit if a specific missing piece becomes clear. |
| Five tips for running Claude Opus autonomously for hours: auto-mode permissions, dynamic subagent workflows, /goal or /loop, Claude Code in cloud, self-verification tools | ai-productivity-digest item (2026-06-07), https://x.com/bcherny/status/2063792263067754658 | Duplicate / Out of scope | Auto-mode permissions → `fewer-permission-prompts` skill; subagent workflows → `board`; /loop → `weekly-automation-review`; self-verification → `verify-work.sh` + `but-for-real`. All angles already covered. |
| Geoffrey Litt's personal agent for groceries, family budget, and move logistics — template for personal agent design | ai-productivity-digest item (2026-06-07), https://x.com/geoffreylitt/status/2063791754369765794 | Out of scope | Household/personal-task management; no bearing on dev workflow hooks. |
| When prompting, instruct the model to ask clarifying questions one at a time | ai-productivity-digest item (2026-06-07), https://x.com/davis7/status/2063746062532395208 | Rejected | Prompting tip with no concrete hook/skill surface; too minor to warrant a standalone skill, and the existing skills (`premortem`, `board`) already surface ambiguities before committing. |

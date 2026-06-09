# Skipped Suggestions Log

Maintained by the `commit-digest` skill. Each dated section records every suggestion reviewed
that was **not** implemented, plus a "nothing skipped" row (with PR links) for runs where
everything was acted on.

Dedup rule: a suggestion already present anywhere in this file is never re-logged.

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
| Add Content Security Policy section to `rails-security` skill | Own idea (gap: Rails has built-in `config.content_security_policy` since 5.2 but rails-toolkit skill didn’t cover it) | **Implement** (blocked) | Wrote full section: initializer with nonce for Importmap, report-only rollout, common mistakes. Could not push — GitHub integration lacked write access to rails-toolkit in this session. |
| Fix template version drift (DEV_ENV_VERSION `"9"` in templates vs VERSION `10`) | Own observation | **Implement** | Bundled into PR #6. |
| Remove qmd from dotfiles | dotfiles commit `9eadd66` (June 1) | Out of scope | Personal quarto/qumd tooling; no bearing on dev-workflow hooks. |
| Avoid opening apps during dotf run / Skip file associations in CI | dotfiles commits `7487651`, `60afa1f` (May 31) | Out of scope | Specific to Nate’s macOS dotfiles runner; no hook surface in dev-hooks. |
| Update Pi todos extension from upstream | dotfiles commit `1e7827f` (May 31) | Out of scope | Pi personal agent tool; not applicable. |
| Fix Pi OpenRouter env var reference | dotfiles commit `3f43c89` (May 31) | Out of scope | Pi personal agent tool; not applicable. |
| Pin pi to a provenance-preserving release | dotfiles commit `6559bca` (May 31) | Out of scope | Pi personal agent; release-pinning strategy for pi has no generalizable surface. |
| Run migrations during dotf run | dotfiles commit `5fed8f4` (May 31) | Out of scope | Specific to Nate’s `dotf run` automation workflow; dev-hooks has no equivalent runner. |

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

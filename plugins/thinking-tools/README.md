# thinking-tools

A Claude Code plugin of on-demand "thinking tools" you invoke as slash commands (or that
Claude reaches for when the trigger fits): critique, decision, verification, and automation
workflows distilled from the `#ai-productivity-digest` tips.

Part of the [dev-hooks marketplace](../../README.md), alongside `dev-hooks`,
`coding-onboarding`, and `writing`.

## Skills

| Skill | Use when |
|-------|----------|
| `but-for-real` | About to claim something is done/fixed/working — forces re-reading the real code, running it, and separating verified from assumed. |
| `premortem` | Before committing to a non-trivial plan — imagines it already failed and works backward to failure modes, hidden assumptions, and a revised plan. |
| `board` | You want hard, independent critique — convenes a panel of real parallel advisor subagents, then a chairman synthesizes. |
| `self-rate` | Before returning uncertain work — scores it on a calibrated scale, then tightens overclaims to match. |
| `code-simplifier` | After modifying code or during refactoring — simplifies and refines for clarity, consistency, and maintainability while preserving all functionality; focuses on recently changed sections unless directed otherwise. |
| `weekly-automation-review` | Weekly cadence — reviews recent activity and recommends 1–2 repetitive tasks to automate; runs as a scheduled Monday remote agent. On a local run it also reads the cross-repo prompt log (`~/.claude/automation-review/prompts.jsonl`, written by the `dev-hooks` `prompt-log` hook) and every repo's memory index to spot what you keep asking for. |
| `commit-digest` | Weekly cadence — reviews recent commits in tracked external repos (+ optional Atom/RSS feeds), pulls applicable improvements in as separate PRs, and logs every skipped suggestion to the `claude/skipped-log` branch with dedup and a per-run PR comment. Companion to `weekly-automation-review`, which reviews the local repo's own activity. |
| `adr` | When you've made (or are about to make) a significant architectural decision — captures why in a lightweight Markdown document so future contributors don't re-litigate it. |

## Install

```bash
/plugin marketplace add mickzijdel/dev-hooks
/plugin install thinking-tools@dev-hooks
```

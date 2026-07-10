---
name: checkup
description: Audit installed skills, MCP servers, hooks, and CLAUDE.md files for bloat — what's carried but never used, what's slow, what's duplicated. Use on a monthly cadence, or when asked "what's slowing me down", "clean up my Claude Code setup", "am I carrying dead weight", "prune unused skills/MCPs", or "why is every turn so noisy". Reports prune candidates for the user to act on; never removes anything itself. Complements [[weekly-automation-review]] (which finds work worth *adding*) — this is the *subtracting* half.
---

# Checkup

A hygiene pass over what's currently installed, not what's missing. Every idle skill and MCP server still costs — its description sits in the context window every turn, its tools widen the permission surface — so an unused one is pure cost with no offsetting benefit. This skill finds those and reports them; it never edits or uninstalls on its own.

## 1. Inventory what's installed

- **Skills** — the `skill_listing` attachment on this transcript names every installed skill (from every enabled plugin and `~/.claude/skills/`). Use it as the full list; don't re-derive it from disk.
- **MCP servers** — run `/mcp` (or read `mcpServers` / `enabledMcpjsonServers` in `.claude/settings.json`, `.claude/settings.local.json`, and `~/.claude.json`) for every configured server, connected or not.
- **Hooks** — for each installed plugin that ships a `hooks/` directory, list its registered hooks and which event each fires on (`SessionStart`, `PostToolUse`, `PreToolUse`, `Stop`, `UserPromptSubmit`).
- **CLAUDE.md files** — every one in scope: `~/.claude/CLAUDE.md` (user-level), the project root, and any subdirectory-level ones.

## 2. Gather usage evidence

Look back across recent sessions — `~/.claude/projects/*/*.jsonl` transcripts, a few weeks' worth or the last N sessions, whichever is available.

**Walk `tool_use` blocks; never grep skill names.** The `skill_listing` attachment names every installed skill in *every* session regardless of use, so a bare-name `grep` matches everywhere and permanently hides a truly-idle skill. Only a real `Skill`/`Agent` tool-use entry invoking that name counts as a use. (Mirrors the `transcript_invoked()` convention in `dev-hooks`'s `hook_helpers.py`.) The same logic applies to MCP tools — only an actual `mcp__<server>__*` tool call counts, not the server merely being connected.

For hooks, look for a different signal: did the hook's advisory output (its `additionalContext`, or a `permissionDecision`) ever visibly change what happened next, or did every firing get silently ignored? A hook that fires constantly and is never acted on is a noise candidate even if it's "working as designed."

## 3. Classify each item

For skills and MCP servers: **Actively used** (invoked in the window) / **Rarely used** (once or twice — ask before pruning, some are intentionally rare-but-critical) / **Never used** (zero real invocations in the window — the strongest prune signal).

For MCP servers specifically, weigh connection cost too: a server that auto-connects on every session start burns context and startup time regardless of whether its tools ever get called.

For hooks: **Earning its keep** (output gets acted on) / **Ambient noise** (fires often, acted on rarely or never — disable candidate) / **Expensive** (does real work — network calls, heavy subprocess, large file scans — on a hot path like `PostToolUse`, regardless of whether it's acted on).

## 4. Check CLAUDE.md for drift

With more than one CLAUDE.md in scope, read all of them and flag:
- **Duplication** — the same instruction repeated verbatim or near-verbatim across files (wastes context on every turn; keep it in the most specific file that still covers every place it's needed).
- **Contradiction** — two files disagreeing on the same point (which one is stale?).
- **Dead references** — an instruction pointing at a file, skill, or convention that no longer exists.

## 5. Pre-approved commands

Don't reimplement this — hand off to the `fewer-permission-prompts` skill, which already scans transcripts for common safe commands and proposes an allowlist. Mention it in the report rather than duplicating its scan.

## 6. Report

Present findings as three buckets — **Prune**, **Investigate**, **Keep as-is** — each with the one-line evidence that earned it that bucket (last-used date or "never seen in N sessions/days", the specific duplication/contradiction found, the concrete cost for an "expensive" hook). Never delete or disable anything yourself: this is a proposal, and pruning a skill or hook is the user's call, not an automatic action.

## Cadence

Suited to a monthly on-demand run rather than every-session — usage patterns need weeks to show a trend. If the user wants it scheduled, the [[schedule]] skill (`CronCreate`) can register it as a recurring remote agent the same way `commit-digest` and `weekly-automation-review` are.

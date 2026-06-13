---
name: weekly-automation-review
description: Use on a weekly (Monday) cadence, or when asked what repetitive work is worth automating, what to turn into a skill/hook/tool, or to review recent activity for automation opportunities. This is the skill the scheduled Monday remote agent invokes. Triggers on recurring-task review, "what should I automate", and end-of-week/start-of-week retrospectives.
---

# Weekly Automation Review

Once a week, look back at recent work, spot the tasks you did by hand more than once, and recommend **1–2** of them to automate into a skill, hook, or tool. The discipline is to automate deliberately on a cadence instead of only when something annoys you in the moment.

## What it reviews

- **The prompt log** — `~/.claude/automation-review/prompts.jsonl`, written by the `dev-hooks` plugin's `prompt-log` hook: one JSON line per user prompt (`ts`, `cwd`, `session_id`, `len`, `prompt` ≤ 500 chars) across **all** repos. This is the only **cross-repo** source, and the strongest signal — what you actually keep *asking for* is exactly what's worth automating. Pull the last 7 days (jq-only cutoff, so no GNU/BSD `date` divergence):
  ```bash
  jq -c 'select(.ts >= (now - 7*86400 | strftime("%Y-%m-%dT%H:%M:%SZ")))' ~/.claude/automation-review/prompts.jsonl 2>/dev/null
  ```
  Also read `prompts.jsonl.1` (the rotation spillover) if present. Cluster prompts by intent — same verbs/nouns ("deploy", "fix CI", "regenerate fixtures"), same `cwd`, near-duplicate phrasing — and count repeats; anything asked **3+ times in a week**, or weekly across reports, is a prime candidate. **If the file doesn't exist** (the `dev-hooks` plugin isn't installed, or `DEV_HOOKS_PROMPT_LOG=false`), skip this source silently and rely on the others.
- **Every repo's memory index** — glob `~/.claude/projects/*/memory/MEMORY.md` and skim each (follow into an individual memory file only when a line looks automation-relevant). `feedback`/`project` memories record recurring corrections and workflows ("always run X after Y") — patterns worth turning into a hook or skill. Glob may match nothing; degrade silently.
- **Recent git activity** — commits/branches in the working repo over the last 7 days (`git log --since='7 days ago' --stat`); what kinds of changes repeated?
- **The off-topic backlog** — `plans/off-topic-improvements.md` if present; recurring themes there are automation candidates.
- **Repetition signals** — the same multi-step manual workflow done more than once, the same class of fix, the same checklist run by hand.
- **The previous report** — read the last file in `plans/automation-reviews/` so recommendations build on prior ones and you can note what actually got automated (self-improving loop).

## Procedure

1. Read the previous report (if any) and note which past suggestions shipped.
2. Gather the week's activity — start with the prompt log (when present), then the memory indexes, then git/backlog.
3. Identify repeated workflows — favor ones that are **high-volume, well-defined, low blast-radius, and measurable**.
4. Pick the top **1–2** and, for each, specify: what it is, whether it's best as a **skill / hook / tool**, a rough effort estimate, and the first concrete step.
5. Write the dated report (below) and post a one-paragraph summary to the user.

## Output

Write to `plans/automation-reviews/YYYY-MM-DD.md`:

```markdown
# Automation Review — YYYY-MM-DD

## Reviewed
<repos / window / sources scanned>

## Repetitive workflows spotted
- <workflow> — seen <N>× — <why it recurs>
- <request cluster> — asked <N>× across <M> repos (prompt log) — <why it recurs>

## Recommended this week (1–2)
1. <name> — skill | hook | tool — effort: <S/M/L>
   - First step: <…>

## Status of prior suggestions
- <past idea> — shipped / dropped / still open
```

Then give the user a short summary + the top recommendation.

## Scheduling

Registered as a recurring **Monday-morning remote agent** via the [[schedule]] skill (CronCreate). Note: remote routines run against a **single repo**, and a **remote** run can't see the local prompt log or the per-repo memory indexes (they live on your machine under `~/.claude/`) — so the cross-repo prompt-log/memory view only materializes on a **local** run. For a genuine sweep across all local projects, run it via a local recurring mechanism (`/loop` or a local cron) instead. Each run appends to the report history, so the review compounds over time.

---
name: automation-review
description: Use for the daily automation review the scheduled task runs, or when asked "what should I automate", what repeated work to turn into a skill, hook or tool, or for a look back at recent activity.
---

# Automation Review

Each weekday morning, look back at recent work, spot the tasks you did by hand more than once, and recommend **at most 1–2** of them to automate into a skill, hook, or tool. The discipline is to automate deliberately on a cadence instead of only when something annoys you in the moment.

**Daily window.** Count repeats over a **rolling 7 days**, so the thresholds below keep their weekly meaning, but **report only what is new since the previous report**: a pattern that crossed a threshold since then, a candidate whose count grew, a new retro or queue entry. Something already recommended and unchanged gets one line under prior suggestions, never a second recommendation. On Monday the previous report is Friday's, so the weekend is covered. A day with nothing new gets a three-line report that says so; that is a good result, not a failure.

Automation is a one-way ratchet unless something also **removes** it. So the **first run of each ISO week** (normally Monday) also does a **Retire pass**: pick 1–2 existing scaffolds whose capability bet the current model has outgrown and propose deleting them. Adding without ever retiring is how a harness accretes dead weight that fights a better model instead of riding it.

## What it reviews

- **The prompt log** — `~/.claude/automation-review/prompts.jsonl`, written by the `dev-hooks` plugin's `prompt-log` hook: one JSON line per user prompt (`ts`, `cwd`, `session_id`, `len`, `prompt` ≤ 500 chars) across **all** repos. This is the only **cross-repo** source, and the strongest signal — what you actually keep *asking for* is exactly what's worth automating. Pull the last 7 days (jq-only cutoff, so no GNU/BSD `date` divergence). Read it **corruption-tolerantly** — a crash mid-append can leave a block of NUL bytes that makes a plain `jq -c` abort at that line and silently drop the whole rest of the file (so the review sees *zero* recent prompts and skips its strongest signal). Strip NULs, parse each line on its own, and drop only the unparseable fragment:
  ```bash
  for f in ~/.claude/automation-review/prompts.jsonl ~/.claude/automation-review/prompts.jsonl.1; do
    tr -d '\000' <"$f" 2>/dev/null \
      | jq -Rc 'fromjson? | select(.ts >= (now - 7*86400 | strftime("%Y-%m-%dT%H:%M:%SZ")))'
  done
  ```
  (`prompts.jsonl.1` is the rotation spillover; the loop skips it silently when absent. `-R` reads each line as a raw string and `fromjson?` yields nothing for a line that won't parse, so one bad line can never blind the rest.) Cluster prompts by intent — same verbs/nouns ("deploy", "fix CI", "regenerate fixtures"), same `cwd`, near-duplicate phrasing — and count repeats; anything asked **3+ times in the last 7 days**, or recurring across reports, is a prime candidate; report it only if it is new or its count grew since the previous report. **If neither file exists** (the `dev-hooks` plugin isn't installed, or `DEV_HOOKS_PROMPT_LOG=false`), the loop prints nothing — skip this source silently and rely on the others. If lines exist but their `prompt` fields are empty, the log still gives counts by `cwd` and session; for intent, grep the last 7 days of transcripts (`~/.claude/projects/*/*.jsonl`) instead, and say so in the report.
- **Every memory index** — the global `~/.claude/memory/MEMORY.md` plus each repo's `~/.claude/projects/*/memory/MEMORY.md`; skim each (follow into an individual memory file only when a line looks automation-relevant). `feedback`/`project` memories record recurring corrections and workflows ("always run X after Y") — patterns worth turning into a hook or skill. Glob may match nothing; degrade silently.
- **Recent git activity** — commits/branches in the working repo over the last 7 days (`git log --since=7.days --stat`), marking those newer than the previous report; what kinds of changes repeated?
- **The off-topic backlog** — `plans/off-topic-improvements.md` if present; recurring themes there are automation candidates.
- **Repetition signals** — the same multi-step manual workflow done more than once, the same class of fix, the same checklist run by hand.
- **The skill-candidate queue** — `${XDG_DATA_HOME:-~/.local/share}/dev-hooks/skill-candidates.md`, appended by dev-hooks' `skill-candidate-reminder` at the end of substantial sessions: one `## <date> · <repo> · amend <skill> | new <name>` entry per proposal, with its trigger, should-fire and should-not-fire prompts, evidence and a `Status:` line. Every `Status: open` entry gets a decision this run (see Procedure). The same proposal from two sessions is a strong signal.
- **Retros** — prompt-log lines whose `prompt` starts with `/retro`: each is a moment the user flagged a session as going badly, with the note and any `#tags` after the command and the line's own `ts`, `cwd` and `session_id`. Take those since the previous report. Each is a failure signal nobody diagnosed yet: open the session's transcript (`~/.claude/projects/*/<session_id>.jsonl`) around `ts` and name the cause before proposing a fix (usually a skill amendment, a hook, or a CLAUDE.md line).
- **The previous report** — read the newest `YYYY-MM-DD.md` dated before today in `plans/automation-reviews/` (other files and subfolders there aren't reports) so recommendations build on prior ones and you can note what actually got automated (self-improving loop). With no earlier report, the whole 7 days count as new and this run is the week's first.

## Procedure

1. Read the previous report (if any) and note which past suggestions shipped.
2. Gather activity — the prompt log's last 7 days first (when present), then the memory indexes, then git/backlog — and mark what is newer than the previous report.
3. Identify repeated workflows — favor ones that are **high-volume, well-defined, low blast-radius, and measurable**.
4. **Triage the skill-candidate queue.** For each `Status: open` entry: amend the named skill, add the new one, or decline. Prefer amending; a new skill must first show it triggers on its should-fire prompts and stays quiet on the rest (skill-creator's description test, or a `claude plugin eval` case with a `tool_used: Skill` grader), since every added skill makes picking the right one harder. Rewrite the entry's status line as `Status: shipped <date> <commit>`, `Status: declined <date>: <reason>` or `Status: deferred <date>: <what it waits on>`. A candidate you'd build counts as one of today's picks.
5. Pick at most **1–2** new ones (zero is fine) and, for each, specify: what it is, whether it's best as a **skill / hook / tool**, a rough effort estimate, and the first concrete step.
6. **First run of the ISO week only** (normally Monday; check whether an earlier report this week already has a Retire section): the **Retire pass** and the **separate sub-reviews** (below). Run the Retire pass on another day only when asked, or on a major model release.
7. Write the dated report (below) and post a summary of two or three sentences to the user: the top recommendation, or "nothing new".

## Retire pass — prune scaffolding the model outgrew

The counterweight to the add pass. A hook or skill that compensates for a **model weakness**
declares its bet in its header (`# bet: <weakness>` / `# sunset: <observable that means delete
me>` for hooks; a `bet:`/`sunset:` note for capability-compensating skills). A bet of
`none (L1–L6)` means it encodes preference / private fact / verification / safety — those don't
depreciate, so skip them. Focus only on the ones making a real capability bet.

Each week, take **1–2** such scaffolds (rotate — favour the oldest, or ones the fire log shows
firing rarely) and check the bet against the **current** model:

- **Evidence.** If `~/.claude/automation-review/hook-fires.jsonl` exists (opt in with
  `DEV_HOOKS_FIRE_LOG=1`), see how often the hook actually fires. A hook that never fires is
  either dead or its trigger is stale; a hook that fires constantly and is always ignored is
  noise.
- **Effect, for Stop hooks.** A fire count says nothing about whether the nudge worked. If
  `~/.claude/automation-review/stop-nudges.json` exists (written by the `dev-hooks` mod), read
  its `last7Days` / `last30Days`: per hook, `fired` and how many were `acted` on, `ignored`,
  `declined` (memory-reminder's "nothing worth saving") or `unknown` (no detectable remedy, or
  the session ended first). Acted-on rate = `acted / (acted + ignored + declined)`; `records`
  holds each nudge (`hook`, `session`, `at` in epoch ms, `outcome`, `evidence`) for 90 days.
  A hook with a high fire count and a low acted-on rate is the noise case above. Remedies see
  only Edit/Write and skill/agent runs, so one done through Bash counts as ignored — sample a
  session or two before retiring on this number alone. Missing file: fall back to
  transcripts.
- **The sunset test.** Read the `# sunset:` line — it names the observable that means "delete
  me." Judge whether the current model now does that thing unprompted (sample a few recent
  transcripts, or run a quick with/without probe on a representative case).
- **Mechanism probe, before any delete.** A count cannot tell a redundant hook from a working
  one: "fires rarely, so delete it" and "fires alongside good behaviour, so it works" are the
  same error. Read the script, trigger it on a representative case, and check that what its
  message points at (a skill, script, file or setting) still exists and that nothing else
  already does its job. Record that as the verdict's `mechanism:`; a delete without one is not
  a verdict.
- If the probe shows the bet no longer holds, propose removal (or downgrade a blocking gate to
  advisory) with the same PR discipline as an add: one change, tests updated, the reasoning
  recorded.

Run this pass **explicitly on every major model release**, not only weekly — a capability jump
is exactly when standing bets go stale in bulk.

## Separate sub-reviews

Other projects can register their own weekly review by dropping a Markdown file in
`~/.claude/automation-review/subreviews/*.md`. On the week's first run, for each file there (none is fine; skip
silently), follow it as its own review and report it under **its own heading**, after the
automation report. Its findings never count toward the 1–2 automation picks, the retire pass
or the prior-suggestions list, and nothing from it is folded into them.

## Output

Write to `plans/automation-reviews/YYYY-MM-DD.md`. Keep it short: leave out a section with nothing new (Retire runs once a week), and keep each line to one sentence.

```markdown
# Automation Review — YYYY-MM-DD

## Reviewed
<since <previous report date>; repeats counted over 7 days; sources scanned>

## New since last report
- <workflow> — seen <N>× in 7 days (was <M>) — <why it recurs>
- <request cluster> — asked <N>× across <M> repos (prompt log) — <why it recurs>

## Recommended (0–2)
1. <name> — skill | hook | tool — effort: <S/M/L>
   - First step: <…>

## Skill candidates (<N> open → <N> decided)
- <date · repo · amend X | new Y>: shipped / declined: <reason> / deferred: <waits on>

## Retros (<N> since last report)
- <date · repo · #tags>: cause <from the transcript>; fix <skill / hook / CLAUDE.md line, or none>

## Retire (first run of the week, 0–2)
- <hook/skill> — bet: <its bet> — mechanism: <what it did on a representative case; does its target exist?> — verdict: <still holds / model outgrew it> — <keep / delete / downgrade>

## Status of prior suggestions
- <past idea> — shipped / dropped / still open
```

Then give the user two or three sentences: the top recommendation, or "nothing new".

## Scheduling

Run it **locally**, as a weekday-morning scheduled task (the Claude desktop app's scheduled tasks, or a local cron running `claude -p`), with the repo that holds `plans/automation-reviews/` as its folder. Not as a remote routine: that runs against a single cloned repo and can't see the prompt log, the memory indexes or the Stop-nudge stats, which all live under `~/.claude/` on your machine. Each run adds a dated report, so the review compounds over time.

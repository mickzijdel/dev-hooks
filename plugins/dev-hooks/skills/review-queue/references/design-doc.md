# docs/review-queue.md template

Copy this into the user's repo and fill every section. A section that doesn't apply says
"n/a: <reason>"; none are dropped.

```markdown
# Review queue: <dataset name>

## What I found
Rows, required fields and how often each is empty, staleness (last-modified spread),
what's waiting now. **Baseline: <number> waiting on <date>.**

## Sources
| Kind | Source | Per week | Arrives as | Reply owed? | Phase |
|---|---|---|---|---|---|
| Inbound requests | | | | | |
| Discovery | | | | | |
| Maintenance | | | | | |
| Rules learned | | | | | |

## Interview answers
One line per question in the bank: the answer, or "skipped: <what answered it>".

## Proposal (one queue row)
Where proposals live: the same store as the data, a table or file next to it.
Fields: type (Add / Change / Rule), source, target record, payload (the new record's
fields, or {field, from, to} per change), verdict + reasons, three reject reasons written
in advance, reply draft (and reject-reply draft), status, decided at.
Status: Pending → Accepted → Applied | Rejected (kept <undo window>, then deleted) | Failed.

## Review page
Port of AISafety.com @ <commit>: the files kept, replaced and dropped (from porting.md),
and what replaces the data, preview and auth seams.
Or the lighter surface the user chose, with the ui-checklist items it gives up.
Phase 1 checklist items: <list>.

## Guardrails
Protected fields: <list>. Irreversible actions and how each stays a draft or is confirmed.
Who has view-only access.

## Learning loop
How reject reasons and chat corrections become rulebook edits, where the rulebooks live,
and how a Rule proposal reaches the queue. Rerunning waiting proposals against new
rules: when, and who triggers it.

## Build plan
- Phase 1: <one source>, the proposal store, the review page, the baseline recorded.
- Phase 2: the remaining sources, by volume.
- Phase 3: chat with the agent on the page; the learning loop.

## Check in two weeks
The metric, its baseline, and the number that means it worked.
```

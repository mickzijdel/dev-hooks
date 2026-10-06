---
name: review-queue
description: Use when someone wants agents to prepare changes to a dataset they maintain (a directory, listings site, CRM, catalogue, Airtable or Notion base, spreadsheet) so a human only accepts or rejects. Triggers on "set up a review queue", "approval inbox", "agents propose, I approve", "I keep falling behind on keeping X up to date", "triage requests from email/forms/Slack/Discord into data changes", "minimise human input in data upkeep", or a mention of AISafety.com's Queue. NOT for one-off bulk edits (just do them) or loops with no human decision step (that's loop-oversight).
---

# Designing a review queue

A review queue splits data upkeep in two. Agents do all the work: find the change, fill
every field, draft the reply. The human spends one keypress per decision. The goal is
**the fewest human seconds per correct change**. Nothing applies without an accept.

The reference implementation is AISafety.com's Queue (MIT, Next.js + Airtable):
[references/porting.md](references/porting.md). This skill ends at a design doc.
Building it is a separate step.

## Workflow

1. **Read the data before saying anything.** Profile the dataset: rows, the fields a
   published record needs and how often each is empty, how stale it is (last-modified
   spread), and what's already waiting (drafts, unread requests). That waiting count is
   the **baseline**. Use dev-hooks:data-before-design for the fields the review card will
   show.
2. **Fill the source table.** It has four rows, and every row gets an answer, even
   "none yet":
   | Kind | Example | Per week | Arrives as | Reply owed? |
   |---|---|---|---|---|
   | Inbound requests | email, form, Slack/Discord | | | |
   | Discovery: new items nobody sent | crawl, search, newsletters | | | |
   | Maintenance of existing items | past dates, dead links, stale facts, empty required fields | | | |
   | Rules learned from decisions | reject reasons → rulebook edits | | | |
   Count what the files and connectors show. Ask only for what they can't.
3. **Interview, one group per message.** Use the bank in
   [references/interview.md](references/interview.md), group by group. Skip any question
   the data already answered and say what answered it. A message holds at most three
   questions, each with your recommended answer and why. Wait for the replies before the
   next group, since the answers change what to ask next.
4. **Write the design doc** at `docs/review-queue.md` from
   [references/design-doc.md](references/design-doc.md). Every section is required. Write
   "n/a: <reason>" rather than dropping one.
5. **Offer to build Phase 1** (superpowers:writing-plans). Don't build it in this skill.

## The review page

The page is where the human time goes. By default the plan is to **port AISafety.com's
page** ([porting.md](references/porting.md)), because the port is an agent's job, not the
user's. Recommend the port whatever the dataset's size. A small dataset with one volunteer
reviewer is the case it was built for.

A lighter surface is the user's call, not yours. If they choose one (a terminal script, an
Airtable Interface, a spreadsheet view), the design doc lists which items of
[references/ui-checklist.md](references/ui-checklist.md) it gives up.

## Guardrails every design keeps

- Agents write proposals only. Accept is the single path to the live data.
- Protected fields (publish/hide flags, anything the interview names) can't be written by a
  proposal or an edit.
- Accept re-reads the proposal and refuses one that's already decided.
- Replies to people are drafts. A human sends them.
- A reject keeps the proposal for an undo window (AISafety.com: 24 h) before it's deleted.

## Common mistakes

| Mistake | Instead |
|---|---|
| "Their page is overkill for 30 rows, a CLI will do" | Recommend the port; let the user pick a lighter surface |
| Every question at once, with defaults to accept unread | One group per message, at most three, each with a recommendation |
| Asking only about logistics (trigger, surface) | Rubric, protected fields, reply voice and the baseline matter more |
| Only inbound requests in the queue | All four source kinds, discovery included |
| "Shall I build it?" after the first answer | Finish the interview, write the doc, then offer |
| Ambiguous request → silent best guess | A proposal whose verdict says what's unclear, so the human decides it in one look |

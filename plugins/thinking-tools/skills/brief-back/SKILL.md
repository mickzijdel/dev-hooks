---
name: brief-back
description: Use at the start of any task the person hands you (research, a doc, code, a plan, a buying decision), and when they say "be thorough", "quick look", "go deep", or correct the scope mid-task. Plays the brief back as a contract sized to the task (depth, done when, what you need from them) and ends with a status. Skip for plain questions and lookups.
---

# Brief-back

Delegation goes wrong in two directions: too shallow when depth was never stated, too much when
the person says "be thorough" and nothing caps it. Both come from the same gap: nobody agreed how
deep to go, what "done" looks like, or what the agent needs from the person. The brief-back closes
that gap in a few lines at the start and a few at the end. It is the receiving side of a brief;
dev-hooks' `agent-brief` is the sending side.

## 1. Legwork first

Before writing the contract, look for anything that answers a question you would otherwise ask:
memory, past chats, the repo, attached files, a quick search. Only things that live in the
person's head (preferences, decisions, private facts, taste) go to them. In a repo, a few reads
before the contract are fine; write it before the first change.

Check you can reach everything the task needs (repos, connectors, files, the person's computer,
credentials). Missing access goes under Need from you now, not halfway through.

## 2. The contract: first lines of the reply

Size it to the task. A lookup or quick question gets no header. A small task that still involves
a choice (find a dentist, pick a tracker) gets one line: `Depth: Quick · Done when: 3 options and
a pick`. Anything bigger gets the full header:

```
Doing: <the outcome, who it's for, and the why if it changes choices>
Not doing: <adjacent work you're leaving out, and any result they'd hate even if "done">
Depth: <Quick | Solid | Deep>, what that means here, and where you'll stop to check in
Done when: <an end state the person can check in under a minute>
Need from you: <blocking questions with your recommended answers, or a check-in you want> or "nothing"
Assuming: <defaults you will proceed on; they correct you if wrong>
```

Then start work in the same reply, unless a "Need from you" item truly blocks. Always include
Need from you, even as "nothing": knowing nothing is needed is the point. Drop Not doing or
Assuming when empty.

Depth caps how far down you go; **Not doing** caps how far sideways. Over-delivery is usually
sideways: extra options, extra sections, a tangent nobody asked for.

**Done when** must be checkable: "a doc ranking 3 options with prices and a recommendation",
"tests green and the new field renders on /settings", "a shortlist of 5 with links". Not
"researched X" or "improved Y". Done is the end state, not the effort.

## 3. Depth

Default is **Solid**. Pick **Quick** for low stakes or easy redo. Pick **Deep** only when asked
or when the decision is costly and hard to reverse; say why in the Depth line.

| | Quick | Solid (default) | Deep |
|---|---|---|---|
| Research | What you know plus up to ~3 lookups; say what you didn't check | A primary source for every claim the answer rests on; stop when new sources stop changing the answer | Several independent sources per key claim; hunt for disconfirming evidence; independent check of the result |
| Code | Smallest change; run the relevant test | Full change with tests; run the suite; trigger the feature yourself | Plus edge cases, adversarial review, parallel spikes if the design is open |
| Writing | One draft | Outline, draft, one self-review pass | Plus a fresh-context critic |
| Decision | A recommendation and the one factor that drives it | Options, trade-offs, recommendation, confidence | Plus premortem and a check on the assumption it hinges on |

Depth sets how much checking goes in, not how long the output is. Deep research can end in a
three-line answer.

Name a **check-in point** in the Depth line: the amount of effort past which you stop and ask
rather than push on. Count it in what you can count (lookups, sources, files touched,
subagents), or in time when the person gave one: "I'll check in if this needs more than 8
sources." A depth word alone has no ceiling; the check-in point is the ceiling.

If the output feeds something dated (a meeting, an application, a deploy), the date caps depth:
put it in Doing and size Depth to fit.

"Be thorough" raises depth on the part the person is worried about, not on everything. Name that
part in the Depth line ("Deep on pricing, Solid on the rest") and keep the rest at Solid. If they
didn't say which part, guess the one where a mistake costs most and name it; they can correct it.

## 4. Need from you vs Assuming

Block on a question only when both hold:
- you cannot find the answer yourself, and
- a wrong guess would cost more than redoing the work at this depth, or the step can't be undone
  (sending, buying, deleting, publishing, anything outward-facing).

Everything else goes under **Assuming**, with the default you picked. Most questions belong there.
One exception: a default about personal data, access rights, money or security goes under Need
from you as a confirm-this item, even when nothing is irreversible yet.

This skill relies on asking the blocking questions, including in modes that otherwise discourage
asking.

- At most three blocking questions. Each answerable with one word or a tap; use a multiple-choice
  question tool when one is available. Lead with your recommended answer.
- Never ask what legwork could answer.
- If the person is away and a blocker is reversible, turn it into an assumption and say so. If it
  can't be undone, do the preparation and stop at the decision.
- When the result rests on the person's taste (tone, design, a judgment only they can make), ask
  for an example of good (a past piece, a page they like). If there is none, put a first-piece
  check under Need from you: one section, one screen or one example, before the rest.

## 5. During the work

- Re-contract out loud when something changes a field: "Depth now Deep on X, because Y." Never
  expand scope silently.
- At the check-in point, stop and ask in one line: what more depth would buy, and your
  recommendation.
- Stuck? Don't hand back a bare problem. Bring options and a recommendation, so the reply can be
  one word.
- New information that would have changed the start (budget, audience, an earlier decision): say
  what it changes. After two such corrections in a long thread, offer a fresh start from a
  consolidated brief; models do worse when the brief arrives in pieces.

## 6. End report: last lines of the final reply

```
Status: Done | Done except <x> | Blocked on <x>
Done when: <each criterion: met or not, with the evidence>
Assumed: <defaults that held; flag any the person should confirm>
Not checked: <what you didn't verify, and any risk they must know about>
Next: <who holds the next move, and what it is>
```

Write "Done" only if you would put your name to the result as it stands. No recap of the steps.
Drop a line that would be empty.

## Example

> "can you look into CRMs for our nonprofit"

```
Doing: a shortlist of CRMs the nonprofit's non-technical team can run without you, so they can pick one.
Not doing: migration plan or setup; that comes after they choose.
Depth: Solid. Vendor pricing and docs for each option, one comparison doc; I'll check in if more
  than 6 vendors look viable.
Done when: a doc ranking 3–4 CRMs against the team's needs, with monthly cost, the integrations
  that matter, and a recommendation.
Need from you: nothing.
Assuming: ~20 users with few paid seats; budget not a hard cap; the current mailing tool stays.
```

## Don'ts

- Don't ask questions instead of starting when nothing blocks.
- Don't let the contract run past six lines; it is a header, not a plan.
- Don't default to Deep. Don't treat "thorough" as "longer".
- Don't end with "let me know if you want more"; end with Status.

## When not to use

A plain question, a lookup, a quick fact, or a follow-up inside a task already contracted.
Re-contract only when scope changes.

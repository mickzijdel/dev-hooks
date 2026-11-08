---
name: the-algorithm
description: Use before the first edit of a change that is not fully specified (a feature, a fix with open choices, a new prompt, hook, process or doc), and when a request piles on requirements, options or steps. Triggers on "run the algorithm", "question the requirements", "what can we delete", "Musk's algorithm". Skip plain questions and fully specified edits ("rename X to Y", a typo).
---

# The algorithm

Five steps, in this order. Each step is a gate: write its result before you start the next. The order is the point: the common mistake is to optimise or automate something that should not exist.

1. **Question every requirement.**
2. **Delete** any part or step you can.
3. **Simplify** what is left.
4. **Accelerate** the feedback loop.
5. **Automate**, last.

**Skip** for an edit the person fully specified, and for follow-up edits inside a change that already has its block: write "Algorithm: fully specified" at most.

## Procedure

### 1. Question every requirement

List every requirement: the stated ones and the ones you inferred (a fallback, an option, a config flag, backwards compatibility, a UI state).

For each one, write down:
- **Who it comes from**: a named person and where they said it ("the person, this message", "Alex in the issue comment"), or a standing instruction (a CLAUDE.md, a repo rule, a safety rule). "Best practice" and "it's usual" are not owners. A requirement with no owner is the first candidate to cut. Correctness, tests the change needs and security are never cut for lack of an owner.
- **The strongest case that it is wrong or not needed.** Be specific. A requirement from a smart or senior person needs this most, because people question it least.
- **A verdict:** keep, cut, or ask.

Questioning a requirement the person gave you means **asking them**, never quietly dropping it. Ask only where the answer changes the design: one line per question, with your recommendation. For everything else, state your assumption and continue.

### 2. Delete

Delete from the **plan**: requirements cut in step 1, planned parts, options, steps and special cases. Ask once: can the whole change be deleted? (Does an existing tool, setting or one-line instruction already do it?)

Test: if you never end up adding back roughly 1 in 10 of the plan items you cut, you are not cutting enough.

Existing code, config or process outside the requested change is not yours to delete in this diff: propose it to the person, or log it where the project keeps improvement ideas.

### 3. Simplify

Only now design what survived. Use what the codebase already has, then the standard library or framework, then an installed dependency, then the least new code. Prefer fewer moving parts and fewer special cases.

### 4. Accelerate

Shorten the loop that tells you whether the change works: the test the change needs, failing first; a targeted command instead of the full suite while iterating; a preview you can click. Do not speed up a step that step 2 should have cut.

### 5. Automate

Automate a manual process only once it survived steps 1–4 and will repeat (a hook, a script, a scheduled job). This step does not apply when the automation is the deliverable, and the tests the change needs belong to steps 3 and 4, not here.

## Output

Show the block, then start the work in the same reply. Size it to the change: one line per step for a small fix ("none" is a valid answer), a short list under each for a feature.

```
The algorithm
1. Requirements: <each requirement: owner, verdict; questions asked>
2. Cut: <plan items cut; proposals for existing code>
3. Simplified to: <the design in one or two lines>
4. Faster loop: <the check you iterate against>
5. Automated: <what is automated, or "nothing">
```

In the end report, under what changed, list what you cut and what you added back.

## Common mistakes

- Jumping to step 3 or 5 because the request already sounded clear.
- Writing step 1 as a list of requirements without the case against each one.
- Treating "the person asked for it" as unquestionable, or the opposite: dropping it without asking.
- Writing the block after the work, as a summary. It goes before the first edit.

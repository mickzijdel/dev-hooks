---
name: grill
description: Use when a plan, design, or feature idea needs to be interrogated until it is fully specified — the user wants to be interviewed, one question at a time, until every open decision is resolved. Triggers on "grill me", "interview me", "ask me questions about this", "stress-test this plan with me", "help me fully specify this", or before writing a plan/PRD from a still-fuzzy idea — offer to grill first rather than drafting from guesses. Not for generating ideas from scratch (that's brainstorming), third-party critique (that's [[board]]), or failure-mode hunting (that's [[premortem]]).
license: "MIT; copyright Matt Pocock; see ../matt-pocock-skills-LICENSE.txt"
source: "adapted/merged from https://github.com/mattpocock/skills/tree/main/skills/productivity/grill-me, https://github.com/mattpocock/skills/tree/main/skills/productivity/grilling, https://github.com/mattpocock/skills/tree/main/skills/engineering/grill-with-docs"
---

# Grill

Interview the user relentlessly about a plan or design until you reach shared understanding. The deliverable is a resolved decision tree, restated back as a decisions summary — not a document (unless the user asks for one).

## The loop

1. **Map the decision tree first.** Sketch the branches the plan actually depends on — scope, data model, interfaces, edge cases, sequencing, rollout. Walk them in dependency order: never ask about a leaf while its trunk is unresolved, because the trunk's answer reshapes the leaves.

2. **One question at a time.** Ask, wait for the answer, absorb it, then ask the next. Batching questions is bewildering, and each answer re-ranks what's worth asking next.

3. **Recommend an answer with every question.** The user reacts faster and more honestly to a position than to a blank. State your recommendation and the one-line reason; let them push back.

4. **Legwork before asking.** If the codebase, docs, git history, or a quick command can answer the question, go look instead of asking. The user's time is for judgement calls, preferences, and things only they can know.

5. **Show the tree between rounds.** Every few questions, restate which branches are resolved (with their decisions) and which are still open. This is how the user steers and how you avoid re-asking.

## Completion criterion

Done only when **every branch is resolved** — no remaining question whose answer would change the plan — and you have restated the full set of decisions back as a compact summary the user confirms. Not done because the user went quiet, a round number of questions has passed, or the conversation feels long. If the user cuts the session short, list the still-open branches explicitly so nobody mistakes the plan for fully specified.

## Composing with other skills

- When a term crystallises or two words turn out to mean the same thing, run [[domain-modeling]] inline to capture it in the glossary — grilling is where vocabulary gets sharp.
- A resolved branch that was hard to reverse and cost real deliberation is an [[adr]].
- When the plan is fully specified, offer a [[premortem]] before execution starts.

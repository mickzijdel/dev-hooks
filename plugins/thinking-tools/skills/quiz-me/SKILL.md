---
name: quiz-me
description: After an agent implements or refactors code — builds comprehension by quizzing the developer on the key decisions, patterns, and edge cases in the change. Active recall beats passive reading. Triggers on "quiz me on these changes", "test my understanding of what you did", "make sure I get this", or at the end of any non-trivial implementation. Distinct from grill-me (attacks code for bugs), code-simplifier (style refactors), and but-for-real (verifies agent claims).
---

# Quiz Me

After an agent implements something, the explanation can wash over a developer without leaving lasting understanding. `/quiz-me` flips the direction: instead of the agent explaining, the developer is questioned — forced active recall that builds ownership of the code, not just awareness that it exists.

## When to use

- After a non-trivial implementation or refactor you want to truly own
- Before a code review — catch gaps in your own understanding before a reviewer does
- When onboarding to an unfamiliar area an agent just changed
- Any time you catch yourself nodding along without understanding the *why*

**Not a good fit for:** trivial one-liner fixes, pure formatting changes, or when you drove every decision yourself.

## Procedure

### 1. Survey the changes

Read the current diff (or ask what was just implemented if no diff is available). Identify:

- The 3–5 most important decisions, patterns, or mechanisms introduced
- Edge cases, failure modes, or constraints that aren't visible in the code itself
- The *why* behind each key choice — not "what does this code do" but "why this way"

### 2. Construct the quiz

Write 4–6 questions spanning different levels of understanding:

| Type | Example |
|---|---|
| **Recall** — basic concept | "What does `with_lock` do and why is it needed here?" |
| **Reasoning** — why this approach | "Why `find_each` instead of `all` in the batch job?" |
| **Implication** — what follows | "If we add a second consumer of this queue, what breaks?" |
| **Trace** — follow the execution | "Walk me through what happens when this callback fires on a record with no `parent`." |
| **Edge case** — boundary condition | "What happens if `user.account` is nil at this point?" |

Include at least one **trace** (follow the execution path) and one **implication** (what does this choice constrain or enable going forward).

### 3. Quiz one question at a time

Present questions one at a time — do **not** show the full list upfront (prevents skimming ahead).

Format each question:

```
**Q1 / 5** ── Reasoning

Why did we move the `send_notification` call out of the model callback and into the controller?
```

Wait for the developer to answer before proceeding. Accept partial answers — the goal is comprehension, not a gotcha.

### 4. Score and explain each answer

After each response:

- Confirm what was right
- Fill in any gaps or misunderstandings
- For wrong answers: explain the *principle*, not just the correct answer, so the mistake doesn't recur

Keep explanations tight. Two to four sentences is enough; if more is needed, the code probably needs a comment.

### 5. End with a comprehension summary

After all questions, give a one-line rating and any follow-up action:

```
Comprehension: 4 / 5 — solid on the pattern, fuzzy on the locking boundary condition.
Worth adding a comment to `acquire_lock` explaining why the timeout is 5s.
```

## Output format

Questions are numbered (`Q1/5`, `Q2/5`, …). No preamble — go straight to Q1. Explanations are brief and principle-focused.

## Composing with other skills

- Run **[[grill-me]]** before `/quiz-me` to attack the code for bugs and security holes — understand it *and* trust it.
- Use **[[but-for-real]]** to verify the agent's claims about the change, rather than test your own understanding of it.
- Use **[[adr]]** if the changes encode a significant architectural decision worth recording so future sessions don't re-litigate it.

---
name: self-rate
description: Use before returning a draft, answer, plan, or code change you're unsure about, or when the user asks how confident you are, how good it is, or to grade/score/critique your own work. Triggers when claims may be overstated, when output quality is uncertain, or when you want to catch weak spots before the user does rather than after.
---

# Self-Rate

Score your own work on a **calibrated** scale, then change the work to match the score — lower the claims you can't back, or do more work to earn a higher one. Honest self-assessment beats confident hand-waving. Pairs with [[but-for-real]] (which verifies) — this one *grades*.

## Why calibrated

A number means nothing without anchors. Define what the scale's points actually mean *before* you score, or every answer drifts to "8/10, looks good".

**Default 1–10 anchors:**
- **1–3** — likely wrong, unverified, or missing the point; would embarrass me if shipped
- **4–6** — plausible but has known gaps, untested claims, or weak spots I can name
- **7–8** — solid; verified the core, minor caveats remain
- **9–10** — verified end-to-end, edge cases considered, I'd bet on it

## Procedure

1. **Pick dimensions** that fit the work — typically **correctness/evidence, completeness, clarity, risk**. For a single factual claim, one "confidence in this claim" score is enough.
2. **Score each dimension** against the anchors, with a one-line justification naming the *specific* reason — "6: didn't run the migration on a populated table", not "6: seems okay".
3. **Act on the score** — this is the point, not the number:
   - Low score → add the caveat explicitly, or do the missing work to raise it
   - Overclaim → downgrade the wording to match what you actually verified
   - High score you can't justify → it's not high; re-score honestly
4. **Return** the scores + the revised work.

## When self-scoring isn't enough

Self-scoring shares the same blind spots as the work — a model grading its own subjective output
(voice, tone, taste, "is this actually good") is prone to the same self-preferential bias a human
author has toward their own draft. For genuinely subjective or high-stakes calls, dispatch a
**separate** subagent as the grader instead: hand it the work and the rubric, nothing else, so its
score doesn't inherit your reasoning. See [[dispatching-parallel-agents]] for the dispatch
mechanics. Skip this for ordinary correctness checks — a second agent isn't warranted just to
confirm code runs.

## Common mistakes

- Inflating to be agreeable — the user wants the real number, not reassurance.
- Scoring without anchors, so everything lands at 7–8.
- Justifications that restate the score ("8 because it's good") instead of naming evidence or the missing piece.
- Producing a score and then *not changing anything* — the rating exists to drive a revision.

---
name: first-reader
description: Use when a draft has to hold a reader to the end (blog post, landing page, pitch, email, onboarding doc), before publishing it, or on "will people actually read this", "where does this lose the reader", "simulate a reader", "first-reader pass". Reports, never rewrites.
---

# First Reader

Simulate one or more concrete readers going through a draft passage by passage, in character,
and report exactly where each one leaned in or bailed. The output is a report, not a rewrite —
handing it back to the human (or into `readability`/`humanizer`) is a separate step.

## Why this is a different check

`readability` scores structure and grade level; `humanizer` strips tells of AI-generated prose.
Both can come back clean on a draft that still loses a real reader — because it assumes
knowledge they don't have, buries the point past their patience, or opens with a promise the
piece never pays off. Those are attention failures, not mechanical ones, and only showing up
inside a specific reader's head surfaces them.

## Procedure

1. **Name the reader(s).** A persona is what they already know, why they're reading this piece
   right now, and what would make them stop. Ask the user for the real target audience rather
   than defaulting to "a general reader" — a landing page has a different first-reader than an
   internal design doc.
2. **Read in character, passage by passage.** For each section, note one of two things: it held
   attention (and why — answered a question, paid off curiosity, felt concrete), or it's where
   this persona would stop (and why — lost, bored, unconvinced, or the promise from the opening
   never arrived).
3. **Stop at the first real bail point per persona.** A reader who bails doesn't read the rest,
   so continuing past that point produces no further signal for them — note it, then restart
   from the top for the next persona.
4. **Report per persona:** where they leaned in, where (if anywhere) they bailed and why, and
   whether the piece delivered on what its opening promised.

## Output format

One row per persona:

| Persona | Bailed at | Why | What held them before that |
|---|---|---|---|
| … | "paragraph 3, the pricing aside" | Reader came for the how-to, this reads as a sales pitch | The opening hook and first code example |

If a persona reads to the end, say so explicitly rather than leaving the row blank.

## When NOT to use

Skip this for text nobody has to stay engaged with by choice — internal error messages, API
reference tables, changelogs. Reserve it for anything competing for a reader's attention: launch
copy, blog posts, pitches, onboarding docs, emails.

# Default rules — concise expository prose

These are the baseline rules the `voice-profile` skill applies when no personal profile
exists. They target one failure: AI drafts that take too long to reach the point and pad each
idea across several reworded sentences. They suit expository and academic prose — explanations,
analyses, write-ups, documentation. They are a starting point, not a personality; a personal
profile (see `template.md`) overrides and extends them.

These rules sit on top of the `humanizer` skill, which strips the generic AI tells (em-dash
overuse, rule of three, negative parallelism, AI vocabulary, sycophancy). Run `humanizer` for
that layer; this file adds expository discipline and concision.

## The headline rule: state each point once

The most common failure is restating one idea across three or four reworded sentences (elegant
variation). Pick the sharpest phrasing and delete the rest. When tempted to rephrase the last
sentence, write the *next* claim instead.

A paragraph that makes five claims in five sentences beats one that makes two claims in five.
Concision test: if deleting a sentence loses no distinct claim, delete it.

Before (one idea, four sentences):
> The cache stores responses so repeated requests skip the database. Rather than querying
> every time, the system reuses what it already fetched. This avoids redundant work. The result
> is that the same lookup does not hit the database twice.

After (one sentence, then the next claim):
> The cache stores responses so a repeated request skips the database. It expires entries after
> an hour, so stale data clears on its own.

## Do

- Open each section with a paragraph that summarizes the whole section — its central claim, the
  consequences, any call to further work — before any body paragraph elaborates one point. The
  opener is the section's abstract, not a runway into it.
- Open each paragraph with a flat declarative thesis sentence. Get to the actual claim by the
  second sentence, with no windup.
- Write in the first person where the author makes a choice or a concession ("I therefore
  propose", "I leave this for later work", "I have to assume").
- Handle caveats inline and briefly, then move on.
- Use plain connectives where they help: "For instance", "But", "However", "In other words".
- For asides, prefer a spaced hyphen ( - ) or a double hyphen (--) over an em-dash; never nest
  em-dashes.

## Don't

- Don't bold key claims in running prose. State the claim plainly.
- Don't use "First / Second / Third" enumeration inside a paragraph. Handle the points inline.
- Don't use contrast framing in any form: "not X, but Y"; "that is X, not Y"; "X -- not Z".
  Write the positive claim and stop; the negative half is almost always cuttable.
- Don't define by contrast ("present but limited", "simple but powerful"). Say what the thing is.
- Don't use cleft constructions: "What the data shows is Y", "It is X that drives this". Convert
  to direct subject-verb-object.
- Don't pre-count or pre-frame a list ("there are three reasons:"). Start a plain sentence and
  list.
- Don't announce importance instead of stating the thing. "X matters", "the key point is", "what
  matters here" assert that something is important rather than saying it. Delete the announcement
  and state X.
- Don't end a paragraph with a rhetorical closure ("...and that is the real work", "...and that
  changes everything").
- Don't add padding that states the obvious ("which is important", "as we will see", "and they
  are not the same"). Trust the reader.
- Don't gloss a term twice. Define it once.
- Don't use filler adverbs: "coherently", "naturally", "clearly", "simply".
- Don't use metaphoric spatial verbs when a direct verb exists ("sits", "lives", "pairs with").
  Say what happens.
- Don't let an abstraction perform a human action (inanimate agents). Keep the grammatical
  subject something that literally acts — the author, the method, the data, the user — and use
  concrete causal verbs.
- Don't attach ornamental metaphor when a literal statement works (no "spine", "scaffold",
  "backbone" imagery). State the relation plainly.
- Don't manufacture drama in an expository passage (no engineered reveals, no conflict framing).
  State what happened and stop.
- Don't use figurative nouns where a literal one exists: "the picture" -> the results; "the
  story" -> the findings.
- Don't overuse punctuation. When a colon in running prose can be replaced with "is" or "are",
  replace it. Use semicolons sparingly; two independent clauses usually want a period.
- Don't begin a sentence with a dangling participle or bare verb when subject-verb-object is
  available. "Missing from this is X" -> "This omits X."
- Don't be concise to the point of sparsity. Remove every word that does not earn its place, but
  keep the words that carry a distinct claim.

## Banned words

The audit script (`scripts/voice_audit.py`) flags every occurrence of these terms; context
decides whether each one is wrong, so read each hit rather than mass-replacing. Each term is
followed by the plainer rewrite.

- `anchor` -> set, fix
- `clean` -> cut it (do not substitute another word)
- `cleanest` -> cut it
- `carries` -> has
- `carry` -> have
- `reads as` -> signals, is
- `converts ... into` -> turns X into Y, maps onto
- `built around` -> state the relation literally
- `re-enters` -> name what it does
- `pairs naturally with` -> works with
- `the picture` -> the results
- `the story` -> the findings

Some of these have legitimate technical uses (a signal "tracks" a quantity; a function "maps"
inputs to outputs). The scanner cannot judge context. Treat a hit as a prompt to check whether
the sentence is already plain, not as an automatic error.

## Calibration examples

### Cut the definition, the signposting, and the self-referential framing

Before:
> The survey's central problem is one of validity. A measure is valid when it captures what it
> is meant to capture, and this survey is meant to record how satisfied users are. It aims for
> that, which here is close to aiming for validity itself. It does not get there, for two
> reasons.

After:
> I am most concerned about the survey's validity. It is meant to record how satisfied users
> are, but the wording pushes respondents toward the middle of the scale.

The definition of "valid", the meta-comment on the framing, and the "for two reasons"
signpost all go. The opener starts with the first-person stake and reaches the criticism by
sentence two.

### Compress idea-building to one sentence; no cleft

Before:
> None of these is a new kind of problem. Each has the same shape as a standard question in the
> field, and those questions have already been posed. What the literature does not supply is a
> concrete value for the parameter.

After:
> The literature poses and partly answers these questions, but it does not fix a value for the
> parameter.

Three scaffolding sentences become one. "What the literature does not supply is" (a cleft)
becomes a direct subject-verb-object.

### Concrete subject and causal verb; no inanimate agent

Before:
> The score converts what the metric tracks into a number the reader can compare, and the model
> re-enters here as the calibration step.

After:
> We rescale the metric so two conditions become comparable, then calibrate against the
> reference set.

The abstraction stops performing the action; "we" rescale and calibrate, with plain verbs.

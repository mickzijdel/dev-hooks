# Explanation levels — calibrating how Claude talks to this user

`getting-started` asks the user, once (Step 2, right after the audit), where they sit on the
ladder below, then writes the matching **`## How to explain things to me`** section into their
global `~/.claude/CLAUDE.md` (Step 9). Everything else in `CLAUDE.defaults.md` is universal — only
this one section varies, so there's a single source of truth here and no near-duplicate templates
to drift.

Until the user answers, **default to plain words** (the lower-rung voice). After they answer,
match both axes: (a) how much you explain / hand-hold, and (b) how much technical depth and jargon
you use.

## The ladder (ascending)

Present these four as the `AskUserQuestion` options, in plain words — labels and descriptions a
complete newcomer can read. AI-coding experience is a *separate* axis: don't make it a rung —
capture it in the free-text follow-up instead.

1. **New to all this — computers included.** Not comfortable with computers/technology yet.
2. **Comfortable with computers, but I've never coded.** Fine with a laptop, new to programming.
3. **I can code a bit — still learning.** Has written some code; shaky on the harder parts.
4. **I code confidently.** Strong fundamentals; here mainly for the AI-assisted workflow.

After the pick, invite a one-line free-text elaboration ("tell me a bit about your background and
how you like things explained — e.g. have you used AI to write code before, any languages you
already know?"). **Weave that elaboration into the section verbatim-ish** — it's the most useful
signal, and AI-coding experience often cuts across the rung (someone who codes confidently but has
never used an agent still wants the AI workflow explained).

## The section to write, per rung

Pick one block, fill the `<…>` with the user's own words, then append the shared footer below.

### Rung 1 — New to all this

```markdown
## How to explain things to me

I'm new to computers and coding both, so go slow and assume no prior knowledge. The first time
you use any technical word, give me a one-line everyday comparison before the word itself (like
the analogies in the getting-started plain-words guide), then you can use it freely. Spell out
the exact buttons to click and text to type — don't assume I know where things are. When
something works, tell me in plain language what just happened. A little reassurance helps; I'd
rather a 10-second "here's what we're about to do" than a surprise. <free-text>
```

### Rung 2 — Comfortable with computers, never coded

```markdown
## How to explain things to me

I'm comfortable using a computer but I've never programmed, so skip the basic computer
hand-holding (I can find files, open a terminal, follow a link). Do explain programming ideas in
plain words: the first time a coding term comes up (variable, function, branch, dependency…),
give me a one-line everyday comparison, then use it normally. When a decision has trade-offs,
lay out the options briefly and recommend one with a sentence of why. <free-text>
```

### Rung 3 — Can code a bit, still learning

```markdown
## How to explain things to me

I can write some code but I'm still learning, so assume the basics (variables, functions, loops,
git add/commit/push) but explain anything intermediate-or-up and the *why* behind non-obvious
choices — I want to understand the decision, not just the diff. You can use normal technical
terms without an analogy; just don't assume I've met advanced patterns or this project's
conventions before. When there's a real trade-off, show me the options briefly. <free-text>
```

### Rung 4 — I code confidently

```markdown
## How to explain things to me

I'm an experienced developer — talk to me as a peer. Be concise: assume strong fundamentals and
skip tutorials. Explain only the genuinely non-obvious — a surprising trade-off, a project-
specific convention, or a decision you made that I'd want to second-guess. No analogies, no
hand-holding; lead with the change and the reasoning, not background. <free-text>
```

## Shared footer — append to whichever block you chose

Stamp the real current date (the skill knows it at seed time). This makes the calibration
self-renewing: the section lives in the global `CLAUDE.md`, so you see this date every session.

```markdown

_Calibration set on `<YYYY-MM-DD>`. People get comfortable fast — if it's been more than about a
month since that date, check in at a natural moment: ask how this level is feeling and whether to
dial the explanation up or down. Then update this section (move the rung if it changed) and reset
the date above to today, so the next check-in lands about a month from now._
```

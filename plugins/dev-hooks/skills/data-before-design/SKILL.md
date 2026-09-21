---
name: data-before-design
description: |
  Use when about to build, restyle or lay out anything that displays stored data — a card,
  panel, detail view, dashboard, table, report, profile page or summary strip — and the design
  depends on what the data actually contains. Also when a field looks obviously useful, when a
  stakeholder describes what they want to see, or when choosing between layouts for the same
  records. Not for pure aesthetics (design-process), chart colour and form (dataviz), or
  floating UI mechanics (popovers-tooltips).
---

# Data before design

Three things decide whether a view of data is any good, and all three are settled before you
write markup: **what decision the view serves**, **what is actually in the field**, and **which
of several layouts the person wants**. Skipping any of them produces a view that looks finished
and is wrong.

## When to use

- Any card, panel, table, dashboard or detail view over records you did not author
- A stakeholder says "show me X" and X is a column name
- You are about to summarise, truncate, badge, sort, colour or count a field
- You are choosing between two ways to lay out the same information

Skip when the data is your own fixture, or the view is one value you already printed.

## Step 0: name the decision

Write one sentence before touching the data: *"Someone looking at this is deciding ___."* If
you cannot finish it, you are building a data dump and the layout question has no answer.

- **Every field earns its place by changing that decision.** Interesting but decision-neutral
  belongs in the detail view, not the card.
- **Prominence tracks decision weight, not query convenience.** The field that was easiest to
  fetch is not the field that deserves the largest type.
- A stakeholder naming a column has told you the *data* they want, not the *decision*. Ask what
  they would do differently depending on its value.

## Step 1: profile the field, then design

Query before you design. For every field the view will show:

| Check | Why it changes the design |
|---|---|
| Non-null count | A field NULL on every row needs no card — it needs a bug report |
| Distinct values | Four values is a chip set; four thousand is a search box |
| Length: min / mean / **p95** / max | The mean hides the overflow — size the container to p95, and decide deliberately what the tail does |
| Coverage across records | A card that fires for 1.6% of records is an empty state with a rare exception |
| Cardinality per parent | One note per person is a paragraph; twenty is a list with its own affordances |
| Date presence | You cannot show staleness for a field that carries no date |
| Vocabulary | Free text with eight house phrasings needs normalising, not rendering |
| A comparator exists | A bare number is unreadable — see below |

State what you found before proposing the design, in numbers.

### Every number on screen needs something to compare it against

`52 notes` tells the reader nothing: they cannot tell whether it is a lot. `52 notes (median
4)` is a finding. Before displaying any count, total or score, find its comparator — a median,
a target, the previous period, or the rest of the set — and display them together. If no
comparator exists, that is evidence the number should not be on screen.

The degenerate case is a number that never varies: a count true of every record reads as a
finding and is noise.

## Step 2: mock the options, then build

For anything card-shaped, produce **several** static mocks from real records and let the person
choose. Build only after that.

- Say in one line what each option optimises for and what it costs
- Mocks are throwaway HTML, not a component — do not wire them up

### Mock six states, not one

Design every state the view can be in, each from a real record:

| State | Draw it from |
|---|---|
| Ideal | The typical record — the one at the median, not the one you picked |
| Empty | A record with nothing in the field, *and* a brand-new account with no records at all |
| Partial | Some fields filled, some not — in real data this is the common case, not the exception |
| Loading | What occupies the space before the data arrives, at the size the data will be |
| Error | The fetch failed, or the value is malformed and cannot be rendered |
| Done | What confirms an action the view offers actually happened |

### Then the stress case

Volume extremes (busiest, typical, empty) are not the only extremes. A **stress case** is data
that is present, well-formed, and painful: the name the field mangles, the record whose status
makes a cheerful badge wrong, the person whose deleted account the summary still counts. Pick
the one record that would most embarrass this view and render it.

## Rendering rules that fall out of the data

- **The empty state does work.** "No notes yet" is a dead end. Say why it is empty and what
  fills it. An empty state a user meets on day one is onboarding, and is worth designing.
- **Numbers in a table:** right-align, tabular figures (`font-variant-numeric: tabular-nums`),
  one precision for the whole column, units in the header rather than repeated in each cell.
- **The default sort is a design decision.** Records arriving in primary-key order is the
  absence of one.

## Common mistakes

| Mistake | What happens |
|---|---|
| Designing from the schema | The column exists; the data does not |
| Building with no decision named | Everything gets equal weight, because nothing has a reason to be bigger |
| Giving the easiest field the most prominence | The layout describes the schema, not the job |
| Showing a number with nothing to compare it to | The reader cannot tell whether it is good, and stops looking |
| Counting something that is always true | A count that never varies reads as a finding and is noise |
| Trusting a plan written before the data was seen | You build the thing the plan named, not the thing the data supports |
| Mocking only the ideal state | The design collapses on the record that has nothing, or half of something |
| Testing only volume extremes | The view survives the biggest record and humiliates someone on an ordinary one |
| Building one option because it was described first | The person cannot choose what they were never shown |

## Real-world impact

In one session, profiling first would have pre-empted four rebuilds: a field NULL on all 30,293
rows still had a badge designed for it; a "summarise the notes" feature was specified for notes
averaging 52 characters; a prominent count turned out to be true of every record; and 8% of a
text field was silently truncated upstream with nothing in the UI saying so. Each was found
mid-build, after the card existed.

## Where the non-obvious parts come from

- Decision-first, and prominence by decision weight — Stephen Few, *Information Dashboard Design*
- A number needs a comparator — Few again, on context as the thing that makes a number mean anything
- The six states — Scott Hurff's UI Stack
- Stress cases — Eric Meyer & Sara Wachter-Boettcher, *Design for Real Life*

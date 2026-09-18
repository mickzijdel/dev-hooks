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

Two things decide whether a view of data is any good, and both happen before you write markup:
**what is actually in the field**, and **which of several layouts the person wants**. Skipping
either produces a view that looks finished and is wrong.

## When to use

- Any card, panel, table, dashboard or detail view over records you did not author
- A stakeholder says "show me X" and X is a column name
- You are about to summarise, truncate, badge, sort, colour or count a field
- You are choosing between two ways to lay out the same information

Skip when the data is your own fixture, or the view is one value you already printed.

## Step 1: profile the field, then design

Query before you design. For every field the view will show:

| Check | Why it changes the design |
|---|---|
| Non-null count | A field NULL on every row needs no card — it needs a bug report |
| Distinct values | Four values is a chip set; four thousand is a search box |
| Length: min / mean / max | A 50-character field needs no summarisation, truncation or expander |
| Coverage across records | A card that fires for 1.6% of records is an empty state with a rare exception |
| Cardinality per parent | One note per person is a paragraph; twenty is a list with its own affordances |
| Date presence | You cannot show staleness for a field that carries no date |
| Vocabulary | Free text with eight house phrasings needs normalising, not rendering |

State what you found before proposing the design, in numbers.

## Step 2: mock the options, then build

For anything card-shaped, produce **several** static mocks from real records and let the person
choose. Build only after that.

- Render each option with the real extremes: the busiest record, the typical one, the empty one
- Say in one line what each optimises for and what it costs
- Mocks are throwaway HTML, not a component — do not wire them up

## Common mistakes

| Mistake | What happens |
|---|---|
| Designing from the schema | The column exists; the data does not |
| Counting something that is always true | A count that never varies reads as a finding and is noise |
| Trusting a plan written before the data was seen | You build the thing the plan named, not the thing the data supports |
| Mocking only the happy path | The design collapses on the record that has nothing |
| Building one option because it was described first | The person cannot choose what they were never shown |

## Real-world impact

In one session, profiling first would have pre-empted four rebuilds: a field NULL on all 30,293
rows still had a badge designed for it; a "summarise the notes" feature was specified for notes
averaging 52 characters; a prominent count turned out to be true of every record; and 8% of a
text field was silently truncated upstream with nothing in the UI saying so. Each was found
mid-build, after the card existed.

---
name: practical-charts
description: Use when making or reviewing a chart or data table that will be posted, shared, or put in a report, deck or newsletter, and on "make this chart shareable", "chart this for a post", "is this chart misleading", "critique my chart". Not for palette values (dataviz) or which fields a view shows (data-before-design).
---

# Practical charts

A chart that leaves the tool that drew it gets a few seconds of attention, at phone size, often
as a screenshot cut loose from the post around it. So the **words** carry the finding, the
**encoding** stays honest, **color** goes to one story, and everything a reader needs to trust
the chart sits **inside the image**. Thirteen rules follow; the checklist at the end is the
done-when.

Two neighbours own the rest. When the chart shows stored records you did not author,
`data-before-design` comes first: which fields to chart, what is actually in them, and what each
number is compared against. Palette values and mark specs come from `dataviz` when it is loaded.
This skill decides what the chart says and whether it survives being reposted.

## Anatomy of a chart that travels

1. **Headline**: the finding, as a sentence you could say out loud.
2. **Subtitle**: what was measured, the units, where and when. The dry part goes here.
3. **Annotation**: the event that explains the change, placed where the change happens.
4. **End label**: the latest value sits at the end of the line, so nobody reads it off the axis.
5. **Quiet axis**: hairline gridlines at a few round numbers. The data is the loudest thing.
6. **Source and byline**: inside the frame, so they survive every crop and repost.

## Words

**1. Write the title as a headline.** State the finding, not the contents.
`Weekly sign-ups by channel, Q3 2026` makes the reader hunt for the point;
`Referrals now bring in more sign-ups than ads` lands it. Measure, units and period move into a
smaller, lighter subtitle. The one colored mark is the thing the headline names.

**2. Annotate the moment that matters.** A spike with no explanation gets noticed and scrolled
past. Put a short note next to the event, in the same small type as the labels: a shaded band
for a period, a thin rule for a moment, a `+1.9 points` callout above the bar that differs. No
footnotes. Stripping a chart is half the job; adding back the few words that explain it is the
other half.

**3. Put the source and the byline inside the image.** Bottom left, small and grey:
`Source: <who>, <sample size>, <date>`. Bottom right: `Chart: <name or handle>`. Ask the person
for the byline; never invent a handle.

## Encoding

**4. Start bars at zero.** Bar length encodes the value, so a cut axis misstates the ratio. When
the difference is small, say it exactly in the title or chart the difference itself. A line
chart may zoom, because it encodes change by slope, provided the axis is labeled.

**5. Use one y-axis per chart.** With two, the author picks where the lines cross, so any two
series can be made to look linked. Index both to a common base (first period = 100), or stack
two small charts that share the x-axis.

**6. Sort the bars, and turn them sideways.** Sort by value unless the categories have a natural
order (age bands, months, funnel steps). Labels longer than one word mean horizontal bars, so
no label is ever tilted. Value labels at the bar ends replace the grid.

**7. Use bars instead of pies for close values.** People compare lengths on a shared baseline far
better than angles. A pie only works for two or three slices with a simple message, such as
"about a quarter".

## Emphasis and color

**8. Highlight one series and grey the rest.** One series in color, its label in bold; the others
thin and light grey as context. The headline and the color say the same thing. Several stories
means several charts; across those charts, one category keeps one color (the category table in
`data-before-design`).

**9. Label lines directly.** Put each line's name and latest value at its end, ordered as the
lines finish, and drop the legend. Label text stays neutral; the line beside it carries the
identity. This also works for colorblind readers and in greyscale.

**10. Use one hue for amounts.** Light to dark in one hue for amounts; two hues meeting at a
neutral grey only around a meaningful midpoint; distinct hues only for unordered categories.
No rainbow scales, and never let red versus green carry the meaning alone (about 1 man in 12
can't tell them apart).

## Clutter and the medium

**11. Cut the chrome, keep the explanation.** Remove plot backgrounds, borders, heavy
gridlines, a legend for a single series, markers on every point, and decimals beyond what the
point needs. Put the unit on the top tick or first value label only (`$55`, `31 hrs`), not on
every number. Then add back only the notes that explain what remains.

**12. Design for a phone at arm's length.** One finding per image; four findings are four images
in a thread, not one dashboard export. An image N px wide shows on a phone at 375/N of its
size: 14 px labels in a 1200 px export become 4 px. Export with an opaque background: the
image won't follow the reader's dark mode, and a transparent PNG puts dark text on a dark
timeline.

## Tables

**13. Right-align numbers and drop the grid.** This is the full table rule; `data-before-design`
points here. Right-align numbers in tabular figures, one precision per column, units in the
header (`Revenue ($K/mo)`), a true minus and an explicit plus on changes (`−0.2`, `+3.4`). Replace cell borders with white space and a few light rules,
tint the row that matters, and add a small inline bar when the pattern matters more than the
digits. Rules 1 and 3 apply to tables too.

## Check before you hand it over

Done when every line holds:

- [ ] The title is a sentence stating a finding; the subtitle names measure, units and period.
- [ ] Every bar axis starts at zero, and the chart has one y-axis.
- [ ] Bars are sorted by value, or the natural order is the reason they are not.
- [ ] At most one series is in color, it is the one the headline names, and no legend remains
      where direct labels fit.
- [ ] Amounts use one hue, and no red–green pair carries meaning alone.
- [ ] Source, date and byline are inside the image.
- [ ] **Phone check:** the export scaled to 375 px wide (`magick chart.png -resize 375x phone.png`,
      or a screenshot at a 375 px viewport for an HTML chart), then viewed with Read. The
      headline, every end label and every annotation are readable without zooming.
- [ ] **Background check:** `magick chart.png -bordercolor white -border 40 on-white.png` and the
      same with `black`, both viewed with Read. The chart reads as a card on both, and no text
      vanishes.

Report the two checks as passed or failed, with the image paths.

## Where the rules come from

Claus Wilke, *Fundamentals of Data Visualization*; Dona Wong, *The Wall Street Journal Guide to
Information Graphics*; Lisa Charlotte Muth on the Datawrapper blog; Jonathan Schwabish, "Ten
Guidelines for Better Tables"; Cole Nussbaumer Knaflic, *Storytelling with Data*; John
Burn-Murdoch's FT chart talks; Edward Tufte; Alberto Cairo, *How Charts Lie*; Cleveland and
McGill (1984) on graphical perception. Gathered in the "Practical Charts" guide.

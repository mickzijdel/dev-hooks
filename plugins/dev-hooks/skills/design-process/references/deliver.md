# Deliver — polish by subtraction

Once we've gotten to a unique, standout design, the final step is to clean up the details
and get it ready for production use. AI can build amazing, striking visuals, but your
judgment will be key to making sure the design makes sense, flows well, and serves its
practical purpose for users.

## Remove before you add

AI loves to add more, but it rarely takes away. One of the biggest signs that a design is
AI-generated is that it overexplains everything or contains elements that don't serve any
practical purpose. By contrast, a design that exercises restraint immediately looks premium
and tasteful.

When polishing AI designs, most of the effort goes into removing things. In the worked
example — a calorie tracker that had been asked for a "clean, minimalist design" — the result
wasn't bad, but a lot in it wasn't adding value:

- Pink glowy effects in the background and on the progress bar
- Random colors and highlights on text
- Extra labels and empty space when displaying all the foods for a day, when the images
  already communicate this
- Custom buttons and text fields that look worse than built-in (native) components

The dial-back that fixed it:

- Simplify the layout into an image-centric grid
- Get rid of gradients, glows, and unnecessary containers
- Aim for a truly minimalist aesthetic that feels native to the platform

The result is opinionated and allows the visuals to speak for themselves. It uses native
components, and the excessive colors and gradients are gone. The text is smaller, simpler,
and tighter. This is good design.

Today's models would never think to make these choices on their own. Remember, AI doesn't
like to take risks, and it's risky to strip down a design and delete code. The model needs a
push. Look over the design and ask what really needs to be there. Often, putting less on the
screen communicates *more*, because you can hold users' attention without overwhelming them
with clutter.

## The subtraction pass

Walk the page top to bottom and, for each element, ask "what breaks if this goes?" If the
answer is "nothing," delete it. Chanel's rule applies: before leaving the house, look in the
mirror and remove one accessory. Spend your boldness in one place — let one element be the
memorable thing and keep everything around it quiet.

**Judge a tell by intent, not by appearance.** A pattern is a tell when it is a default
reached for without reason, not whenever it appears. One gradient tied to the brand and
used well is not slop; glass and bento grids are legitimate when the content calls for
them; a confident design that happens to be minimal is not "timid." Restraint executed
well is a decision — reward it. And **a clean audit is a valid result**: if the page is
already distinctive and intentional, say so and stop. Do not manufacture problems.

In rough order of how often things need to go:

| Remove | Because |
|--------|---------|
| Glows, blurs, drop shadows on everything, background blobs | Decoration standing in for a decision; the loudest AI tell |
| Gradients on text, buttons, backgrounds | Same — replace with one flat colour or a real image/texture |
| Cards nested in cards; containers with no content of their own | Structure that explains nothing |
| Labels that repeat what the visual already says ("Image of…", "Your dashboard") | Over-explaining |
| Filler copy: "Unlock your potential", "Seamless", "Effortless", rule-of-three feature grids | Words the reader skips; say the concrete thing or nothing |
| Custom-styled inputs, selects, scrollbars that are worse than native | Native is accessible and familiar for free |
| Emoji used as icons; badges and pills on every item | Visual noise with no hierarchy |
| A second and third accent colour | One accent, used rarely, reads as intent |
| Animations on load for every element | Motion should mean something; one considered move beats ten entrances |
| Sections that exist because a template had them (testimonials with no testimonials, stats with made-up numbers) | Fabricated content undermines the real content |

Triage by who would notice, and fix in that order:

- **P0 — a layperson sees it's AI-made:** the purple/blue gradient, one generic sans for
  everything, an untouched component-library theme, gradient-clipped headline text,
  reflexive glassmorphism, blurred blob backgrounds.
- **P1 — a designer or developer sees it:** the same radius and shadow on every surface,
  the default page shell and four-column footer, icon-in-a-rounded-square feature grids,
  dead hover/focus states, arrows glued to every CTA, default-blue buttons, "Elevate your
  workflow" copy, coloured left-border cards.
- **P2 — craft gaps:** flat spacing with no rhythm, the same fade-up entrance on every
  section, missing empty/loading/error states.

**Native controls beat custom ones** unless the custom one beats native on a named axis
(and you can say which). A styled `<div>` select loses keyboard behaviour, screen-reader
semantics, and the platform's mobile presentation; the custom one has to earn all of that
back. Default to `<button>`, `<select>`, `<input>`, `<details>`, `<dialog>`, and style
them.

Then check what's left holds together:

- **Hierarchy:** one thing is clearly first on each screen. Squint at the screenshot; if
  nothing wins, sizes and weights are too even.
- **Rhythm:** spacing comes from one scale; alignment is deliberate, including the
  deliberate breaks from it.
- **Typography:** the display and text faces earn their place and are loaded (not silently
  falling back); sizes have real contrast.
- **Copy:** every sentence is something the product actually does, in the user's words.
- **States:** empty, loading, error, and long-content states are designed, not accidental.
- **Native fit:** platform conventions (iOS, Android, desktop, web) are respected where the
  user expects them and broken only on purpose.

When restyling an existing generic page rather than polishing a fresh one, fix in this
order — each step unlocks the next: font swap → palette cleanup → hover/active/focus
states → layout and spacing → replace generic components → loading/empty/error states →
typography polish. Two passes is normal; needing a third means the brief is wrong, not the
design — re-read it.

Clearing the catalog is necessary, not sufficient — a token swap (indigo to teal, Inter to
a serif, drop the emoji) clears every P0 and still leaves a forgettable template. Three
tests catch mediocrity:

1. **Justified.** Every choice serves the committed direction in the brief, not a different
   reflex.
2. **Coherent.** Type pairing, palette stance, layout, and signature detail reinforce one
   another. One committed idea, executed.
3. **Not a re-run.** It doesn't reach for the same "safe" non-default as the last pass.

## Production readiness

The polished design still has to work. Before calling it done:

- **Responsive:** phone, tablet, desktop; no horizontal scroll; wide content scrolls in its
  own container.
- **Dark and light:** both are designed, not one auto-inverted from the other (the `tailwind`
  skill covers tokens for this).
- **Accessibility:** run the `accessibility` skill's audit — contrast, focus order, labels,
  `prefers-reduced-motion` for anything that moves, real `<button>`/`<a>` elements.
- **Performance:** images sized and compressed, videos with poster frames and lazy loading,
  fonts subsetted or limited to two families, no shader running on a page that's mostly text.
- **Verified in a browser, not inferred from the code:** screenshot the final state at every
  breakpoint and look at it. "Should look right" is not done.

## Voice pass

The last pass is over the words, not the pixels. Page copy is prose the user publishes under
their name, and a design that reads in the model's default register is a tell as sure as a
purple gradient. Run the `writing:voice-profile` skill over every user-visible string —
headlines, ledes, button labels, empty states, error messages, footer lines — before calling
the page done:

- **Profile found** (`$WRITING_VOICE_PROFILE`, `~/.claude/voice_profile.md`, or a project
  profile): apply it in APPLY mode. Pick the register from its dial that fits the page's job
  — a landing page and a settings screen sit at different points — and rewrite the copy in
  that register. Run its `voice_audit.py` over the extracted strings for banned words.
- **No profile:** the skill's DEFAULT mode still applies — the baseline expository rules,
  plus the `writing:humanizer` pass for generic AI tells (em-dashes, rule of three, "seamless",
  "unlock", "elevate").

Keep the copy rules from anti-slop.md in force while rewriting: one job per string, buttons
say what happens, errors say how to exit, no invented proof. The voice pass changes *how* it
sounds, never *what* it claims.

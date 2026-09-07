# Anti-slop — the defaults to refuse, and the craft floor to meet

Consolidated from the best-rated public design skills (Anthropic's `frontend-design`,
`artifact-design` and the frontend-aesthetics cookbook; `pbakaus/impeccable`,
`Nutlope/hallmark`, `emilkowalski/skills`, `Dammyjay93/interface-design`,
`s0xDk/refactoring-ui-skill`, `dominikmartn/nothing-design-skill`,
`funboy322/avoid-ai-design`, Vercel's Web Interface Guidelines) and two data sets — Adrian
Krebs's scan of 1,590 Show HN landing pages and a 3.2M-post Reddit mining of "looks
vibecoded" complaints. Percentages below are Krebs's frequencies.

Two anchors before the catalog:

- **A tell is a default reached for without reason, not a pattern that appears.** A model
  "does not choose indigo; indigo is the average." Read every item as "no one chose this,"
  and every fix as "choose." One gradient tied to the brand is not slop; a minimal page
  executed with precision is not timid. If unsure whether something is a tell or a
  decision, treat it as a decision.
- **The brief wins.** Where the user pinned a direction — even one on this list — follow it
  exactly. Redirecting a clear brief toward your own taste is failure. This list applies
  only where the brief leaves an axis free.

## The bar

> Approach this as the design lead at a design studio known for giving every client a
> distinct visual identity that is not mistaken for anyone else's. This client has already
> rejected proposals that felt cliché or templated, and is paying for a distinctive point of
> view. — Anthropic, `frontend-design`

> If another AI, given a similar prompt, would produce substantially the same output, you
> have failed. — `interface-design`

> Most AI-generated UIs are visually distinct but structurally identical: hero → three
> features → CTA → footer. Structural sameness is the AI fingerprint, not visual sameness.
> — `hallmark`

## Never by default

Ranked by who notices. **P0**: a layperson sees it's AI-made. **P1**: a designer or
developer sees it. **P2**: craft gaps.

| Sev | Tell | Instead |
|-----|------|---------|
| P0 | **Generic typeface**: Inter, Roboto, Arial, Open Sans, Lato, Poppins, Montserrat, DM Sans, system-ui — *and the second-order set* reached for to look non-generic: Space Grotesk, Geist, Instrument Serif, Fraunces, Syne, Playfair (15.8%) | Choose deliberately for this subject; never ship the font the last three projects shipped; state the choice before coding |
| P0 | **Purple/violet→blue or cyan→magenta gradient** (28% gradients, 10.7% purple CTAs; `#6366f1 #7c3aed #8b5cf6 #a855f7`), including `background-clip: text` headlines | One flat, confident colour; a gradient only when tied to the brand, two stops max — "the third stop is vanity" |
| P0 | **Untouched component-library theme** (default shadcn `slate`, `--radius: 0.5rem`, `rounded-lg border bg-card shadow-sm` trio) — 23.5% | Edit the primitives before building; the radius is a fingerprint |
| P0 | **Centred-everything hero**: `100vh`, eyebrow + title + lede + CTA stacked on one centred axis (23.5%) | At most two centred elements; asymmetry; size the hero to what it holds |
| P0 | **Reflexive glassmorphism** (17.1%), blurred gradient blobs and glow `box-shadow`s as ambience | Blur/translucency only where layering is real; depth from weight and scale, not colour theatre |
| P0 | **Cream/beige + serif + sage/terracotta** — the "tasteful" escape hatch that became a default (`#faf8f5`, `#F4F1EA`, `#D97757`) | It's a choice only if the subject earns it; otherwise pick from the subject's own colour world |
| P1 | **3-or-6 identical cards, icon-in-a-rounded-square above a heading** (20.1%) — "the universal AI feature-card template" | A different macrostructure: alternating rows, a single column, a table, a specimen, a marquee — never the same one twice in a project |
| P1 | **Coloured left/side accent border on cards** (13%) — "as reliable a sign as em-dashes for text" | Reserve for one semantic role, or drop it |
| P1 | **Tracked ALL-CAPS eyebrow/kicker above every heading** (10.5%), `01 · THE TOUR` beside it, numbered `01/02/03` markers on non-sequences (9.4%) | Structural devices encode information; numbering only for real sequences; the eyebrow is a ban, not a default |
| P1 | **Same radius, same shadow, same padding on every surface**; card-in-card; containers nested 3 deep | Radius and elevation express hierarchy (card > button > input); nest at most 2 levels; "not everything is a card" |
| P1 | **Template chrome**: wordmark-left + 4 links + button-right nav with hairline; four-column Product/Company/Resources/Legal footer; fake browser bars with traffic lights, fake phone frames, fake terminals | Chrome shaped by the product; two footer columns and a line is often enough; never re-draw UI that already exists in the user's environment |
| P1 | **Invented proof**: stat strips ("10× faster", "trusted by 50,000+ teams"), testimonials from Jane Doe at Acme, logo walls (12.2%) | Real numbers or cut the section — "stat-led structures are slop the moment their stats become decorative" |
| P1 | **Filler copy**: streamline, empower, supercharge, seamless, effortless, unleash, world-class, "Elevate your workflow"; a `→` glued to every CTA; a single italic/coloured emphasis word in an upright headline | Say what the product does in the user's words; a real button doesn't need an arrow; emphasis from weight or an underline |
| P1 | **Emoji as icons** (✨🚀⚡🔥🎯✅), two icon libraries mixed, `Sparkles` for "AI", blinking status dots | One icon family, or type only |
| P1 | **Dead states**: no hover/focus-visible/active; happy path only, no empty/loading/error/long-content | Every state designed — "the fastest tell of unfinished UI" |
| P2 | **Fade-and-slide-up on every section, hover transition on every card**, `transition: all`, bounce/elastic easing | One orchestrated moment; transform + opacity only; see Motion |
| P2 | **Ad-hoc values**: `padding: 17px`, `#3B82F6` inline, `lighten(5%)` hover, pure `#000`/`#fff`, zero-chroma greys, near-duplicate neutrals | Everything from a scale and a token; tint neutrals toward the accent hue |
| P1 | **Fake product UI built from styled divs in the hero** — a fake task list, fake terminal, fake dashboard | Called the #1 tell by two independent sources. Show the real product (a screenshot, a live embed) or type-led hero |
| P1 | **Performative-craft chrome**: `V0.6`/`BETA` labels in the hero, `01 / 4` tile pagination, rotated vertical text, crosshair/hairline grid decoration, weather/locale strips (`LIS 14:23 · 18°C`), photo-credit captions as decoration (`Plate 03`), "Quietly in use at" / "From the field" labels, live counters ("412 of 800 reserved"), `BRAND. MOTION. SPATIAL.` text strips, "Scroll to explore" cues, decorative status dots | Delete. "If the user can count, they don't need the label"; "if they haven't scrolled yet they're looking at the hero — they know what scroll is" |
| P2 | **Hand-drawn inline SVG illustration** as a stand-in for real assets | Real imagery (see define.md), or no illustration at all |
| P2 | **Em-dashes and middle-dot chains in copy** (`A · B · C`, `WORD — fragment`) | Zero em-dashes in user-visible text — phrased as binary because "use sparingly" gets ignored; the middle dot at most once per line |

Cleared by the data — don't chase these: dark mode itself (only unprompted glow is the
tell), bento grids (0.1% of complaints, actively defended), Tailwind/shadcn as tools
("defaults are the tell, not the tools"), spacing (a soft signal — never lead an audit
with it).

## Typography

- One family or two; if two, make them clearly distinct (display + mono, serif + geometric
  sans). Never more than three; the outlier appears in ≤2 places.
- **Serif is not automatically "premium" or "editorial".** "Creative brief = serif" is the
  most-tested tell in production rounds; sans display faces are the default for the same
  reason black is in fashion. Reach for serif when the subject earns it. Emphasis inside a
  headline uses italic or bold of the *same* family — never a serif word dropped into a
  sans headline.
- Use extremes: weight 200 next to 800 reads as intentional, 400 next to 600 reads as a
  default. Size jumps of 2.5–3×, not 1.5×; heading:body below 2× is a flagged finding.
- Hierarchy from weight and colour before size: `REVENUE` 11px/500/muted/tracked ·
  `$48,200` 28px/600/primary/tabular-nums · `↑12%` 12px/500/success. Three text colours,
  maximum. Nothing below 400 in UI — de-emphasise with colour or size, not weight.
- Measure 45–75ch (`max-width: 65ch`); body 16px ideal, never under 14; line-height
  1.5–1.7 body, 1.0–1.2 display; body letter-spacing ≤0.05em. Serif body gets slightly more
  line-height and can run slightly longer.
- Type from a fixed scale (`12 14 16 18 20 24 30 36 48 60 72`), `px`/`rem` only.
- Load the face and verify it loaded; a silent fallback to the system font is the worst
  of both worlds.
- Curly quotes, `…` not `...`, tabular numerals for anything compared, non-breaking space
  between number and unit.

## Colour

- 3–5 colours total. Paper + ink + a 5–9 step neutral ramp + **one accent** covering ≤5–10%
  of any viewport. A second accent needs a job (destructive, success).
- Choose neutrals, don't default to them: a grey with a slight hue bias toward the accent
  reads as chosen; `oklch` chroma ≥0.005 on every neutral. No pure black/white as base.
- Dominant colours with sharp accents beat evenly-distributed timid palettes. Draw from the
  subject's world — the materials, the place, the era — not from a colour picker.
- Token by intent: destructive → `action.destructive`, never the primary; secondary
  buttons are neutral (outline/transparent), never a second coloured fill. A blue "Delete"
  is a bug.
- Dark mode is designed, not inverted: paper L 12–18%, ink L 92–96%, higher surfaces
  *lighter* (~3% per level), body weight reduced ~50 units, same hue in both modes.
- Never generate shades at runtime; write the ramp down.

## Layout and structure

- Design plan first: 4–6 named hex values, typefaces with roles, a layout concept in one
  sentence plus an ASCII wireframe, alignment guidance, principles. Then review it against
  the brief: anything that reads as the default for "any similar page" gets revised.
- Pick the whole-page shape deliberately (long document, workbench, manifesto,
  photographic, specimen, catalogue, index-first, quote-led, conversational…) and don't
  repeat the last one in this project.
- Break the pattern in exactly one place per screen. "This single break IS the design.
  Without it: sterile grid. With more than one: chaos."
- Mechanical caps that are easy to check: eyebrows ≤ ⌈sections ÷ 3⌉ (grep `uppercase
  tracking`; over the cap → delete, don't restyle); no more than two consecutive
  image+text zigzag sections; a page with 8 sections uses ≥4 layout families; a bento
  grid has exactly as many cells as there is content; hero headline ≤2 lines, lede ≤20
  words, ≤4 text elements (no trust strip, pricing teaser, or avatar row in the hero).
- Locks across the whole page: one CTA label per intent ("Get in touch" / "Contact us" /
  "Let's talk" is one intent — pick one), one radius scale (round buttons in a square
  layout is broken), one palette (a warm-grey site doesn't get a blue CTA in section 7).
- Spacing carries meaning: 4–8px "belong together", 16 same group, 32–48 new group, 64–96
  new context. Always more space around a group than within it. If you need a divider,
  the spacing contrast is probably wrong. Container ladder, prefer the top: spacing alone
  → one divider → subtle border → surface card. Never box the most important element.
- Fixed spacing scale with adjacent steps ≥25% apart (`4 8 12 16 24 32 48 64 96 128 …`);
  layout siblings with flex/grid `gap`, not per-element margins.
- Width is a tool, not a constant: not every section in `container mx-auto px-4`.
  Proportions speak — a 280px sidebar says "navigation serves content"; 360px says
  "peers".
- Show the page at rest: everything meant to be read is visible on load, never parked at
  `opacity: 0` waiting for an observer.
- Nested radii concentric (`outer = inner + padding`); cards top out at 12–16px, pills for
  tags and buttons only. Shadows layered (ambient + direct) and tinted toward the surface
  hue, never stacked defaults, never hairline border *and* wide shadow on one element.
- Start too airy and remove space; work in greyscale first; shrink the canvas to ~400px
  early — mobile forces the hierarchy decisions.

## Motion

- Decide by frequency, not taste: 100+ times a day (shortcuts, command palette) → no
  animation, ever; tens of times a day → minimal; occasional (modal, drawer, toast) →
  standard; rare (onboarding, celebration) → delight. Never animate keyboard-initiated
  actions.
- One orchestrated moment — a page-load sequence with staggered reveals (`animation-delay`,
  total stagger ≤500ms) — beats scattered micro-interactions.
- `transform` + `opacity` only; never `width/height/top/left/margin/padding`; never
  `transition: all`; CSS transitions (interruptible) over keyframes for state changes.
- Never `ease-in` on UI. Built-in easings are too weak: `--ease-out: cubic-bezier(0.16, 1,
  0.3, 1)`, `--ease-drawer: cubic-bezier(0.32, 0.72, 0, 1)`. No bounce/elastic on
  interface elements.
- Durations: press 100–160ms, tooltip 125–200ms, dropdown 150–250ms, modal/drawer
  200–500ms; UI motion stays under 300ms; exits ~75% of the enter.
- Enter from `scale(0.96)` + `opacity: 0`, never `scale(0)`; popovers scale from the
  trigger (origin-aware), modals from centre; button press `scale(0.97)` on `:active`.
- Interactions increase contrast (`:hover`/`:active`/`:focus` more contrast than rest);
  focus rings don't fade in; `prefers-reduced-motion` respected.
- No more than three distinct animation primitives per page. Never by default: scroll
  reveals on body text ("reading is not a cinematic experience"), background gradient
  shifts, cursor followers, section-by-section fade-up stagger, tab content sliding
  sideways (crossfade only), parallax, infinite loops.

## The craft floor

- **Theme the surfaces you didn't draw**: text selection, caret, scrollbars, focus rings,
  underline offset, `color-scheme`, `theme-color`. "The cheapest signal that a page was
  built rather than assembled, and the one models skip most reliably."
- Every state: hover, focus-visible, active, disabled, loading, error, empty, sparse,
  dense, overflow. Skeletons mirror final content exactly.
- Real elements: `<button>`, `<a href>`, `<select>`, `<details>`, `<dialog>`; a hand-rolled
  control is "both slop and a real bug" unless it beats native on a named axis.
- Contrast 4.5:1 body / 3:1 large; touch targets ≥44px even at dense density; large text
  for WCAG is 24px regular or 18.66px bold, not 18px.
- Optical alignment beats geometric (±1px); widows and orphans handled.
- Test the hero at 1280×800 as well as 1440×900: display line-height 1.0–1.1, lede ≤2
  lines (~60ch).
- Watch for CSS that cancels itself out (a `.section` rule and a `.cta` rule fighting
  over margin).

## Copy

- Words are design content, not decoration. Each element does exactly one job.
- Buttons say what happens: "Save API key", not "Continue" or "Submit". "Publish" produces
  "Published."
- Errors don't apologise and are never vague; they say how to exit. Empty screens invite
  an action.
- Speak the user's language: they manage notifications, not webhook config.
- Fold labels into values ("12 left in stock", not "In stock: 12"); labels are a last
  resort.
- Ban vague design vocabulary in your own reasoning and reviews: "clean", "modern",
  "sleek", "elegant", "premium", "seamless", "intuitive" without specifics. A decision
  reads like: "64px section gaps to create reading pauses — accepts longer scroll depth in
  exchange for the eye resting between ideas." Every principle names a plausible rejected
  alternative, and at least one is a restraint — something comparable sites do that this
  design deliberately doesn't.

## If you can't render

Code shows half of it; pixels show the rest. Palette dominance, spacing rhythm,
hierarchy, and motion cannot be judged from source. When you cannot screenshot, say which
findings are code-certain and which are inferred — never present an inferred one as seen.

## Self-check before showing work

Score 1–5 on **Philosophy** (one committed idea), **Hierarchy** (squint: one thing wins),
**Execution** (scale, tokens, states, loaded fonts), **Specificity** (strip the product
name — can someone tell what it's for?), **Restraint** (one accessory removed), **Variety**
(not the last pass's choices). Anything under 3 triggers a revision before the screenshot
goes to the critic. Then the three tests from deliver.md: justified, coherent, not a re-run.

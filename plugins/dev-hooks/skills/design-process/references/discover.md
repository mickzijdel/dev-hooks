# Discover — go broad before going deep

The hardest part of the design process is looking at a blank screen with infinite
possibilities. The best way to tackle that moment is to start by going broad before going
deep. AI is an excellent tool to explore a wide variety of potential directions.

Models tend to overrely on familiar patterns and make conservative choices. To explore the
full potential design space, we want to coax a model to do the opposite: be bold, be varied,
and take risks. Below are two ways to push it out of its comfort zone.

## Technique 1: Seed the design from outside the model

The idea here is to get the model to find a new source of inspiration for designs, rather
than relying on the defaults it learned from training. Prompted plainly ("Build me a landing
page for my productivity app"), almost every run produces a purplish gradient, text on the
left, graphic on the right, and the exact same structure. It looks like every AI-designed
website ever.

Just asking for variety doesn't work. "Give me something totally unique. Make every design
decision completely at random" yields results that are different from the default but still
not varied: the same color scheme, structure, even the same awkward metaphors. The model is
predicting tokens that *sound* random but aren't *actually* random.

**The problem is that the model can't inherently act randomly.** It can only predict the
most likely token. If we want variety, we have to bring it from outside the model. One
technique for this is String Seed of Thought, published by Sakana AI
(<https://pub.sakana.ai/ssot/>). We make the AI generate a random string and use it as
design inspiration. That way, the model is truly making different decisions each time.

The procedure, as a prompt (swap in what you're building):

> I want you to build me a landing page for my productivity app.
>
> Follow this procedure:
>
> 1. Generate a long, random alphanumeric string using a shell script.
> 2. Define the creative direction (color scheme, layout, typography, etc.) based on the
>    string. Look beyond the surface for subpatterns, special numbers, anything that
>    inspires you.
> 3. Use your judgment to bring this direction to life and make it look great.
>
> Don't reveal the string in the design. It's only for your inspiration.

Suddenly the outputs are much more varied: different color schemes, fonts, and new ideas.
These designs are one-of-a-kind; no two runs ever produce the same result.

Running this yourself (as the agent):

```bash
# a genuinely random seed — never invent one in your head (a made-up string is the
# model's most likely string, which defeats the point)
openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 48; echo
```

Extract maximum randomness by using **all** of the string: split it into segments and let
each segment drive one decision — palette, type pairing, layout stance, motion, signature
element — via whatever mapping you like (character sums mod the number of options, rolling
hash, patterns you notice). The point of segments is that no two decisions are coupled, so
the combination is genuinely new. (Sakana's paper notes the technique loses power on small
models and is only for tasks with many valid answers — design qualifies.)

Write the creative direction the string inspires into the design brief **before** any code
(see the brief template below). Generate several seeds → several briefs → several throwaway
variants when the user wants a spread to pick from; each variant lives in its own file or
worktree so they never blend into one average.

**Rotate across runs.** Models converge on the same "tasteful" non-defaults just as reliably
as on the defaults — Space Grotesk, a slate palette, one stock gradient. A second-order
default is still a default. If the last pass in this repo was warm-editorial, this one
should not be; check the previous brief (or `git log` for earlier design work) and steer
away from it.

## Technique 2: Get specific and wild

Another approach to giving a model a strong push is to get more specific and wild with your
prompts. This gives the model a clear vision to base its decisions on, rather than letting
it make them up on the fly. The best way to find a unique idea is by bringing your own taste
into the equation. You first imagine the inspiration — a video game, an interior design
trend, an art installation — and describe how you'd like that inspiration to influence the
outputs. Examples:

> "Build me a landing page for my productivity app, with a bold pixel art theme and stunning
> graphics. Each section should feel like a still from a video game, yet somehow it should
> all function as a landing page."

> "Build me a landing page for my productivity app, set in an isometric living 3D city,
> where different features are somehow represented by neighborhoods or buildings."

> "Build me a landing page for my productivity app, with a radically asymmetric layout,
> dissonant colors and typography, and uncomfortable negative space. Break all the rules but
> still make it look good."

Of course, the hard part is coming up with original ideas to ask for. AI can help with this
too, but if you simply ask it for ideas, you'll get the same average ones everyone else gets.
Here's a system to find unique prompt ideas with AI — three prompts, in order, with the
user's taste applied in the middle:

**1. Go broad:**

> I want to come up with a bold, unique design language for my product. Can you list as many
> ideas as you can, with short, high-level descriptions? Go broad, not deep.

**2. Sharpen one with the user's taste.** The user picks a direction and reacts to it; the
reaction is the valuable part. Example:

> Industrial Control Panel:
>
> - I'm imagining something tactile. Clicky, satisfying buttons, nice sounds.
> - Initially I pictured something cartoony or skeuomorphic, but this feels tacky to me.
>   Avoid that.
> - Instead, want consistent components and little touches that land this look without
>   going overboard.
> - Gray gradients would look boring. Need more texture. Maybe we can incorporate some
>   color, while retaining the control panel feel?
>
> Can you sharpen this one based on my tastes?

**3. Turn it into a build prompt:**

> Can you write a concise prompt that an AI agent could use to build an initial POC page
> with this?

If you just paste AI-generated ideas back into AI, it's hard to get something unique. After
all, anyone else could have done the same thing. However, when you actively steer the design
direction, you end up with something only you could have created. When the user hasn't
supplied taste, run step 1, show them the list, and ask which ones pull at them — don't pick
for them silently.

Don't be afraid to try ideas that sound terrible. If you find yourself thinking, "There's no
way this will work," you're on the right track. Often, your agent will surprise you, and
you'll realize you were underestimating it. If not, just throw away those results and try
something else. But save the prompts that *don't* work, and test them again when newer
models come out. That way, you'll know you're taking full advantage of what the latest
models can do.

## Technique 3: Mock it up as an image first

Text briefs (Techniques 1 and 2) still route every layout and spacing decision through a
model that predicts tokens one at a time — it can describe a composition accurately without
ever "seeing" whether it holds together. An image model doesn't have that problem for the
same reason a human designer handing off a comp doesn't: the whole layout exists at once, so
proportions, whitespace, and visual hierarchy get judged as a picture, not assembled from a
list of properties.

Use this when the direction is more about *composition and hierarchy* than the seeded
inspiration Techniques 1–2 produce, or when a stakeholder needs to react to something visual
before code exists:

1. Check the imagery route settled at the gate (step 1 of SKILL.md) actually produces
   full-screen UI compositions, not just isolated hero/feature art — a photo-generation model
   is the wrong tool here; an image model asked explicitly for "a UI mockup / wireframe /
   screen design" is the right one.
2. Prompt the image model with the same inputs a brief would carry: product, audience, the
   one action the screen exists for, and the direction from Technique 1 or 2. Ask for the
   specific screen (not a moodboard) at the target aspect ratio.
3. Generate a small spread (3–5), not one — the first image is as much a default-attractor
   as the first text completion. Pick the strongest, or let the user pick.
4. Feed the chosen image to the coding agent as a **reference to build from**, not to trace
   pixel-for-pixel: name what to keep exact (layout proportions, spacing rhythm, the
   signature element) versus what to adapt (real copy, actual data, responsive behavior the
   static image can't show). Still write the design brief (below) alongside it — the image
   captures composition, the brief captures the decisions a screenshot can't (why this
   direction, what it must differ from, the states the image doesn't show).
5. Run the critic loop (Define) against the *built* result as usual, not against the mockup
   image — the mockup seeded the direction, it isn't the bar.

An image mockup replaces the *layout* half of a text brief; it doesn't replace the written
brief's job of recording intent, or the critic loop's job of checking the built page.

## The design brief

Every direction — seeded or hand-picked — gets written down before code. A brief is the
single place a critic, a second agent, or the user can check the work against, and it stops
the direction drifting back to the default halfway through the build. Keep it short and
concrete:

```markdown
# Design brief: <project / page>

**Direction (one line):** <the aesthetic in a sentence someone could sketch from>
**Feeling it should create:** <the emotional response — calm, urgent, playful, precise…>
**Inspiration:** <the game / movement / object / seed-derived idea, and what to borrow from it>

**Typography:** <display face + text face, and why; size/weight contrast>
**Color:** <palette with roles — ground, ink, one accent; how it's used sparingly>
**Layout & composition:** <grid or deliberate break from it; density; asymmetry; whitespace>
**Motion & texture:** <what moves, what doesn't; texture/grain/imagery instead of gradients>
**Signature element:** <the one memorable thing a visitor would describe to a friend>

**Not this:** <the default patterns this direction must avoid — hero-split, purple gradient,
glow cards, three-column feature grid, generic sans…>
**Differs from the last pass on:** <axes — page shape, type, palette stance, motion — or
"first design in this repo">
```

State the pick in plain text before writing code — "Macrostructure: X. Type: Y. Differs
from the last on: Z." Deciding on the page, not in your head, is what prevents the
default-attractor sameness. Then stamp it into the artifact so the *next* run can read it:

```css
/* design-process · shape: long-document · type: Newsreader + IBM Plex Mono · palette: olive/brick/paper · differs: previous was centred hero + sans */
```

A stamp (or the saved brief) is the only durable mechanism for cross-run variety; the
model cannot "remember to vary" on its own.

Save it next to the work (e.g. `design/brief.md` or a comment block at the top of the page)
and treat it as the spec for Define and Deliver.

### Review the plan against the brief before building

Anthropic's own frontend-design skill makes this a mandatory second pass, and it is the
cheapest slop filter there is:

> Then review that plan against the brief before building: if any part of it reads like
> the generic default you would produce for any similar page (work through a similar prompt
> to see if you arrive somewhere similar) rather than a choice made for this specific brief
> — revise that part, say what you changed and why. Only after you've confirmed the
> relative uniqueness of your design plan should you start to write the code.

Two more sequencing rules from well-rated guides:

- **Don't ask for style and structure in the same prompt.** Settle the direction (this
  file), then the layout, then the build — a prompt that asks for both at once gets the
  default for both.
- **Ground in the subject.** "The subject's industry, subject matter, materials, and
  vernacular are where distinctive visual choices come from — a design for a toy for girls
  aged 8–11 will be very aesthetically different from a dashboard for financial analysts."
  If the brief doesn't say what the product is, find out before designing.

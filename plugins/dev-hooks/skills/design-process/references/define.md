# Define — give the design an identity

No matter how we prompt, our initial AI-generated designs will usually still feel generic.
Seeded designs have promise, but they still rely heavily on the same stale patterns: text
on the left with a CTA button below, nav bar up top, graphic on the right.

The goal of this stage is to give each design an individual personality through distinct
design choices. Three techniques, in the order to reach for them.

## 1. The design critic loop

We need to iterate on our designs to improve them. But simply asking the coding agent to
look at the design and improve it won't work, because the agent isn't objective: it reviews
its own code, past decisions, and previous rationale. AI can't easily zoom out, look at the
big picture, and "think different."

To solve this, instead of letting the coding agent decide when the design is good enough,
have it ask *another* agent — a "design critic." The critic's job is to look at screenshots
of the current design and provide feedback. It doesn't care how the current design is
implemented or how much effort went into it, only if it actually hits the quality bar.

This approach has an extra benefit: we can use a big, expensive model for the critic without
breaking the bank, because we'll only use it for executive decisions. A cheap, fast model can
do the grunt work, while the strong critic model provides taste. In practice the critic
accounts for under 10% of output tokens; asking the big model to redesign the page directly
would cost twice as much and take much longer.

### The loop (verbatim, for the implementing agent)

> I want you to improve this design. To figure out what to focus on, use a <strongest
> available model> subagent as a design critic.
>
> Follow this procedure at each iteration:
>
> - Capture a screenshot of the current design
> - Invoke the critic in a fresh context, with just the screenshot, not the code,
>   implementation details, or earlier iterations/critiques
> - Ask it to evaluate the aesthetic that the design is going for, imagine how a top design
>   studio would execute this aesthetic, then outline the biggest gaps
> - Lastly, it should provide a score out of 10 indicating how close the current design is
>   to that studio-level quality bar
>
> Provide this guidance to the critic in its prompt:
>
> - It should think high-level about the overall structure and composition as well as look
>   at the fine details
> - It should watch out for patterns that feel overdone, excessive, or otherwise obviously
>   AI-generated, and penalize them
> - It should provide tight, specific feedback, not vague prose
> - It should be bold and opinionated, not rely on what's safe or easy
>
> Your work is only complete when the critic independently deems it 9/10 or higher. Do not
> put that criterion in the critic prompt; keep it objective in its scoring. Use the same
> critic prompt each time.

Instead of the same cookie-cutter layout over and over, each design ends up with its own
identity — but still maintains its original high-level aesthetic.

### Running it in Claude Code

- **Screenshot:** the `playwright-cli` skill, or `vischeck:verify` where installed. Capture
  the full page at desktop width (1440) and at a phone width (390); hand the critic both.
  Save screenshots to files and pass paths — raw image payloads in tool results flood the
  context. If the dev server hot-reloads, wait for the reload to finish before capturing,
  or you screenshot the previous version with a plausible-looking result.
- **Fresh context:** dispatch the critic with the `Agent` tool, `model: "opus"` (or the
  strongest available), a prompt that contains **only** the critic template from
  [critic-prompt.md](critic-prompt.md), the intended aesthetic in one line, and the
  screenshot path(s). No code, no brief history, no previous critiques, no target score.
- **Same prompt every round.** Rewriting the critic prompt between rounds moves the
  goalposts and makes scores incomparable. You cannot alter the judge's prompt to relax
  the condition.
- **Fix the biggest gap first,** not everything the critic listed. Re-screenshot, re-critique.
- **One owner per pass.** Coupled visual concerns (type + spacing + hierarchy; colour +
  imagery) get worse when several agents edit them in parallel — a published run measured
  parallel fan-out moving the score +0.46 while *adding* defects, and a single sequential
  owner moving it +1.00 while cutting them by more than half. Iterate sequentially.
- **Pair the judge with a deterministic gate.** Contrast ratios, a Lighthouse score, the
  `accessibility` audit, a pixel diff against the last round. "It looks flat" is not
  actionable; a measured number is, and it can't be talked up.

### Hard exits — a score threshold is not a stop condition

No published critic loop has ever terminated on its own score gate: the article's own
24-hour run never reached 9/10, and a well-known game-rendering run went 3.59 → 4.14 →
4.05 → 5.05 before being stopped by hand. Scores out of 10 drift and oscillate. So the
9/10 goal above is the *aim*; the loop actually stops on the first of:

1. **The critic's bar is met** (9+, or ours wins the blind comparison).
2. **A round fixes nothing** — the score doesn't move, or the same gap is reported twice.
   That is a signal the brief or the inputs are the problem, not the effort. Stop, show the
   user the screenshot and the last critique, ask which way to push.
3. **The budget is spent** — the round count or token share agreed with the user up front
   (default: two rounds, then ask before authorising more).

**Prefer a blind comparison when a real reference exists.** A score asks the critic to
grade against words; a bar makes it compare against something that already exists and is
undeniably good. Give it four professional screenshots plus ours with labels stripped and
ask which is better and what the single biggest remaining gap is. The reference must be
*named, fetchable, and comparable* — if the critic can't see the real thing, it hallucinates
the comparison and approves everything.

### Tips — the way you set these loops up matters a lot

- **Make sure the criteria for the critic are as clear and objective as possible.**
  - Bad: "Judge if our design looks beautiful, not AI-generated." This is too subjective, and
    the results will vary wildly from run to run.
  - OK: "Review the aesthetic we're going for, visualize how a top design studio would
    execute it, then judge our design's quality against that bar." The prompt is still
    mushy, but it provides a consistent framework and quality bar.
  - Great: "Here are 5 designs: 4 professional examples and 1 screenshot of our product.
    Rank them by polish and taste level." This instruction is concrete and objective, and
    gives a visual baseline for judgment.
- **Provide example images to demonstrate the target quality bar.** You can use comparable
  screenshots or designs you like, or even AI-generated concept art. Instruct the critic to
  treat these as a baseline or a moodboard, not a target. You don't want it to copy other
  designs outright.
- **Set the stopping criteria carefully.** Otherwise, the critic may never consider the
  design good enough, and your agent will helplessly burn tokens trying to please it. Prompt
  it to do one or two iterations first, and see if it's converging before adding more. If two
  consecutive rounds don't move the score, stop and show the user where it stands.
- **Choose the right model for each job.** Consider bigger models for the critic role, since
  more parameters generally translate to better design sense and a wider distribution of
  ideas. Small models can be effective as the implementer, but don't go too small. You still
  need a model that's capable of executing a design direction well.

## 2. Real images instead of code-drawn decoration

Coding agents love to write code, but they usually don't incorporate images. Instead, they
tend to use the easy code-based alternatives: gradients, shapes, and basic patterns. Those
are all strong giveaways of an AI-generated design.

Some agents have image tools built in, but they underutilize them. Others don't have image
tools out of the box but can easily use the OpenAI or Gemini APIs to generate images with an
API key.

> The design is pretty plain. Add more personality using image generation. Consider shaders
> or 3D effects in combination with images to create more interesting visuals.
>
> For image generation, use this <provider> API key (only use it locally, do not store it in
> the code or product): <key>
>
> Verify that your work looks right frame-by-frame in the browser.

Images and effects like these can quickly add a lot of personality and make a design less
obviously AI-generated, since they demonstrate more than surface-level effort.

Depending on your setup, there are different ways to connect your agent to image generation:

- **If the agent has built-in image generation** (Codex, Antigravity, Grok Build): tell it to
  use its built-in image generation. The agent already knows how to do this but rarely does
  so until instructed.
- **If you use Claude Code but also have a ChatGPT subscription:** "Use the Codex CLI to
  generate images. Help me install it if it isn't already present. Make sure it's billing my
  subscription, not an API key."
- **If you only use Claude, or any other tool:** the simplest path is to give the agent an
  OpenAI or Gemini API key to generate images. Create a separate API key with a tight spend
  limit, just for the agent. That way, costs are controlled even if the key gets out or the
  agent misuses it, and it can be revoked without disrupting other work.
  - If keys get pasted into chats frequently, put them in a file instead: "Create a
    gitignored file called `.env.agents`, store this API key in it, and note to yourself in
    AGENTS.md/CLAUDE.md that these keys are for you to use during development (but must not
    ship with the product)." In repos that use fnox, store the reference there instead (see
    the `env-to-fnox` skill); never commit the value.

**As the agent:** read the key from the env file or fnox, call the API from a local script,
save the generated assets into the project's asset directory, and never echo the key or
write it into source. Generated assets are checked in like any other image; the key is not.

Practical notes:

- fal.ai ships an official MCP server that covers image *and* video models with one key:
  `claude mcp add --transport http fal-ai https://mcp.fal.ai/mcp --header "Authorization: Bearer $FAL_KEY"`
  (tools include `search_models`, `recommend_model`, `run_model`).
- For UI assets you usually want a **transparent background**. OpenAI's image models support
  `background: transparent` (PNG/WebP only, not JPEG); Gemini's image models have no
  transparent option and watermark every output — matte the background out afterwards or
  pick the other provider.
- Generate at the size and aspect the layout needs (hero art is rarely square); compress
  before committing; give every image real `alt` text or `alt=""` if decorative.
- Don't hand-draw imagery as inline SVG blobs as a substitute — that is the code-shaped
  decoration this step exists to replace.

## 3. Video models for motion and transitions

Video generation models are incredibly powerful, but most people think of them as tools for
generating ads or novelty clips. They can work wonders for everyday design work too. The best
models change frequently, so an aggregator platform like fal.ai lets the agent evaluate
different options and choose the best one with a single API key.

Two ways to use video models in designs:

### Looping ambient animations (chroma key / matting)

The trick is to generate a looping clip with a solid color background, then either chroma
key it out (like a green screen) or, in more complex cases, use a video matting model to
remove the background. This gives you an animation you can layer anywhere in the UI without
it looking like a video.

> Can you replace the image on this page with a looping video clip that does something more
> interesting? Have the <hero object> splinter apart and slowly spin around. It should have
> awesome glassy effects that refract the page background and cast shadows and light around
> it.
>
> To get convincing glass refraction effects, render the video of the glass over the page
> background colors first (so it bakes in the refraction effects), then remove the background
> with a video matting model.
>
> Use this fal.ai API key: <key>
>
> Find appropriate recent models for video generation and background removal.

This is a much richer effect than you can get with code: interesting caustic reflections,
glassy refraction effects, and complex physical motion.

### Keyframe-interpolated transitions (scroll- or gesture-scrubbed)

In addition to generating video from text, many video models can interpolate between
keyframe images. This lets you take two product stills and create a transition clip between
them. Play the clip when the user takes an action (navigating to another screen) or scrub
through it frame-by-frame in response to a gesture (scrolling or swiping).

> Build a demo page for a <product> that uses a video model to create interactive
> transitions between a couple of screens. Each screen should show the <product> in a
> different state, with vertical motion that feels appropriate for scrolling:
>
> - Initially, have the <product> floating high up in the air
> - Then have it land on the floor and pop open
> - Finally, have its contents neatly land into it from the top
>
> Generate the initial frame using your image generation skill. Then, generate a video clip
> that starts from that frame and animates to the next state. Use the final frame of that
> video to seed the next transition so that it continues seamlessly. Scrub through the
> transitions one by one as the user scrolls.
>
> Use this fal.ai API key: <key>
>
> Use a video model with strong physics and consistency.

Transitions like this scrub fluidly with the user's scrolling and make the user *want* to
keep scrolling.

### Shipping video assets (the parts the models won't tell you)

- **Get alpha straight from the matting model** rather than chroma-keying afterwards: on
  fal, `bria/video/background-removal` needs `background_color: Transparent` (the default
  is black) and emits `webm_vp9` or `mov_h265`; `fal-ai/ben/v2/video` outputs transparent
  WebM when no background colour is given. MP4 has no alpha — transparent areas turn black.
- **Two sources, HEVC first.** Safari can't play VP9 with alpha; Chrome/Firefox can't play
  HEVC-alpha. Ship both and list the `.mov` first:
  ```html
  <video playsinline muted autoplay loop>
    <source type="video/quicktime; codecs=hvc1.1.6.H120.b0" src="hero.mov">
    <source type="video/webm; codecs=vp09.00.41.08" src="hero.webm">
  </video>
  ```
  HEVC-with-alpha encodes only with Apple's hardware encoder (`hevc_videotoolbox`); for a
  smaller single-file path, stack the alpha as a second half-height layer and recomposite
  in a shader (see Jake Archibald, "Video with alpha transparency on the web", 2024).
- **Chroma key when you must:** `ffmpeg -i in.mp4 -vf "chromakey=0x00FF00:0.3:0.1,despill=green" -c:v libvpx-vp9 -pix_fmt yuva420p out.webm`.
- **Scroll-scrubbing:** prefer an **image sequence drawn to a canvas via
  `requestAnimationFrame`** (the Apple product-page technique) over seeking a `<video>`;
  a video element can't sync to rAF and seeks only to keyframes. Pure interpolation models
  (`fal-ai/rife`, `fal-ai/film`) can return PNG frames directly with `output_type: images`.
  If you must scrub video, encode with a keyframe every frame or two
  (`-g 2 -x264-params scenecut=0`) and ship MP4 as well as WebM for iOS.
- **Seamless loops:** identical first and last frames make video models generate no
  motion. Instead generate clip 1, then generate clip 2 *from* clip 1's last frame *to* its
  first frame, drop the duplicate seam frame, and concatenate.
- **Always:** a poster frame from the first keyframe, `preload="metadata"`, lazy load
  below the fold, and `prefers-reduced-motion` shows the poster only.

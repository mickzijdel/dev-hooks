---
name: popovers-tooltips
description: Use when building or fixing popovers, tooltips, dropdowns, menus, comboboxes, or any floating/overlay UI — especially when they render off-screen, get clipped, or are mis-positioned. Covers Floating UI in a Stimulus controller (Rails/Hotwire), Tippy/Flowbite/Preline, and the native Popover API.
---

# Popovers & tooltips

Use this skill to build popovers, tooltips, dropdowns and menus that stay **on-screen** and
aren't clipped.

## Core principle: Tailwind styles, it does NOT position

Tailwind has no positioning logic — it only paints. Don't hand-roll `top`/`left` math from
`getBoundingClientRect()`; you'll reinvent collision detection badly and the popover will open
off-screen. Reach for a positioner that does **collision detection** (flip + shift) and render
the floating element in the **top layer / a portal** so an ancestor's `overflow`, `transform`,
or `z-index` can't clip it.

## Why popovers go off-screen (the failure modes)

- No flip/shift fallback, so a bottom-anchored tooltip near the viewport edge overflows.
- Clipped by an ancestor with `overflow:hidden`, a `transform`, or its own stacking context.
- Positioned `absolute` inside a scrolled container, so it drifts on scroll.
- Never re-positioned on scroll/resize.

## The four things that fix it

1. `offset()` — gap from the reference.
2. `flip()` — pick the side with room.
3. `shift({ padding })` — slide along the axis to stay in the viewport.
4. `arrow()` + `autoUpdate()` — arrow placement, and re-position on scroll/resize/layout.

Plus: render in the **top layer** (native `popover`) or **portal to `<body>`** to escape
clipping.

## Primary — Floating UI + Stimulus (Rails 8 / Hotwire)

[Floating UI](https://floating-ui.com) (`@floating-ui/dom`, the framework-agnostic successor
to Popper) is the right tool in a Hotwire app: call it from a Stimulus controller. Install with
`bin/importmap pin @floating-ui/dom` (or pin it in your esbuild/jsbundling setup).

```erb
<%# Tailwind here is styling ONLY — positioning is the controller's job %>
<span data-controller="tooltip" data-tooltip-text-value="Archive this card">
  <button data-tooltip-target="trigger" class="rounded p-2 hover:bg-gray-100">Archive</button>
</span>
```

```js
// app/javascript/controllers/tooltip_controller.js
import { Controller } from "@hotwired/stimulus"
import { computePosition, offset, flip, shift, autoUpdate } from "@floating-ui/dom"

export default class extends Controller {
  static targets = ["trigger"]
  static values = { text: String }

  connect() {
    this.tip = document.createElement("div")
    this.tip.textContent = this.textValue
    this.tip.role = "tooltip"
    // Styling only. Note `w-max` + a `max-w-*` so long text wraps instead of overflowing.
    this.tip.className =
      "hidden absolute top-0 left-0 w-max max-w-xs rounded bg-gray-900 px-2 py-1 text-sm text-white shadow-lg z-50"
    document.body.appendChild(this.tip) // portal out of any clipping ancestor

    this.show = () => {
      this.tip.classList.remove("hidden")
      // autoUpdate keeps it positioned on scroll/resize; returns a cleanup fn.
      this.cleanup = autoUpdate(this.triggerTarget, this.tip, () => {
        computePosition(this.triggerTarget, this.tip, {
          placement: "top",
          middleware: [offset(6), flip(), shift({ padding: 8 })],
        }).then(({ x, y }) => {
          Object.assign(this.tip.style, { left: `${x}px`, top: `${y}px` })
        })
      })
    }
    this.hide = () => {
      this.cleanup?.() // stop the autoUpdate listeners
      this.cleanup = null
      this.tip.classList.add("hidden")
    }

    this.triggerTarget.addEventListener("mouseenter", this.show)
    this.triggerTarget.addEventListener("focus", this.show)
    this.triggerTarget.addEventListener("mouseleave", this.hide)
    this.triggerTarget.addEventListener("blur", this.hide)
  }

  disconnect() {
    // TURBO GOTCHA: the tip is portaled to <body>, OUTSIDE this element's subtree, so
    // Turbo Drive's cache/restore and Turbo 8 morph won't remove it. Clean up here or
    // you leak listeners and orphan stale tooltips across navigations.
    this.cleanup?.()
    this.tip?.remove()
    this.triggerTarget.removeEventListener("mouseenter", this.show)
    this.triggerTarget.removeEventListener("focus", this.show)
    this.triggerTarget.removeEventListener("mouseleave", this.hide)
    this.triggerTarget.removeEventListener("blur", this.hide)
  }
}
```

## Alternatives

| Option | Use when |
|--------|----------|
| [Tippy.js](https://atomiks.github.io/tippyjs/) (built on Popper) | Plain tooltips/popovers — the fastest drop-in; less code than wiring Floating UI yourself. |
| [Flowbite](https://flowbite.com) / [Preline](https://preline.co) / [daisyUI](https://daisyui.com) | You already use that Tailwind component kit — use its popover/dropdown/tooltip rather than hand-rolling. |
| Native [Popover API](https://developer.mozilla.org/docs/Web/API/Popover_API) (`popover` attr + `popovertarget`) | You want top-layer + light-dismiss for free (Baseline 2024). Pair with CSS anchor positioning for placement — but **anchor positioning is Chromium-only as of 2026**, so add a Floating UI fallback for cross-browser placement. |
| React: [Radix](https://www.radix-ui.com), [Headless UI](https://headlessui.com), [shadcn/ui](https://ui.shadcn.com) | It's a **React** app (these wrap Floating UI internally). They do **not** apply to a Hotwire/Stimulus app. |

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Hand-rolling `top`/`left` from `getBoundingClientRect()` | Use `computePosition` with `flip()` + `shift()`. |
| Tooltip clipped / hidden | Portal to `<body>` (or use the native top layer); don't fight `overflow:hidden`. |
| `flip()` only, no `shift()` | `flip()` switches sides; `shift()` slides along the axis — you need both to stay on-screen. |
| Forgetting `autoUpdate` | Position goes stale on scroll/resize. |
| Forgetting `disconnect()` cleanup under Turbo | Leaked listeners + orphaned popovers across Turbo visits. Call the `autoUpdate` cleanup and `remove()` the portaled node. |
| z-index wars | Render in the top layer / a high-z portal instead of escalating `z-index`. |

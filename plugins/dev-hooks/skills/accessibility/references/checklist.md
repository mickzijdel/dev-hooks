# WCAG 2.2 AA review checklist

Work top to bottom over the changed UI. The bundled `a11y_audit.py` covers the items marked
**[auto]**; the rest need a human (or you) looking at the rendered page.

## Text alternatives & media

- [ ] **[auto]** Every `<img>` has `alt`. Meaningful images describe meaning; decorative
      images use `alt=""`.
- [ ] Inline `<svg>` is `aria-hidden="true"` (decorative) or has `role="img"` + `<title>`.
- [ ] Icon fonts (`<i class="fa-...">`) aren't the only content of a control without a label.
- [ ] `<video>`/`<audio>` have captions / transcripts; no autoplay with sound.

## Names, roles, values

- [ ] **[auto]** Every interactive control has an accessible name (text content,
      `aria-label`, `aria-labelledby`, or associated `<label>`).
- [ ] **[auto]** Icon-only `<button>`/`<a>` have `aria-label`.
- [ ] Custom widgets expose the right `role` and state (`aria-expanded`, `aria-pressed`,
      `aria-checked`, `aria-selected`, `aria-current`).
- [ ] `aria-*` attributes are valid and reference IDs that exist (`aria-labelledby`,
      `aria-describedby`, `aria-controls`).
- [ ] No redundant/ conflicting ARIA (e.g. `role="button"` on a real `<button>`).

## Forms

- [ ] **[auto]** Every `<input>`/`<select>`/`<textarea>` (except hidden/submit/button) has a
      programmatic label — `<label for>`, wrapping `<label>`, `aria-label`, or
      `aria-labelledby`.
- [ ] `placeholder` is not used as the only label.
- [ ] Required fields use `required`/`aria-required`; errors use `aria-invalid` +
      `aria-describedby` pointing at the message, not color alone.
- [ ] Related radios/checkboxes are grouped in a `<fieldset>` with a `<legend>`.
- [ ] Inputs have an appropriate `autocomplete` token (WCAG 1.3.5).

## Keyboard & focus

- [ ] Every control is reachable and operable with Tab / Shift-Tab / Enter / Space (and
      arrow keys for composite widgets).
- [ ] Focus is always visible — no `outline: none` without a clear replacement (`:focus-visible`).
- [ ] **[auto]** No positive `tabindex` (`tabindex="1"` and up). Only `0` or `-1`.
- [ ] **[auto]** Click/key handlers live on real interactive elements, not `<div>`/`<span>`
      (or, if unavoidable, the element has `role` + `tabindex="0"` + a keydown handler).
- [ ] Focus order matches visual/reading order.
- [ ] Modals trap focus while open and restore it to the trigger on close; Escape closes.
- [ ] After async swaps (Turbo Frame/Stream, route change), focus moves sensibly and updates
      are announced via `aria-live`.
- [ ] A "skip to main content" link is the first focusable element on full pages.

## Structure & semantics

- [ ] **[auto]** `<html>` has a `lang` attribute.
- [ ] Exactly one `<h1>`; heading levels don't skip (h2 → h4) for styling reasons.
- [ ] Landmarks present: `<header>`, `<nav>`, `<main>` (one), `<footer>`.
- [ ] Lists use `<ul>/<ol>/<li>`; tabular data uses `<table>` with `<th scope>`.
- [ ] **[auto]** `<button>` inside a `<form>` has an explicit `type` (default is `submit`).

## Color, contrast, motion, zoom (WCAG 2.2)

- [ ] Text contrast ≥ 4.5:1 (≥ 3:1 for ≥ 24px or ≥ 19px bold); UI components/graphics ≥ 3:1.
- [ ] Information is never conveyed by color alone.
- [ ] Layout works at 200% zoom and 320px width (reflow) with no loss of content/function.
- [ ] `prefers-reduced-motion` is honored for non-essential animation.
- [ ] Target size ≥ 24×24px (WCAG 2.2 SC 2.5.8), or adequate spacing.
- [ ] Focus is never fully hidden behind sticky headers (WCAG 2.2 SC 2.4.11).

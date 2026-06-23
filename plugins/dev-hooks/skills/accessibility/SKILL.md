---
name: accessibility
description: Use when building or reviewing web UI — auditing or fixing accessibility (a11y) against WCAG 2.2 / ARIA. Covers semantic HTML, alt text, accessible names, labels, keyboard focus order, color contrast, and reduced motion, with Rails/Hotwire and React patterns. Pairs with the a11y-reminder hook.
---

# Accessibility

Use this skill to make web UI usable with a keyboard, a screen reader, and at any zoom or
contrast — and to audit changed frontend files against WCAG 2.2 AA before shipping.

## Core principle: a real element beats a fake one

The single highest-leverage rule: **use the native HTML element for the job.** A `<button>` is
focusable, fires on Enter/Space, announces its role, and works with assistive tech for free. A
`<div onclick>` gives you none of that and you'll reimplement all of it badly. Reach for ARIA
only to *enhance* semantics you can't get from HTML — never to fake an element that already
exists. (First rule of ARIA: don't use ARIA if a native element will do.)

```
Need…                     Use                         Not
a click action            <button>                    <div onclick> / <a> with no href
navigation to a URL       <a href>                    <button> + JS navigation
a labeled field           <label for> + <input>       a bare <input> with placeholder
a toggle                  <input type=checkbox> /     a styled <div> + aria you hand-wire
                          <button aria-pressed>
a list                    <ul>/<ol>/<li>              <div> soup
```

## Audit a change

When asked to review or before finishing UI work, audit the **changed** frontend files. Run
the bundled checker over them for the mechanical issues, then eyeball the rest of the checklist
([references/checklist.md](references/checklist.md)):

```bash
# scans HTML / ERB / JSX / TSX / Vue / Svelte and reports file:line: issue
plugins/dev-hooks/skills/accessibility/scripts/a11y_audit.py app/views/**/*.erb app/javascript/**/*.tsx
# or just the files git says changed:
git diff --name-only --diff-filter=d | grep -E '\.(html|erb|haml|slim|jsx|tsx|vue|svelte)$' | xargs a11y_audit.py
```

The checker is heuristic (regex, not a real DOM) — it catches the common, high-signal mistakes
(missing alt, unlabeled inputs, icon-only controls, clicks on non-interactive elements, missing
`lang`, positive `tabindex`). It can't judge contrast, focus order, or whether an `alt` is
*good* — do those by hand from the checklist.

## The seven things that catch most issues

1. **Every image has a text alternative.** `<img>` needs `alt`. Describe the *meaning*
   (`alt="Sales up 30% in Q3"`), not the file (`alt="chart.png"`). Decorative image → `alt=""`
   (empty, not missing) so screen readers skip it. Inline `<svg>` icons: `aria-hidden="true"`
   if decorative, or `role="img"` + `<title>` if meaningful.
2. **Every control has an accessible name.** An icon-only button (`<button>🗑</button>`) is
   announced as "button" with no name. Add `aria-label="Delete"` (or visually-hidden text).
   The name comes from contents, `aria-label`, `aria-labelledby`, or an associated `<label>`.
3. **Every form field has a programmatic label.** `<label for="email">` + `<input id="email">`,
   or wrap the input in the label. `placeholder` is **not** a label (it vanishes on input and
   often fails contrast).
4. **Everything works from the keyboard.** Tab reaches every control, Enter/Space activate it,
   focus is visible (never `outline: none` without a replacement), and focus order follows
   reading order. Don't use `tabindex` > 0. Custom widgets need the ARIA Authoring Practices
   keyboard pattern (e.g. a menu handles arrow keys + Escape).
5. **Semantic structure.** One `<h1>`, headings in order (no skipping levels for size),
   landmarks (`<header>/<nav>/<main>/<footer>`), and `<html lang="…">`.
6. **Color isn't the only signal, and contrast passes.** Text ≥ 4.5:1 (3:1 for large text),
   UI/graphics ≥ 3:1. Don't convey state with color alone — pair it with text or an icon.
7. **Respect user settings.** Honor `prefers-reduced-motion` (drop non-essential animation),
   don't disable zoom, and keep tap targets ≥ 24×24px (WCAG 2.2).

## Frameworks

**Rails / Hotwire (ERB, ViewComponent, Stimulus).** Use the form builder — `form.label
:email` + `form.email_field :email` wires `for`/`id` automatically. For icon buttons:
`button_tag aria: { label: "Delete" }`. After a Turbo Frame/Stream swap, **move focus** to the
new content (a Stimulus controller calling `element.focus()` in `connect()`), and announce
async results via an `aria-live` region so screen-reader users notice the update. Don't put
click handlers on `<div data-action="click->...">` — put them on a `<button>`.

**React / JSX.** It's `htmlFor` (not `for`), `className`, and `aria-*`/`role` stay
hyphenated. Prefer real elements over `onClick` divs. For modals/menus, use a headless library
that ships the ARIA + focus-trap (Radix, React Aria, Headless UI) rather than hand-rolling —
focus management is the part everyone gets wrong. Manage focus on route changes and after
opening/closing overlays.

See [references/common-fixes.md](references/common-fixes.md) for before/after snippets of the
issues the checker flags, and [references/checklist.md](references/checklist.md) for the full
WCAG 2.2 AA review list.

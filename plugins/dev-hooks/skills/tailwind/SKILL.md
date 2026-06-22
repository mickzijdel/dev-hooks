---
name: tailwind
description: Use when writing or fixing Tailwind CSS — in HTML, ERB/ViewComponent, JSX, Vue, or any template that carries utility classes. Covers design tokens, taming class soup, component-first extraction, dark mode, responsive layout, and accessibility. Triggers on "tailwind", "css", "styling", "dark mode", "responsive", "class soup", "@apply", "design system", or any "make this look right / fix this layout" request — even when styling isn't named explicitly, since templates almost always contain Tailwind classes.
---

# Tailwind CSS

Tailwind works well at scale only with two things in place: a **design system of consistent
tokens** and a **component-based architecture**. Most Tailwind pain — unreadable class soup,
inconsistent spacing, forgotten dark mode — traces back to missing one of them. This skill
enforces both, plus dark mode, responsive, and accessibility as defaults rather than afterthoughts.

Tailwind **styles**; it does **not** position floating UI. For dropdowns, tooltips, and popovers
that must stay on-screen, see the companion [popovers-tooltips](../popovers-tooltips/SKILL.md) skill.

## The golden rules

1. **No plain CSS.** Style through Tailwind utilities, or `@apply` inside a component layer. Don't hand-write raw CSS properties.
2. **No inline styles.** Never use the `style` attribute. If Tailwind lacks a utility, extend the config.
3. **Reuse components first.** Before adding classes to a new element, check whether an existing partial, component, or shared pattern already handles it.
4. **Design tokens over magic numbers.** Use the colors, spacing, and sizes from your config — not arbitrary values like `bg-[#3b82f6]` or `p-[13px]`.
5. **Every UI works in light and dark mode.** No exceptions.
6. **Every UI is responsive.** No exceptions.

---

## Design system: theme configuration

The single source of truth for visual decisions is the Tailwind theme (`tailwind.config.js`, or
`@theme` in CSS for Tailwind v4). Colors, spacing, and breakpoints come from there — not from
arbitrary values scattered across templates.

### Name colors by purpose, not appearance

Semantic names let you restyle the palette without hunting through every template:

```js
// tailwind.config.js
module.exports = {
  theme: {
    extend: {
      colors: {
        primary:   { /* … */ }, // brand / main actions
        secondary: { /* … */ }, // supporting actions
        accent:    { /* … */ }, // highlights and emphasis
        success:   { /* … */ }, // positive feedback
        warning:   { /* … */ }, // cautionary feedback
        error:     { /* … */ }, // error states
        surface:   { /* … */ }, // backgrounds and cards
        muted:     { /* … */ }, // subdued text and borders
      }
    }
  }
}
```

Use `bg-primary-500`, `text-error-600`, `border-muted-200` in templates. Never raw hex or arbitrary color values.

### Stick to one spacing scale

Tailwind's default scale (0, 1, 2, 3, 4, 5, 6, 8, 10, 12, …) is solid. Extend it only with a clear reason — and when you do, add a token rather than reaching for arbitrary values:

```html
<!-- WRONG — arbitrary spacing breaks visual rhythm -->
<div class="p-[13px] mt-[7px] gap-[22px]">

<!-- RIGHT — use the scale -->
<div class="p-3 mt-2 gap-5">
```

---

## Reducing class bloat

Long utility strings — "class soup" — make templates hard to read. Keep class lists short, scannable, intentional.

**Use shorthand utilities** instead of spelling out each direction:

```html
<!-- WRONG --> <div class="pt-4 pb-4 pl-6 pr-6">
<!-- RIGHT --> <div class="py-4 px-6">
```

**Drop classes that duplicate defaults:**

```html
<!-- WRONG — flex-row is the default --> <div class="flex flex-row justify-between">
<!-- RIGHT --> <div class="flex justify-between">
```

**Keep class order consistent** so classes are predictable to scan —
layout → sizing → spacing → typography → colors → effects → states. Automate it with the official
[`prettier-plugin-tailwindcss`](https://github.com/tailwindlabs/prettier-plugin-tailwindcss) rather than ordering by hand:

```json
// .prettierrc
{ "plugins": ["prettier-plugin-tailwindcss"] }
```

---

## Component-first architecture

The primary weapon against class soup is **extracting a component**, not `@apply`. When the same
cluster of classes repeats across templates, extract it into a partial or component — not a CSS
abstraction.

```erb
<%# WRONG — the same button classes copy-pasted everywhere %>
<button class="inline-flex items-center gap-2 px-4 py-2 bg-primary-500 text-white rounded-lg hover:bg-primary-600 dark:bg-primary-600 dark:hover:bg-primary-700">
  Save
</button>

<%# RIGHT — extract a component, pass a variant %>
<%= render ButtonComponent.new(variant: :primary, label: "Save") %>
```

**Use a finite set of variants** rather than accepting arbitrary classes — this keeps the design
system consistent and gives you one place to edit:

```ruby
# app/components/button_component.rb
VARIANTS = {
  primary:   "bg-primary-500 text-white hover:bg-primary-600 dark:bg-primary-600 dark:hover:bg-primary-700",
  secondary: "bg-surface-100 text-surface-800 hover:bg-surface-200 dark:bg-surface-700 dark:text-surface-100",
  danger:    "bg-error-500 text-white hover:bg-error-600 dark:bg-error-600 dark:hover:bg-error-700"
}.freeze
```

Changing a variant propagates everywhere it's used — one edit, not dozens. (In a Rails app, the
component owns its class map in a constant — see the rails-toolkit `rails-viewcomponents` skill.)

### When to reach for `@apply`

Reserve `@apply` for cases where component extraction isn't practical — global base styles,
third-party overrides, or markup generated by libraries you don't control. Keep it inside
`@layer components` to avoid specificity issues:

```css
/* app/assets/stylesheets/application.css */
@layer components {
  .prose-content a {
    @apply text-primary-600 underline hover:text-primary-800 dark:text-primary-400;
  }
  /* Third-party output you can't add classes to directly */
  .trix-content h2 {
    @apply text-lg font-semibold mt-6 mb-2;
  }
}
```

If you can extract a component or partial instead, always prefer that.

---

## Dark mode

Every element with color classes needs a `dark:` variant. Dark mode ships with the initial
implementation, not as a follow-up.

```html
<!-- WRONG — dark mode forgotten -->
<div class="bg-white text-gray-900 border-gray-200">

<!-- RIGHT — both modes -->
<div class="bg-white dark:bg-gray-900 text-gray-900 dark:text-gray-100 border-gray-200 dark:border-gray-700">
```

- **Contrast still matters.** Dark mode isn't just inverting colors — maintain WCAG AA ratios
  (4.5:1 normal text, 3:1 large text). Light text on dark: use `-100`/`-200` shades; dark text on
  light: `-800`/`-900`. Avoid pure white on pure black — use off-whites and deep grays.
- **Adjust images that look wrong on dark backgrounds:** `class="dark:brightness-90 dark:contrast-105"`.
- **Verify both modes** after any UI change: text readable, borders visible, hover/focus states
  clear, icons and images don't vanish.

---

## Responsive design

Mobile-first: start with the mobile layout, then add larger breakpoints.

```html
<!-- Mobile: stack · Tablet: side-by-side · Desktop: sidebar grid -->
<div class="flex flex-col md:flex-row lg:grid lg:grid-cols-[250px_1fr]">
  <nav class="p-4 md:w-64 lg:w-auto">…</nav>
  <main class="p-4 flex-1">…</main>
</div>
```

Common patterns: `grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3`, `hidden lg:block`,
`text-2xl md:text-3xl lg:text-4xl`, `px-4 md:px-8 lg:px-16`.

**Touch targets** need adequate size on mobile — minimum 44×44px: `class="min-h-[44px] min-w-[44px] px-4 py-2"`.

---

## Accessibility

Styling affects accessibility directly.

- **Visible focus for keyboard users.** Use `focus-visible` (not `focus`) so the ring only shows
  for keyboard navigation, not mouse clicks — and never remove an outline without replacing it:
  `class="focus:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2"`.
- **Color is not the only signal.** Pair color with an icon or text. An error field gets
  `aria-invalid="true"` + an `aria-describedby` message, not just `border-error-500`.
- **Semantic HTML first.** `<button>` over `<div role="button">`; `<nav>` over `<div aria-label="navigation">`.
- **Screen-reader-only labels** for icon-only controls: `<span class="sr-only">Delete post</span>`.
- **Respect reduced motion:** `class="transition-transform motion-reduce:transition-none motion-reduce:transform-none"`.

---

## Anti-patterns

| Don't | Do instead | Why |
|-------|-----------|-----|
| `style="color: red"` | `text-error-500` | Inline styles bypass the design system |
| `bg-[#3b82f6]` | `bg-primary-500` | Arbitrary values can't be updated centrally |
| Copy-paste 15 classes | Extract a component | Components are the reuse mechanism |
| Raw CSS in `.css` files | Tailwind utilities, or `@apply` in `@layer` | Plain CSS diverges from the system |
| `p-[13px]` | `p-3` (or extend the config) | Arbitrary spacing breaks visual rhythm |
| Forget `dark:` variants | Pair light and dark always | Half your users see a broken UI |
| Forget breakpoints | Mobile-first, add `md:`/`lg:` | Mobile users are the majority |
| `focus:` for focus rings | `focus-visible:` | Avoids focus rings on mouse clicks |
| Remove outline, no replacement | `focus:outline-none focus-visible:ring-2` | Keyboard users must see focus |

---

## Checklist for UI changes

1. **Existing component?** — is there a partial/component/shared pattern that already handles this?
2. **Design tokens** — colors, spacing, sizes from the theme, not arbitrary values.
3. **Lean classes** — shorthand, drop defaults, consistent order (Prettier plugin).
4. **Dark mode** — every color class has a `dark:` pair, contrast holds.
5. **Responsive** — works from mobile up; touch targets ≥ 44px.
6. **Accessibility** — `focus-visible` states, semantic HTML, `sr-only` labels for icon-only buttons.
7. **No plain CSS, no inline styles** — utilities or `@apply` in `@layer components` only.

---

*Adapted from the MIT-licensed [mattsears/rails-cto](https://github.com/mattsears/rails-cto) `rails-cto-tailwind` skill, generalised beyond Rails.*

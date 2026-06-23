# Common a11y fixes (before → after)

Snippets for the issues the checker flags and the ones it can't. HTML unless noted.

## Image with no alt

```html
<!-- before -->
<img src="/logo.png">
<img src="/chart.png">

<!-- after: decorative gets empty alt (screen readers skip it); meaningful describes meaning -->
<img src="/logo.png" alt="">
<img src="/chart.png" alt="Revenue grew 30% from Q2 to Q3">
```

Inline SVG icon:

```html
<!-- decorative (next to a text label) -->
<svg aria-hidden="true" focusable="false">…</svg>

<!-- meaningful (icon is the only content) -->
<svg role="img" aria-labelledby="t1"><title id="t1">Download</title>…</svg>
```

## Icon-only button with no name

```html
<!-- before: announced as just "button" -->
<button><svg>…</svg></button>

<!-- after -->
<button aria-label="Delete item"><svg aria-hidden="true">…</svg></button>
```

Rails: `button_tag aria: { label: "Delete item" } do … end`.
React: `<button aria-label="Delete item">…</button>`.

Prefer visible text when there's room; a visually-hidden label also works:

```html
<button><svg aria-hidden="true">…</svg><span class="sr-only">Delete item</span></button>
```

## Click handler on a non-interactive element

```html
<!-- before: not focusable, no Enter/Space, no role -->
<div onclick="openMenu()">Menu</div>
```

```html
<!-- after: use the real element -->
<button type="button" onclick="openMenu()">Menu</button>
```

If it genuinely can't be a `<button>`, make the `<div>` behave like one:

```html
<div role="button" tabindex="0"
     onclick="openMenu()"
     onkeydown="if(event.key==='Enter'||event.key===' ')openMenu()">Menu</div>
```

Rails/Hotwire: put the `data-action="click->menu#open"` on a `<button>`, not a `<div>`.

## Unlabeled input

```html
<!-- before: placeholder is not a label -->
<input type="email" placeholder="Email">
```

```html
<!-- after: associate a real label -->
<label for="email">Email</label>
<input type="email" id="email" autocomplete="email">
```

Rails form builder does this for you: `form.label :email` + `form.email_field :email`.
React: `<label htmlFor="email">Email</label><input id="email" />`.
No room for a visible label? `aria-label="Email"` (least preferred — visible labels help
everyone).

## Missing page language

```html
<!-- before --> <html>
<!-- after  --> <html lang="en">
```

## Button in a form with no type

```html
<!-- before: defaults to type=submit and submits the form unexpectedly -->
<button>Cancel</button>

<!-- after -->
<button type="button">Cancel</button>
```

## Invisible focus (CSS, can't be auto-detected)

```css
/* before */ :focus { outline: none; }

/* after: keep a visible focus ring for keyboard users */
:focus-visible { outline: 2px solid CanvasText; outline-offset: 2px; }
```

## Reduced motion (CSS)

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { animation-duration: .01ms !important; transition-duration: .01ms !important; }
}
```

## Hotwire: focus + announce after a Turbo swap

```js
// app/javascript/controllers/focus_controller.js
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  connect() { this.element.focus() }   // move focus to freshly-rendered content
}
```

```erb
<%# announce async results to screen readers %>
<div aria-live="polite" class="sr-only"><%= @status_message %></div>
```

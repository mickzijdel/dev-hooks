# Discovery: finding the API and capturing it

Read this for steps 1–3 of the loop: locating the endpoint and getting a clean capture to
work from. There's rarely one right method — the good reverse-engineer is curious about how
the app is built and tries several angles. The techniques below (distilled from Jerome
Paulos's ["All the data can be yours"](https://jero.zone/posts/reverse-engineering-apis))
are roughly ordered easiest-first, but follow your gut about which the target invites.

## Is the data already in the HTML?

Before hunting for a request, check whether the page ships the data inline — server-rendered
frameworks routinely do, and then there's nothing to reverse:

- **Next.js** — a `<script id="__NEXT_DATA__" type="application/json">` blob holds the route's
  props (often the full dataset). Even when the page looks like it loads async, it may just be
  serialized React components; the real data is right there.
- **Nuxt / SvelteKit / Remix** — `window.__NUXT__`, `__remixContext`, or a
  `<script type="application/json">` island.
- **Generic** — grep the raw HTML for `application/json`, `application/ld+json` (structured
  data), or a bare `{"...":` assigned to a `window.` global.

`curl -s <url> | grep -o '__NEXT_DATA__[^<]*'` (or fetch + parse) is often the whole job.

## Watch for fetch/XHR requests

Content that appears *after* the page loads, on scroll, or on a click that doesn't cause a
full navigation is a `fetch`/XHR to a JSON (or GraphQL) endpoint. Find it in DevTools:

1. Open **Network**, tick **Preserve log**, filter to **Fetch/XHR**.
2. Reproduce the action that reveals the data — search, scroll to infinite-load, click "Next
   page", open a detail view.
3. Confirm the JSON in the **Response**/**Preview** tab, then right-click → **Copy → Copy as
   cURL (bash)**, and/or **Save all as HAR** for `har_scan.py`.

Caveat: some old-school sites fire fetch requests that return **HTML**, with the interesting
data assembled on the server — then the request is a dead end and you want one of the
guess/Google/JS-reading angles below.

**GraphQL** shows up as `POST`s to a single `/graphql` endpoint whose body carries a `query`
and `operationName`. If introspection is on, dump the whole schema:

```bash
curl -s https://host/graphql -H 'content-type: application/json' \
  -d '{"query":"query{__schema{types{name fields{name}}}}"}'
```

If introspection is disabled, you can still probe: guess field names and let the server's
error messages "correct" your typos — they often suggest the real field names.

## Free APIs that come with the framework

- **WordPress** — every WP site ships a REST API at `/wp-json/wp/v2/` (posts, pages, media,
  users, categories) and admins rarely lock all of it down. Media is public even when the
  posts using it aren't — `/wp-json/wp/v2/media` is a common data source. (Paulos's
  WP_Snooper tool automates exactly this media query.)
- **Rails** — the classic pattern returns JSON for any page with a `.json` suffix:
  `https://host/search.json?q=…`. Try appending `.json` (or `.xml`) to a normal URL.
- **Swagger/OpenAPI** — try `/swagger.json`, `/openapi.json`, `/api-docs`, `/v1/docs`; an
  exposed spec hands you every endpoint and param.

## Find endpoints without the UI

- **GitHub / grep.app code search** — students, staff, and the site's own frontend have often
  published code that calls the endpoints. Search for the API host or a distinctive path; a
  regex like `/host\.edu\/\S*\.(json|xml)/` surfaces data URLs directly. (`PublicWWW` indexes
  page *source* similarly, if less usefully.)
- **Literally Google the endpoint.** A surprising number of internal APIs leak: searching a
  path can turn up an ASP.NET **"Web API Help Page"** listing every route
  (`allintitle:"ASP.NET Web API Help Page"` is a productive dork), or a cached error/stack
  trace that reveals the full URL you were missing.
- **Just guess the URL.** Once you know the framework, guess: a Next.js app doing async loads
  probably has `/api/<resource>/<id>`; try it. Guessing bits of a truncated URL until the
  server (or Google's cache) fills in the rest is a legitimate move.
- **Wappalyzer / BuiltWith** ("relationships" tool) — identify the stack (Algolia, Contentful,
  a headless CMS, a known SaaS) so you can read *its* public docs instead of guessing.
- **`robots.txt` / cert & subdomain enumeration** — `robots.txt` `Disallow` lines advertise
  the paths they'd rather you not see (a discovery gift, separate from the permission check in
  the skill's gate). `crt.sh`, C99's subdomain finder, and subfinder surface `api.`,
  `gateway.`, `graphql.` hosts.

## Read the site's JavaScript

The app's own JS names its endpoints and reveals how they're called. On older sites the JS is
concatenated but **not** minified; sometimes source maps are left on (load them in DevTools
for original source). Deobfuscating even lightly-mangled JS clarifies request-signing, header
requirements, and the semantics of fields the API docs would never tell you. React DevTools /
Vue DevTools expose component props and the data already loaded into the page.

## Mobile-app APIs

A mobile app *must* speak HTTP to a backend, sometimes to endpoints the web UI never touches:

- **iOS** — download many apps via the Mac App Store, then run `strings` over the app bundle
  to spot endpoint URLs and header/key names (Asset Catalog Tinkerer helps pull embedded
  assets).
- **Android** — grab the APK from a mirror and decompile it (`apktool`, jadx) to read base
  URLs and static API keys from source.
- **Live traffic** — route the device through **mitmproxy / Proxyman / Charles** with its CA
  trusted and watch the calls (cert-pinned apps need a patched build or a jailbroken device).

## Recon toolkit

`crt.sh` · C99 subdomain finder · WP_Snooper · React DevTools · Vue DevTools · Wappalyzer ·
BuiltWith relationships · PublicWWW · GitHub code search · GraphQL Playground (introspection)
· cURL · Postman (request testing) · Proxyman / Charles (mobile & desktop proxying) · Asset
Catalog Tinkerer · an APK decompiler.

## Capturing for an agent

The best handoff: a **HAR file** (request, response body, headers, timing for every entry)
fed to `har_scan.py --find "<known value>"`. If you're driving the browser yourself, a
Playwright `page.on("response", …)` / `context.route` capture or a Chrome-DevTools MCP network
trace produces the same material. Always capture *after* clicking through pagination once —
that reveals the pagination params you'll need in step 5.

To turn a whole capture into a structured **OpenAPI 3.0 spec** of every endpoint and its
params — useful when the site has dozens of endpoints, not one — feed the HAR (or a mitmproxy
flow) to [`mitmproxy2swagger`](https://github.com/alufers/mitmproxy2swagger) or `har2openapi`.
It also auto-detects path parameters (`/users/123` → `/users/{id}`), which saves guessing
which URL segments are variables.

# Discovery: finding the API and capturing it

Read this when you're on step 1–3 of the loop: locating the endpoint and getting a clean
capture to work from.

## Is the data already in the HTML?

Before hunting for a request, check whether the page ships the data inline — server-rendered
frameworks routinely do, and then there's nothing to reverse:

- **Next.js** — a `<script id="__NEXT_DATA__" type="application/json">` blob holds the page's
  props (often the full dataset for the route).
- **Nuxt / SvelteKit / Remix** — `window.__NUXT__`, `__remixContext`, or a
  `<script type="application/json">` island.
- **Generic** — grep the raw HTML for `application/json`, `application/ld+json` (structured
  data), or a bare `{"...":` assigned to a `window.` global.

`curl -s <url> | grep -o '__NEXT_DATA__[^<]*'` (or fetch + parse) is often the whole job.

## Where the requests hide

If the data loads dynamically, find the request in DevTools:

1. Open **Network**, tick **Preserve log**, filter to **Fetch/XHR**.
2. Reproduce the action that reveals the data — type in the search box, scroll to trigger
   infinite-load, click "Next page", open a detail view.
3. The new rows come from a JSON (or GraphQL) response. Confirm it in the **Response**/
   **Preview** tab, then right-click → **Copy → Copy as cURL (bash)**, and/or **Save all as
   HAR** for `har_scan.py`.

**GraphQL** shows up as `POST`s to a single `/graphql` endpoint whose body carries a `query`
and `operationName`. If introspection is left on, you can dump the whole schema:

```bash
curl -s https://host/graphql -H 'content-type: application/json' \
  -d '{"query":"query{__schema{types{name fields{name}}}}"}'
```

## Finding endpoints without the UI

When the browser path is awkward (the value is deep in a flow, or you want related endpoints):

- **GitHub / grep.app / PublicWWW code search** — search for the API host or a distinctive
  path; someone has often published a client or the frontend calls are in an open repo.
- **Wappalyzer / BuiltWith** — identify the stack (Algolia, Contentful, a headless CMS, a
  known SaaS) so you can read *its* public API docs instead of guessing.
- **Subdomain / cert enumeration** (`crt.sh`, subfinder) — `api.`, `gateway.`, `graphql.`
  hosts are the API surface.
- **Swagger/OpenAPI** — try `/swagger.json`, `/openapi.json`, `/api-docs`, `/v1/docs`; an
  exposed spec hands you every endpoint and param.

## Mobile-app APIs

A mobile app is often a thinner, less-defended client of the same backend, sometimes with
endpoints the web UI doesn't use:

- Route the phone through **mitmproxy / Proxyman / Charles** with its CA trusted and watch the
  traffic (some apps pin certs — then you need a patched build or a jailbroken device).
- **Decompile the APK** (`apktool`, jadx) to read base URLs, header names, and static API keys
  straight from the source.

## Capturing for an agent

The handoff that works best: a **HAR file** (it carries request, response body, headers, and
timing for every entry) fed to `har_scan.py --find "<known value>"`. If you're driving the
browser yourself, a Playwright `context.route`/`page.on("response")` capture or a
Chrome-DevTools MCP network trace produces the same material. Always capture *after* clicking
through pagination at least once — that reveals the pagination params you'll need in step 5.

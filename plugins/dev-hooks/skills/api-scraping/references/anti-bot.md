# Anti-bot escalation ladder

Read this when a request works in the browser but your replay is blocked. Climb the ladder
**one rung at a time** — each rung is more fragile and more effort than the last, so stop the
moment the data flows. Most sites never require more than rung 1–2.

## Rung 1 — headers

The block is a missing or wrong header. Copy the browser's exactly:

- `User-Agent` — an empty or `python-requests/x` UA is the single most common tell.
- `Accept: application/json`, `Accept-Language`.
- `Referer` / `Origin` — some backends reject a request that didn't "come from" their page.
- App-specific headers seen in the HAR: `X-Requested-With: XMLHttpRequest`, `X-Api-Key`,
  `X-CSRF-Token`.

## Rung 2 — cookies / auth token

Empty responses or a redirect to login mean a credential is missing. Replay the session
`Cookie` or `Authorization: Bearer …` from the capture, then **script how it's minted** — a
login `POST`, an OAuth/`/token` exchange, or a CSRF token embedded in the initial HTML — so
the client refreshes it instead of dying when the copied token expires. Store secrets out of
the code (env var / the repo's secret manager), never hardcoded.

## Rung 3 — TLS / HTTP-2 fingerprinting

Correct headers and cookies, yet a plain client still gets 403 while the browser sails
through: the server is fingerprinting the **TLS handshake and HTTP-2 settings** (cipher
order, extensions, GREASE, `SETTINGS` frame), which a stock `requests`/`httpx` client can't
fake. Cloudflare, Akamai, and DataDome all do this. Changing only the `User-Agent` here is
"a new disguise but the same fingerprints everywhere."

Use [`curl_cffi`](https://github.com/lexiforest/curl_cffi), which swaps the TLS stack to match
a real browser:

```python
from curl_cffi import requests
r = requests.get(url, headers=HEADERS, impersonate="chrome")   # matches Chrome's TLS + HTTP2
```

It's a near drop-in for `requests`/`httpx` (`.get`, `.json()`, sessions), so the client
skeleton in [client.md](client.md) barely changes. Often a well-behaved reputable proxy IP is
needed alongside it — a residential/clean IP plus a real fingerprint is the combination that
passes; either alone often doesn't.

## Rung 4 — headless browser

Reach for this only when a request param is a **signature computed by the site's JavaScript**
that you can't reproduce, or the flow genuinely needs JS execution. Run the real page in
Playwright and either:

- let the page make the call and **intercept the response** (`page.on("response", …)` /
  `context.route`), or
- execute the site's own signing function in-page (`page.evaluate`) and reuse the token for
  direct API calls (fast path: browser for auth, plain client for the bulk pull).

This is the slowest, heaviest option — one browser per worker, real memory — so use it as the
auth/bootstrap step, not the per-row fetch, whenever you can.

## Hard stop — CAPTCHAs

Cloudflare Turnstile, hCaptcha, reCAPTCHA, and "press and hold" challenges are designed to
stop exactly this, and `curl_cffi`/headless tricks don't reliably beat them. **Do not try to
solve or farm them out.** Surface it to the user with `AskUserQuestion` — they may have
legitimate API access, an official export, or a reason not to proceed. Defeating an access
control is the user's call to make, not yours.

## Staying under the radar honestly

The goal is *respectful* access, not evasion: pace requests, back off on 429, cache what you
already pulled so you don't re-fetch, and prefer the smallest job that gets the data. A
scraper that behaves like a considerate client rarely trips these systems in the first place —
most bans are earned by hammering, not by fingerprints.

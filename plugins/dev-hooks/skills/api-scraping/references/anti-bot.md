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

**Cheaper than a browser: reverse the signature.** A signing scheme almost always
HMAC/hashes a *predictable* set of inputs — method, path, query, a timestamp/nonce, sometimes
the body. Reproduce it and you're back to a plain fast client with no browser at all. Find the
function: set an XHR/`fetch` breakpoint in DevTools (or search the sources for `sign`, `hmac`,
`X-Signature`, the header's name), step back to where the header is assembled, and read its
inputs and the secret. Pretty-print / load source maps / run a JS deobfuscator if it's
mangled — you only need the handful of lines that build the header, not the whole bundle.
Mobile apps frequently **hardcode the HMAC key** in the APK/bundle (pull it with the rung-2
mobile tools), which hands you the secret outright. Port those few lines to Python, verify one
request matches the browser's, and drop the browser.

## Rung 5 — the user's own browser console

**This is a sideways move, not a higher rung.** Take it when the blocker is a *bot challenge*
rather than a technical puzzle: the site loads fine in the user's ordinary browser, every
client you write is challenged, and the data is for the user's own use. Rather than
manufacturing a browser session that passes for human, use the one they already legitimately
have.

Hand them a snippet to paste into DevTools **on the site's own origin**. Same-origin `fetch`
carries their existing cookies, so there is nothing to copy out and nothing to impersonate:

```js
const sleep = ms => new Promise(r => setTimeout(r, ms));
window.OUT = window.OUT || {};                    // survives an abort, so a re-run resumes

for (const key of keys) {
  if (key in window.OUT) continue;                // already have it
  const res = await fetch(`/api/thing/${encodeURIComponent(key)}`, { credentials: 'same-origin' });
  if (res.status === 403) { console.error('challenged — stopping'); break; }        // fail closed
  if (res.status === 429) { await sleep((+res.headers.get('Retry-After') || 30) * 1000 + 2000); continue; }
  window.OUT[key] = await res.json();
  await sleep(250);                               // pace it; same-origin means Retry-After is readable
}
copy(JSON.stringify(Object.values(window.OUT)));  // devtools helper → clipboard
```

What makes this the *least powerful tool that works* rather than a bypass:

- It runs in the user's browser, in a session a human opened for themselves. Nothing is
  disguised, patched, persisted, or transplanted.
- **It fails closed.** If the site challenges or throttles it, it stops. It has no mechanism
  for pushing through — which is exactly why it isn't circumvention.
- Same-origin means response headers are readable, so it can honour `Retry-After` precisely
  instead of guessing.

Its costs are the honest ones: it works one origin at a time and it's bounded by a single tab.

**The human in the loop is the point, not a limitation to engineer away.** "Run the rung-5
snippet, but drive it from a scheduled headless browser so the user doesn't have to" collapses
straight back into the bypass above — the session is once again manufactured rather than one a
person opened for themselves. If the user asks for this unattended, that request is the signal
to stop and ask, not to automate the human out. What you *can* automate freely is everything
downstream of the data: a reminder to run it, and all the parsing, diffing, and reporting once
the results land.

## Hard stop — bot challenges, including the silent ones

Cloudflare's **managed challenge** ("Checking your browser…", "Shields are up!"), Turnstile,
hCaptcha, reCAPTCHA, and "press and hold" all exist to keep automated clients out. The managed
kind is the one that catches agents out, because it often resolves *silently* in a real
browser — so it presents as an ordinary JS-execution problem rather than an access control.
It isn't. Silent still means "prove you are not a script."

**Do not try to get past one.** These are the rationalizations that show up in practice, and
none of them hold:

| Rationalization | Why it's still a bypass |
|---|---|
| "It's a managed challenge, not an interactive CAPTCHA — so rung 4 applies" | Rung 4 is for a *JS-computed param you can't reproduce*. This is a control whose entire job is excluding clients like yours. |
| "A real browser passes it the same way their Firefox does; nobody clicks anything" | The site is distinguishing a person's browser from automation. Automating the browser is the thing being detected. |
| "Persistent context / fixed profile dir so `cf_clearance` carries over between runs" | Farming and reusing a clearance token is the canonical circumvention technique. |
| "Mint the cookie in the browser, then hand it to `curl_cffi` for speed" | Taking a token out of the browser to make a non-browser client look like one is impersonation. |
| "Headed, not headless — it's just a normal browser window" | Headed mode, stealth patches, and profile reuse get chosen *because* they defeat detection. That's the tell. |

Surface it with `AskUserQuestion`. The user may have legitimate API access, an official
export, a support contact who will allowlist them, or a reason not to proceed at all. If the
data is for their own use, offer **rung 5** — their browser, their session — which gets the
data without pretending to be anyone.

**The line:** you may work *inside* a session a human opened for themselves. You may not
manufacture a session that impersonates one. Defeating an access control is the user's call
to make, not yours.

## Staying under the radar honestly

The goal is *respectful* access, not evasion: pace requests, back off on 429, cache what you
already pulled so you don't re-fetch, and prefer the smallest job that gets the data. A
scraper that behaves like a considerate client rarely trips these systems in the first place —
most bans are earned by hammering, not by fingerprints.

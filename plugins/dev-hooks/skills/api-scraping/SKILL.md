---
name: api-scraping
description: |
  Get structured data off a website by reverse-engineering the private JSON/GraphQL API
  behind it instead of scraping rendered HTML. Use when the user wants to "scrape a site",
  "get all the X from", "pull listings/results/posts/prices from", "build a scraper/client
  for", says "there's no public API for this", or "reverse-engineer this site's API". The
  loop: capture network traffic (HAR), find the request carrying the data, replay it outside
  the browser, minimize headers/auth to only what's required, then generate a paginating,
  rate-limited, resumable client. Escalates only as far as it must (headers → cookies/token →
  TLS impersonation → headless browser) and stops at CAPTCHAs and anything needing the user's
  legal/ToS call.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
  - WebFetch
  - AskUserQuestion
  - Task
---

# api-scraping

Most "scrape this website" problems are really "call the site's own API." A modern site's
pages are shells that fetch JSON from an internal endpoint; that endpoint returns clean,
structured, paginated data with no HTML to parse and no rendering to run. Reverse-engineer
that call and you get the data faster, more reliably, and with far less code than a DOM
scraper — the DOM scraper is the **fallback**, not the plan. (Adapted from Jerome Paulos's
["All the data can be yours"](https://jero.zone/posts/reverse-engineering-apis), turned into
a loop an agent can run, plus HAR tooling and an anti-bot escalation ladder.)

## Gate first (every run)

Before capturing anything, settle scope and permission — this is cheap and non-negotiable:

- **What, how much, how often** — a one-off pull of a few thousand public rows is not a
  standing crawler hammering an endpoint. Size the job.
- **`robots.txt` and Terms of Service** — fetch `https://<host>/robots.txt`; skim the ToS for
  an anti-scraping clause. `robots.txt` is advisory, not law, but ignoring an explicit
  disallow is a decision the **user** makes, not you.
- **Stop and ask (`AskUserQuestion`) when** the data is behind a login you weren't given,
  the target is personal data (PII) at scale, the ToS explicitly forbids it, or the only way
  through is defeating a CAPTCHA/bot-challenge. Public data, respectful rate, no auth bypass
  is the green path.

## The loop

1. **Spot the API.** Content that appears *after* the page loads, on scroll, or on a click
   that doesn't cause a full navigation is a `fetch`/XHR to a JSON or GraphQL endpoint. Also
   check whether the data is already **embedded** in the HTML (`__NEXT_DATA__`,
   `<script type="application/json">`, `window.__…__`) — sometimes there is no request to
   reverse at all. See [references/discovery.md](references/discovery.md) for where to look
   and the recon toolkit (GraphQL introspection, GitHub/PublicWWW code search, mobile-app
   APIs via a proxy).

2. **Capture the traffic.** The most agent-friendly input is a **HAR**. Ask the user to open
   DevTools → Network, tick *Preserve log*, reproduce the action (search, scroll, click
   "next"), then *Save all as HAR* — or right-click the request → *Copy as cURL*. If you can
   drive a browser yourself (Playwright / a Chrome-DevTools MCP), record the network directly.

3. **Find the request that carries the data.** Don't eyeball hundreds of entries — search the
   capture for a value you can see on the page:
   ```bash
   python3 "$CLAUDE_PLUGIN_ROOT/skills/api-scraping/scripts/har_scan.py" capture.har --find "<a value from the page>"
   ```
   It ranks the XHR/fetch + JSON requests and marks the one whose response body contains that
   value. That request is your endpoint.

4. **Replay, then minimize.** Run the `Copy as cURL` command in a terminal and confirm it
   returns the data **outside** the browser. Then strip it to essentials: remove headers and
   cookies **one at a time**, re-running after each, until it breaks. What survives is what's
   *actually* required — usually a couple of headers and one auth token, not the 30 headers
   the browser sent. Know which of the survivors is the auth (a `Cookie`, a
   `Authorization: Bearer …`, an `X-Api-Key`) and where it's minted (a login or token-refresh
   request in the same HAR).

5. **Parametrize.** Identify the knobs in the URL/body: pagination (`page`/`offset`/`cursor`/
   `limit`), filters, ids, and any signature/nonce param. Change one, re-run, confirm the
   response changes as expected. If a param is an opaque signature you can't reproduce, that's
   an escalation signal (step 7).

6. **Generate a client.** Write a small, typed client that sends only the required headers,
   **follows the response's own next-pointer** for pagination (never a guessed page count),
   backs off on HTTP 429 respecting `Retry-After`, paces politely, and writes results
   incrementally (JSONL) so an interrupted run resumes. Skeleton + pagination/backoff patterns
   in [references/client.md](references/client.md).

7. **Escalate only if it breaks — least powerful tool that works:**

   | Symptom | Move |
   |---------|------|
   | 403/challenge on the direct call, but it works in the browser | Replicate the exact browser headers (`User-Agent`, `Accept`, `Referer`, `Origin`) |
   | Needs login / returns empty without it | Replay the auth cookie or bearer token; script the login/refresh that mints it |
   | Correct headers, still blocked, browser-only | TLS/HTTP-2 fingerprinting — switch to `curl_cffi` with `impersonate` |
   | A request-signing / JS-computed param you can't reproduce | Run the page in a headless browser (Playwright) and call the API from its context, or intercept the response |
   | CAPTCHA / Cloudflare Turnstile / hCaptcha | **Stop. Ask the user.** Do not attempt to defeat it |

   Details, `curl_cffi` example, proxies, and pacing in
   [references/anti-bot.md](references/anti-bot.md).

8. **Verify.** Spot-check scraped rows against the live site; confirm the row count matches
   the site's own reported total where it shows one; confirm a second run is idempotent and
   resumes rather than restarting.

## Done when

- The API call runs outside the browser with **only** the headers it genuinely needs — every
  remaining header justified by the minimize step, not copied wholesale.
- Pagination terminates on the API's own signal (no next cursor / `has_more: false` / empty
  page), not a hardcoded page count.
- 429s back off and honor `Retry-After`; the run is rate-limited and resumable.
- Output is spot-checked against the live site and totals reconcile where the site reports one.
- No CAPTCHA-bypass, no credentialed access you weren't handed, `robots.txt`/ToS accounted for.

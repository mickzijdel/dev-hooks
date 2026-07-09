# Building the client: minimize, paginate, resume

Read this for steps 4–6: reducing the request to essentials and turning it into a client that
pulls the whole dataset without hammering the server or losing work on a crash.

## Minimize the request (the core discipline)

A browser's `Copy as cURL` carries everything the browser happened to send — 20–40 headers,
a wall of cookies, `sec-ch-ua-*` client hints, tracking cookies. Almost none of it is
required. Reduce it:

1. Confirm the copied cURL returns the data in a terminal.
2. Delete headers/cookies in chunks, re-running after each cut, until the response breaks.
3. Bisect the last chunk to the individual header/cookie that mattered.

What typically survives: `User-Agent` (some backends 403 an empty one), `Accept:
application/json`, sometimes `Referer`/`Origin` (CSRF/hotlink checks), and **one** credential
— a session `Cookie`, an `Authorization: Bearer …`, or an `X-Api-Key`. Everything else is
noise. Knowing the minimal set is what makes the client robust: fewer moving parts to rot.

Then find where the credential comes from — a login `POST`, a `/token` refresh, or a value
embedded in the initial HTML — so the client can mint it rather than relying on a copied token
that expires.

## Pagination — follow the API's own pointer

Never guess a page count. Read how the response says "there's more" and stop when it says
there isn't:

| Style | Looks like | Loop |
|-------|-----------|------|
| Offset/limit | `?offset=100&limit=50`, response has `total` | increment `offset` by `limit` until `offset >= total` or a short/empty page |
| Page number | `?page=3`, response has `total_pages`/`has_next` | increment `page` until `has_next` is false or a page returns no rows |
| Cursor/keyset | response has `next_cursor`/`endCursor`/`next` URL | pass it back as the next request's cursor until it's null/absent |
| Infinite scroll | same XHR fires with a bumped offset/cursor on scroll | it's one of the above under the hood — capture two scrolls to see which param moves |

Cursor pagination is the most robust (it doesn't skip/duplicate when rows shift between
requests); prefer it when the API offers both.

## Rate limiting, backoff, resumability

- **Pace**: a small delay between requests (≈0.5–2 s, or match the site's observed cadence).
  Politeness *is* durability — it's what keeps you from getting the IP blocked mid-run.
- **Backoff on 429/503**: sleep and retry with exponential backoff; if the response carries a
  `Retry-After` header, honor it exactly instead of guessing.
- **Resume**: write each page/record to a JSONL file as it arrives and record the last
  cursor/offset, so an interrupted run continues instead of restarting (and re-hammering).

## Skeleton (Python + httpx)

Adapt — don't paste blind. Fill in the minimized headers, the real endpoint, and the
pagination fields you found.

```python
# /// script
# requires-python = ">=3.12"
# dependencies = ["httpx"]
# ///
import json, time, pathlib, httpx

BASE = "https://api.example.com/v2/listings/search"
HEADERS = {                      # ONLY the headers the minimize step proved necessary
    "User-Agent": "Mozilla/5.0 (research; contact you@example.com)",
    "Accept": "application/json",
    # "Authorization": f"Bearer {token}",
}
OUT = pathlib.Path("listings.jsonl")

def fetch(client, cursor):
    params = {"limit": 100}
    if cursor:
        params["cursor"] = cursor
    for attempt in range(6):
        r = client.get(BASE, params=params, headers=HEADERS, timeout=30)
        if r.status_code == 429:
            wait = float(r.headers.get("Retry-After", 2 ** attempt))
            time.sleep(wait)
            continue
        r.raise_for_status()
        return r.json()
    raise RuntimeError("giving up after repeated 429s")

def main():
    seen = sum(1 for _ in OUT.open()) if OUT.exists() else 0
    cursor = None  # load a persisted cursor here to truly resume
    with httpx.Client(http2=True) as client, OUT.open("a") as sink:
        while True:
            page = fetch(client, cursor)
            rows = page.get("results", [])
            for row in rows:
                sink.write(json.dumps(row) + "\n")
            seen += len(rows)
            print(f"{seen} rows")
            cursor = page.get("next_cursor")     # <-- the API's own next-pointer
            if not cursor or not rows:
                break
            time.sleep(1)                          # be polite

if __name__ == "__main__":
    main()
```

Swap `httpx` for `curl_cffi` (same `.get`/`.json` shape, plus `impersonate=`) when the site
fingerprints TLS — see [anti-bot.md](anti-bot.md).

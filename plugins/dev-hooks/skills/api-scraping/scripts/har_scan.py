#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Find the API request that carries the data inside a captured HAR file.

Reverse-engineering a site's private API starts with a browser capture — a HAR
saved from DevTools' Network tab, or one recorded by a headless browser. A real
capture holds hundreds of entries (documents, CSS, images, analytics beacons);
eyeballing them for the one JSON endpoint that returns the data is slow and
error-prone. This ranks the candidates instead.

Two questions it answers:

  1. Which requests look like a data API? (XHR/fetch + a JSON/GraphQL response.)
  2. Which of those actually contains the value I saw on the page?
     `--find "Introduction to Algorithms"` decodes each response body and marks
     the request whose response holds that string — that is your endpoint.

Output is one block per candidate: method, status, URL, split query params, any
POST/GraphQL body, and the response mime + size. Matches float to the top.

    har_scan.py capture.har
    har_scan.py capture.har --find "$3,499" --find "Milano"
    har_scan.py capture.har --all --json

Exit status: 0 when the HAR parsed and a report was produced, 2 on a bad path or
a file that is not a HAR.
"""

from __future__ import annotations

import argparse
import base64
import json
import sys
from urllib.parse import parse_qsl, urlsplit

# Resource types (Chrome/Firefox set `_resourceType`) that are never a data API.
NON_API_TYPES = {
    "document",
    "stylesheet",
    "script",
    "image",
    "font",
    "media",
    "manifest",
    "texttrack",
    "websocket",
    "eventsource",
    "ping",
    "other",
}
API_TYPES = {"xhr", "fetch"}
DATA_MIMES = ("json", "graphql", "javascript")  # javascript catches JSONP


def human_size(n: int) -> str:
    """Bytes → a compact human string; -1 (unknown, common in HARs) → '?'."""
    if n is None or n < 0:
        return "?"
    step = float(n)
    for unit in ("B", "KB", "MB", "GB"):
        if step < 1024 or unit == "GB":
            return f"{step:.0f} {unit}" if unit == "B" else f"{step:.1f} {unit}"
        step /= 1024
    return f"{step:.1f} GB"


def response_body(content: dict) -> str:
    """Decode a HAR response body, transparently un-base64-ing binary captures."""
    text = content.get("text")
    if not text:
        return ""
    if content.get("encoding") == "base64":
        try:
            return base64.b64decode(text).decode("utf-8", "replace")
        except (ValueError, UnicodeDecodeError):
            return ""
    return text


def is_candidate(res_type: str, mime: str, all_entries: bool) -> bool:
    if all_entries:
        return True
    if res_type in API_TYPES:
        return True
    if res_type in NON_API_TYPES:
        return False
    # No/unknown resource type (some exporters omit it): fall back to the mime.
    return any(tag in mime for tag in DATA_MIMES)


def analyse(entry: dict, find_terms: list[str], all_entries: bool) -> dict | None:
    req = entry.get("request", {})
    resp = entry.get("response", {})
    content = resp.get("content", {})
    res_type = (entry.get("_resourceType") or entry.get("_type") or "").lower()
    mime = (content.get("mimeType") or "").lower()

    if not is_candidate(res_type, mime, all_entries):
        return None

    url = req.get("url", "")
    split = urlsplit(url)
    body = response_body(content) if find_terms else ""
    hits = [t for t in find_terms if t.lower() in body.lower()] if body else []

    post = req.get("postData", {})
    post_text = post.get("text", "") if isinstance(post, dict) else ""
    operation = ""
    if "graphql" in url.lower() or "graphql" in (
        post.get("mimeType", "") if isinstance(post, dict) else ""
    ):
        try:
            operation = json.loads(post_text).get("operationName") or ""
        except (ValueError, TypeError):
            operation = ""

    # HAR spec says size/bodySize are numbers, but exporters emit null (or worse, a
    # string) — coerce anything non-numeric to -1 ('unknown') so ranking never chokes.
    size = content.get("size")
    if not isinstance(size, (int, float)) or size < 0:
        size = resp.get("bodySize")
    if not isinstance(size, (int, float)):
        size = -1

    return {
        "method": req.get("method", "?"),
        "status": resp.get("status", 0),
        "url": f"{split.scheme}://{split.netloc}{split.path}" if split.netloc else url,
        "query": parse_qsl(split.query, keep_blank_values=True),
        "mime": content.get("mimeType") or "",
        "size": size,
        "post": post_text,
        "operation": operation,
        "hits": hits,
    }


def rank_key(c: dict) -> tuple:
    """Matches first, then JSON responses, then bigger bodies."""
    is_json = any(tag in c["mime"].lower() for tag in DATA_MIMES)
    return (-len(c["hits"]), 0 if is_json else 1, -(c["size"] if c["size"] > 0 else 0))


def render(candidates: list[dict]) -> str:
    lines: list[str] = []
    for c in candidates:
        marker = ""
        if c["hits"]:
            marker = "  <== MATCH: " + ", ".join(f'"{h}"' for h in c["hits"])
        lines.append(f"{c['method']:5} {c['status']}  {c['url']}{marker}")
        if c["operation"]:
            lines.append(f"      graphql: {c['operation']}")
        for k, v in c["query"]:
            shown = v if len(v) <= 60 else v[:57] + "..."
            lines.append(f"      ? {k} = {shown}")
        if c["post"] and not c["operation"]:
            snippet = c["post"].replace("\n", " ")
            lines.append(
                f"      body: {snippet[:80]}{'...' if len(snippet) > 80 else ''}"
            )
        lines.append(f"      resp: {c['mime'] or '(none)'}  {human_size(c['size'])}")
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Rank the API-looking requests in a HAR capture; --find locates "
        "the one whose response holds a value you saw on the page.",
    )
    ap.add_argument(
        "harfile", help="path to a .har capture (DevTools 'Save all as HAR')"
    )
    ap.add_argument(
        "--find",
        action="append",
        default=[],
        metavar="TEXT",
        help="mark requests whose response body contains TEXT (repeatable)",
    )
    ap.add_argument(
        "--all",
        action="store_true",
        help="include every entry, not just XHR/fetch + JSON candidates",
    )
    ap.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    args = ap.parse_args()

    try:
        with open(args.harfile, encoding="utf-8") as fh:
            data = json.load(fh)
        entries = data["log"]["entries"]
    except FileNotFoundError:
        print(f"har_scan: no such file: {args.harfile}", file=sys.stderr)
        return 2
    except (ValueError, KeyError, TypeError):
        print(f"har_scan: not a valid HAR file: {args.harfile}", file=sys.stderr)
        return 2

    candidates = [
        c for c in (analyse(e, args.find, args.all) for e in entries) if c is not None
    ]
    candidates.sort(key=rank_key)

    if args.json:
        print(json.dumps(candidates, indent=2))
        return 0

    matched = sum(1 for c in candidates if c["hits"])
    total = len(entries)
    summary = f"{len(candidates)} API candidate(s) out of {total} request(s)"
    if args.find:
        summary += f"; {matched} matched your search"
    print(summary + "\n")
    if candidates:
        print(render(candidates), end="")
    if args.find and matched == 0:
        print(
            "No response body matched. The capture may not include response bodies "
            "(re-save the HAR without clearing the log), or the value is paginated / "
            "rendered client-side — try a value from the first screenful.",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())

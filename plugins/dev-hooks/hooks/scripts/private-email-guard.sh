#!/bin/bash
# bet: none (L4 — consent boundary on handing an email address to outside services)
# sunset: never (privacy)
# PreToolUse(Bash|WebFetch|WebSearch|Write|Edit|MultiEdit|NotebookEdit|mcp__*): ask the
# person before a tool call sends an email address off the machine, unless it is on their
# allowlist. Agents sign a scraper politely, a User-Agent or From header "with a contact
# address", and fill in the person's own address, which then sits in the logs of every site
# fetched; other people's addresses leak the same way.
#
# Allowed addresses are DEV_HOOKS_ALLOWED_EMAILS (comma- or space-separated, in .claude
# settings "env"), such as a public alias for bots; with none set, every address asks. Never
# counted: reserved documentation and test domains (example.com/.org/.net, *.example, *.test,
# *.invalid, *.localhost), systemd unit names (name@instance.service), noreply addresses, git@
# logins, a URL's user name and password, and in Bash an ssh/sftp/mosh target or an scp/rsync
# user@host: path.
#
# What counts as sending, per tool (case-insensitive; text is percent-decoded first):
#   Bash      — an address outside git's identity settings (user.email, GIT_*_EMAIL, a
#               git_email YAML key, an --author argument) in a command that can reach the
#               network: a URL of any scheme but file://, curl/wget/http, or a tool or library
#               whose target needn't be a URL (gh, ssh, mail, aws, psql, requests, smtplib,
#               polite-API clients such as Entrez, pyalex, habanero, geopy, LWP, PHP curl...).
#               The whole command is judged, since the address is often set in a variable
#               that a later curl uses. A command whose every target is this machine
#               (localhost, 127.0.0.1, 0.0.0.0, [::1]) stays silent; one that also names
#               another host, or uses a tool or library above, asks.
#   WebFetch  — the URL. WebSearch — the query. MCP tools — any argument.
#   Write, Edit, MultiEdit, NotebookEdit — in code and config, any address (a constant on
#               its own line still ends up in the requests the code makes), except in a test
#               file with no request code; in prose (Markdown, HTML, ERB, text) and package
#               manifests (package.json, pyproject.toml, *.gemspec, AUTHORS...) a line that puts
#               an address in a request: a User-Agent, From header, contact string, mailto=/email=
#               parameter, curl call, HTTP library.
#
# The ask carries the guard prefix, so the dev-hooks mod puts it to the person in a dialog
# rather than letting auto mode answer it. It names every address it asks about after
# "Not on your allowed list (DEV_HOOKS_ALLOWED_EMAILS): " and, when it can pin where the call
# goes, ends with "Destination: " and a typed label ("hosts: a.org b.org", "file: <path>",
# "mcp: <tool>", "web search"); the mod reads both to offer allowing those addresses to that
# destination for the rest of the session (register.tsx EMAIL_ASK_MARK, DEST_MARK). The type
# keeps a file path from passing as a host. A Bash command whose targets can't all be seen (a
# library, gh, ssh, xargs, a shell variable, a redirect it may follow) gets no destination,
# so no session button.
#
# Opt out with DEV_HOOKS_EMAIL_GUARD=false in settings env.

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/reminder-common.sh
source "$SELF_DIR/lib/reminder-common.sh"

# COMMAND is the call's arguments as JSON text; most hold no address and stop here.
reminder_pre_init DEV_HOOKS_EMAIL_GUARD '.tool_input | tostring'
case "$COMMAND" in *@* | *%40*) ;; *) exit 0 ;; esac

reminder_mktemp
printf '%s' "$INPUT" >"$REPLY"
REASON=$(
  python3 - "$REPLY" "$SELF_DIR/lib" "${DEV_HOOKS_ALLOWED_EMAILS:-}" <<'PYEOF'
import json
import re
import sys
from urllib.parse import unquote, urlparse

sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[2])
from hook_helpers import is_test_path  # noqa: E402

with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    payload = json.load(fh)
tool = payload.get("tool_name") or ""
args = payload.get("tool_input") or {}
allowed = {a.lower() for a in re.split(r"[,\s]+", sys.argv[3]) if a}

MARK = "Not on your allowed list (DEV_HOOKS_ALLOWED_EMAILS): "
DEST_MARK = "Destination: "
# An @ written as %40 counts too; scanning runs on percent-decoded text.
EMAIL = re.compile(r"(?<![\w.+$-])[\w.+-]+(?:@|%40)(?:[^\W_][\w-]*\.)+[^\W\d_]{2,}\b")
RESERVED = re.compile(r"(?:^|\.)(?:example\.(?:com|org|net)|example|test|invalid|localhost)$")
UNIT = re.compile(r"\.(?:service|socket|timer|target|mount|automount|path|slice|scope|device|swap)$")
URL_USERINFO = re.compile(r"\b([a-z][a-z0-9+.-]*://)([^/\s@:]*)(?::[^/\s@]*)?@(?=[^\s/@])", re.I)
GIT_IDENTITY = re.compile(
    r"""user\.email[\s=]+["']?[^"'\s]+|GIT_(?:AUTHOR|COMMITTER)_EMAIL=["']?[^"'\s]+"""
    r"""|--author[= ](?:"[^"]*"|'[^']*'|\S+)|^\s*[\w-]*git_email:\s*\S+""",
    re.M,
)
SSH_LOGIN = re.compile(r"(?<![\w.-])(?:ssh|mosh|sftp)(?:\s+-[\w-]+(?:\s+[^\s-]\S*)?)*\s+([\w.-]+@[\w.-]+)")
COPY_SEGMENT = re.compile(r"(?<![\w.-])(?:scp|rsync)\b[^\n|;&]*")
COPY_LOGIN = re.compile(r"(?<![\w.-])([\w.-]+@[\w.-]+):")
URL = re.compile(r"\b[a-z][a-z0-9+.-]*://", re.I)
URL_HOST = re.compile(r"\b[a-z][a-z0-9+.-]*://([^/\s\"':?#]+)", re.I)
URL_FULL = re.compile(r"\b[a-z][a-z0-9+.-]*://\S*", re.I)
VISIBLE = re.compile(r"(?<![\w.-])(?:curl|wget|xh|http|https|httpie)(?![\w.-])", re.I)
# Libraries and API clients that send; shared by the Bash and file-write checks.
LIBRARIES = (
    r"requests\.|httpx|urllib|aiohttp|http\.client|smtplib|ftplib|fetch\(|axios|\bgot\(|https?\.(?:get|request)\("
    r"|Net::HTTP|Faraday|HTTParty|open-uri|URI\.open|URLSession|\bLWP\b|HTTP::Tiny|curl_init|curl_setopt"
    r"|file_get_contents\(\s*['\"]https?|Entrez|pyalex|habanero|crossref|unpaywall|nominatim|geopy"
    r"|set_identity|edgar"
)
UNSEEN = re.compile(
    r"(?<![\w.-])(?:aria2c|lynx|w3m|links|nc|ncat|socat|telnet|ssh|scp|sftp|rsync|mosh|kubectl"
    r"|aws|gcloud|az|psql|mysql|mongosh|redis-cli|mail|mailx|msmtp|sendmail|swaks|himalaya"
    r"|send-email|gh|glab|iwr|irm|Invoke-WebRequest|Invoke-RestMethod)(?![\w.-])|" + LIBRARIES,
    re.I,
)
REDIRECTS = re.compile(r"(?<![\w-])(?:-[a-zA-Z]*L[a-zA-Z]*|--location(?:-trusted)?)(?![\w-])|(?<![\w.-])wget(?![\w.-])")
# The whole host only: localhost.run or 127.0.0.1.example.net is somewhere else.
LOCAL = re.compile(
    r"(?:\b[a-z][a-z0-9+.-]*://)?(?<![\w.-])(?:localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\])(?![\w.-])(?::\d+)?", re.I
)
HOST = re.compile(
    r"(?<![\w@./-])(?:(?:[a-z0-9-]+\.)+[a-z]{2,}|\d{1,3}(?:\.\d{1,3}){3})(?::\d+)?(?=[/?#\s\"';&|)]|$)", re.I
)
REQUEST = re.compile(
    r"""user.?agent|(?<!\w)ua\s*[:=]|\bfrom:|["']from["']|contact|mailto|[?&]email=|headers|curl|wget"""
    r"""|https?://|""" + LIBRARIES,
    re.I,
)
PROSE = re.compile(r"\.(?:md|markdown|txt|rst|html?|erb|haml|slim|liquid|eml|csv)$", re.I)
# Package metadata names its authors; it makes no requests.
MANIFEST = re.compile(
    r"(?:^|/)(?:package\.json|pyproject\.toml|setup\.(?:py|cfg)|[^/]*\.gemspec|Cargo\.toml|composer\.json"
    r"|[^/]*\.nuspec|pom\.xml|CODEOWNERS|\.mailmap|AUTHORS(?:\.\w+)?|MAINTAINERS(?:\.\w+)?|CITATION\.cff)$"
)


def readable(text):
    """Percent-decoded text with each URL's user name and password dropped (the name kept apart
    only when it is itself an address), so neither reads as user@host."""
    return unquote(URL_USERINFO.sub(lambda m: " " + m.group(2) + " " + m.group(1), text))


def counted(raw):
    """The addresses that count, lowercased, in order, once each."""
    out = []
    for found in raw:
        address = found.replace("%40", "@").lower()
        local, _, domain = address.rpartition("@")
        if (
            address in allowed
            or RESERVED.search(domain)
            or UNIT.search(domain)
            or local == "git"
            or local.startswith(("noreply", "no-reply"))
            or domain.endswith("noreply.github.com")
        ):
            continue
        if address not in out:
            out.append(address)
    return out


def addresses(text, skip=()):
    return counted(m.group(0) for m in EMAIL.finditer(text) if m.start() not in skip)


def bash(command):
    text = readable(GIT_IDENTITY.sub(" ", command)).replace("file://", " ")
    logins = {m.start(1) for m in SSH_LOGIN.finditer(text)}
    for segment in COPY_SEGMENT.finditer(text):
        logins |= {segment.start() + m.start(1) for m in COPY_LOGIN.finditer(segment.group(0))}
    found = addresses(text, logins)
    if not found or not (URL.search(text) or VISIBLE.search(text) or UNSEEN.search(text)):
        return None
    remote = LOCAL.sub(" ", text)
    if remote != text and not (URL.search(remote) or UNSEEN.search(remote) or HOST.search(remote)):
        return None  # every target is this machine
    destination = None
    if not (UNSEEN.search(remote) or REDIRECTS.search(remote) or re.search(r"\bxargs\b|\$[{(\w]|`", remote)):
        hosts = {m.group(1).lower() for m in URL_HOST.finditer(remote)}
        hosts |= {m.group(0).split(":")[0].lower() for m in HOST.finditer(URL_FULL.sub(" ", remote))}
        destination = "hosts: " + " ".join(sorted(hosts)) if hosts else None
    return found, "This command sends {} over the network, where the receiving site keeps a copy in its logs.", destination


def written(path, text):
    text = readable(text)
    if PROSE.search(path) or MANIFEST.search(path):
        lines = [line for line in text.splitlines() if REQUEST.search(line)]
    elif is_test_path(path) and not REQUEST.search(text):
        lines = []
    else:
        lines = text.splitlines()
    found = addresses("\n".join(lines))
    what = "This edit writes {} into a file, from where the code or page can send it out."
    return (found, what, "file: " + path if path else None) if found else None


if tool == "Bash":
    result = bash(args.get("command") or "")
elif tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
    parts = [args.get(k) for k in ("content", "new_string", "new_source")]
    parts += [e.get("new_string") for e in args.get("edits") or [] if isinstance(e, dict)]
    text = "\n".join(p for p in parts if isinstance(p, str))
    result = written(args.get("file_path") or args.get("notebook_path") or "", text)
elif tool == "WebFetch":
    url = args.get("url") or ""
    found = addresses(readable(url))
    host = urlparse(url).hostname
    result = (found, "This fetch puts {} in the URL it requests.", "hosts: " + host if host else None) if found else None
elif tool == "WebSearch":
    found = addresses(readable(args.get("query") or ""))
    result = (found, "This search sends {} to the search provider.", "web search") if found else None
elif tool.startswith("mcp__"):
    found = addresses(readable(json.dumps(args, ensure_ascii=False)))
    result = (found, "This call hands {} to the " + tool + " service.", "mcp: " + tool) if found else None
else:
    result = None

if result:
    found, what, destination = result
    noun = "an email address" if len(found) == 1 else "email addresses"
    reason = (
        f"{what.format(noun)} {MARK}{', '.join(found)}. "
        "Allow only if you asked for this; if a site needs a contact address, use an allowed one."
    )
    print(reason + (f" {DEST_MARK}{destination}" if destination else ""))
PYEOF
)
[ -n "$REASON" ] || exit 0

reminder_emit_decision ask "dev-hooks guard — please confirm: $REASON"

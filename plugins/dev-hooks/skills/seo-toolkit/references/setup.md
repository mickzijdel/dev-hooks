# Setting up each tool

## specification.website

No account. Either add the MCP server (tools `search`, `list_topics`, `get_topic`,
`get_checklist`, `get_categories`, `get_changes`; prompt `audit_url`):

```bash
claude mcp add --transport http --scope user specification-website https://mcp.specification.website/mcp
```

or read it over plain HTTP: append `.md` to any spec URL, or fetch
`https://specification.website/checklist.md` (the whole checklist) or `/llms-full.txt` (every
page). Cite a topic's primary sources and its `updated` date when reporting a gap.

## Plausible Cloud

1. The person signs up at plausible.io and adds the site. A 30-day trial needs no card; after
   that, plans are Starter $9, Growth $14 and Business $19 a month, priced by pageviews (Starter
   is 10k a month). Size it for the busiest month, not the average.
2. Copy the snippet from Site settings → General → Tracking into `<head>`. Outbound-link
   clicks and file downloads are toggles on that same settings page, not script changes.
3. CSP: add `https://plausible.io` to `script-src` (the script) and `connect-src` (the events
   it sends).
4. Privacy policy: name Plausible as the analytics processor.

Reading stats needs the Stats API, which only the Business plan has. Store the key in fnox
(`env-to-fnox` skill) and query through `fnox exec`, so the key is never echoed:

```bash
fnox exec -- sh -c 'curl -s https://plausible.io/api/v2/query \
  -H "Authorization: Bearer $PLAUSIBLE_API_KEY" -H "Content-Type: application/json" \
  -d "{\"site_id\":\"example.com\",\"metrics\":[\"visitors\",\"pageviews\"],\"date_range\":\"30d\",\"dimensions\":[\"event:page\"]}"'
```

`date_range` takes `day`, `7d`, `28d`, `30d`, `91d`, `month`, `6mo`, `12mo`, `year`, `all` or
ISO dates; useful dimensions are `event:page`, `visit:source`, `visit:channel`,
`visit:entry_page` and `event:goal`. The limit is 600 requests an hour.

## Google Search Console and Bing Webmaster Tools

1. Search Console: add a **Domain** property (it covers every subdomain and both protocols)
   and verify with the DNS TXT record it gives. `dig +short TXT example.com` shows whether a
   `google-site-verification` record already exists. Without access to the domain's DNS (a
   bare `*.github.io` site), add a **URL-prefix** property and verify with the HTML tag.
2. Submit the sitemap URL (for example, `/sitemap-index.xml` from `@astrojs/sitemap`).
3. Bing Webmaster Tools: sign in and choose "Import from Google Search Console". That carries
   the verification and sitemaps across.
4. For Claude to read Search Console, use OpenSEO's Search Console tools (free, once OpenSEO is
   connected), or claude-seo's `seo-google`, which needs a Google Cloud service account.

## claude-seo, claude-blog, claude-ads

Read the exact plugin ids from `claude plugin list`. They are usually
`claude-seo@agricidaniel-claude-seo`, `claude-blog@agricidaniel-blog` and
`claude-ads@ai-marketing-hub-claude-ads`.

```bash
claude plugin enable claude-seo@agricidaniel-claude-seo --scope local    # .claude/settings.local.json, gitignored
claude plugin enable claude-seo@agricidaniel-claude-seo --scope project  # .claude/settings.json, shared with the repo
```

Use `local` in a repo the person doesn't own. The plugin loads after a restart.

## OpenSEO

Hosted (openseo.so: $10/mo plus a 28% markup on DataForSEO requests). The plugin bundles the
MCP server and 12 skills; it ships no hooks or scripts.

```bash
claude plugin marketplace add every-app/open-seo
claude plugin install openseo@openseo
```

The MCP server is `https://app.openseo.so/mcp`, which signs in with OAuth on first use. For
headless runs, use an API key sent as an `Authorization: Bearer` header.

Self-hosted (Docker, or the Cloudflare free plan): the person pays DataForSEO directly with
their own API key. Follow the repo's `docs/SELF_HOSTING_DOCKER.md` or
`docs/SELF_HOSTING_CLOUDFLARE.md`. The plugin's MCP entry points at the hosted URL, so add the
instance's MCP endpoint with `claude mcp add --transport http openseo <url>` instead, and
install only the skills:

```bash
npx skills add every-app/open-seo --skill '*' --agent claude-code
```

It is a third-party plugin, so keep it pinned: don't turn on auto-update. Before updating,
diff the new commit for added hooks, scripts or network endpoints.

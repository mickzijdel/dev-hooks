---
name: seo-toolkit
description: |
  Use when doing SEO work on a website (rankings, keywords, competitors, backlinks, meta tags,
  sitemaps, structured data, Search Console, AI-search visibility, "why does nobody find my
  site"), when adding web analytics, or when starting, launching or auditing a website.
---

# SEO toolkit

This skill routes SEO jobs to the chosen tools. The method (how to audit, what good schema
looks like) lives in those tools, so don't restate it here or in the answer.

## The roster

| Job | Use | Cost |
|---|---|---|
| What a good site ships: SEO, security, privacy, performance, agent readiness | **specification.website** | Free, no account |
| Visitor analytics | **Plausible Cloud** | From $9/mo (10k pageviews); Stats API only on Business ($19/mo) |
| Which searches show the site, which pages aren't indexed | **Google Search Console + Bing Webmaster Tools** | Free |
| How to audit, write schema, do local SEO, GEO, blog content, ads | **claude-seo / claude-blog / claude-ads** plugins | Free |
| Keyword volume, rankings, competitors, backlinks, AI visibility | **OpenSEO** | Paid per request (DataForSEO); hosted $10/mo + 28% markup |

Plausible Cloud is the analytics default. Recommend it over GA4, Cloudflare Web Analytics or
GoatCounter: it sets no cookies, so it needs no consent banner. Recommend self-hosted
Plausible only when the person asks for it.

OpenSEO is the only paid data source. claude-seo's paid extensions (DataForSEO, Ahrefs, SE
Ranking, Profound, Firecrawl) cover the same data under a second bill, so don't set them up.

Setup commands and API calls for every row: `references/setup.md`.

## A new or relaunching site, in this order

1. **The spec's `required` items** before launch: `get_checklist` on the specification.website
   MCP, or fetch `https://specification.website/checklist.md`. Each item is tagged `required`,
   `recommended`, `optional` or `avoid`; report `required` gaps first, and flag any `avoid`
   item the site uses. Accessibility items: fix with the `accessibility` skill.
2. **Plausible Cloud.** The person adds the site in Plausible and copies the snippet it shows
   (Site settings → General → Tracking). Paste that snippet into `<head>`; never write the
   script tag from memory, as the format is per site. If the site sends a
   `Content-Security-Policy` header, add `https://plausible.io` to `script-src` and
   `connect-src`, or the script is silently blocked. Add a line naming Plausible to the
   privacy policy.
3. **Search Console** (a Domain property verified by DNS TXT; a URL-prefix property when the
   person doesn't control the domain's DNS, as on `*.github.io`) and submit the sitemap; then
   **Bing Webmaster Tools**, importing the site from Search Console.
4. **The spec's `recommended` items.**
5. **Content and on-page work** through claude-seo / claude-blog.

Steps 2 and 3 need accounts in the person's name. Tell them what to click; don't sign up for
them.

## SEO work on an existing site

- **Data before advice.** Ask whether Search Console is set up and who owns it. If it isn't,
  set it up first: no other SEO change can be measured without it.
- **claude-seo, claude-blog, claude-ads** are often installed but disabled. Run
  `claude plugin list`; if one is installed and disabled here, say so and offer to enable it
  for this repo (`references/setup.md`). Don't enable one without asking, or because a repo
  looks like a website.
- **Keyword, rank and competitor data → OpenSEO.** If it isn't installed, offer it (hosted or
  self-hosted). Before any call that spends credits, name the call and ask. Search Console,
  IndexNow, saved data and reports are free.
- **Overlapping skills:** OpenSEO and claude-seo both ship audit and local-SEO skills. Use
  claude-seo to analyse pages and OpenSEO for data.
- **Re-audits:** spec statuses change. Call `get_changes` with the last audit's date and
  re-check only the topics that changed.

## Pitfalls

- **Static hosts can't send headers.** GitHub Pages sets no custom response headers, so the
  spec's security-header items need a proxy or host that can (Cloudflare, Netlify `_headers`).
  Say so; don't mark them unfixable.
- **Plausible's Stats API needs the Business plan.** On Starter or Growth, ask the person for
  a CSV export from the dashboard rather than guessing traffic.

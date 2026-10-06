# Porting AISafety.com's review page

**Source:** github.com/AISafetycom/AISafety.com at commit `a8fc0e6` (5 Oct 2026). The code
is MIT-licensed: keep its copyright notice ("Copyright (c) 2026 StampyAI, Copyright (c)
2026 AISafety.com") in the ported files or a NOTICE file. Port from this commit, and diff
against `main` for later fixes.

**Stack:** Next.js (App Router) + React + CSS modules, with Airtable as the store. Its
design is in the "Queue" section of `docs/architecture.md`, and it started in PR #603.

**What's not in the repo:** the agents. Comb (discovery), Broom (maintenance), the
Secretary (email intake), the Discord intake and the chat agent all run on the owner's Mac
(`~/Queue`). The contract between them and the page is the queue row (see design-doc.md).
Write the agents for the user's sources; brief them with dev-hooks:agent-brief.

## The parts and their seams

About 16k lines. Most of it is UI that ports as is; the seams are what you rewrite.

| Path | What it does | Port |
|---|---|---|
| `src/app/admin/queue/QueueAdmin.tsx` (6k lines) + `queue.module.css` | The whole page: list, focus pane, keys, toast, tabs, search, edits, undo | **Keep.** Swap the field icons and the type-colour helpers it imports from `@/lib/event-types`, `training-types` and `funding-status` for the user's own |
| `src/app/admin/queue/SitePreview.tsx` | Renders the record with the live site's own card code, one mapper per resource page | **Replace the seam:** call the user's own card/record component. If there isn't one, render the fields the published page shows |
| `src/app/admin/queue/Chat.tsx` | Chat with the agent about the item; ```edits blocks become Apply buttons | **Keep for Phase 3.** It talks to a loopback agent (`http://127.0.0.1:<port>`, token from the API). Drop it in Phase 1 |
| `src/app/admin/queue/Position.tsx`, `FieldPicker.tsx` | Where an addition sits on a manually ordered page; edit any other field | Keep if the data has a manual order / many fields; otherwise drop |
| `src/app/admin/queue/page.tsx`, `layout.tsx` | Route + auth gate + admin header | **Replace** the gate with the user's sign-in |
| `src/app/api/admin/queue/route.ts` | GET the list (or one record, schema, page order); POST accept / reject / edit / undo | **Keep the shape;** it calls into `queue.ts` |
| `src/app/api/admin/queue/{logos,previews,preview,upload}/route.ts` | Background fill of logos and cards; picture upload | Keep `previews`; the others only matter if records carry pictures |
| `src/lib/admin/queue.ts` (1.8k lines) | Airtable reads and writes: list rows, read the target, accept (write fields, tick publish), reject, undo, sanitise edits, protected fields, agent token | **The main seam.** Re-implement `listQueue`, `getTargetFields`, `getTableSchema`, `acceptItem`, `rejectItem`, `undoItem`, `saveEdits` on the user's store. Keep `sanitiseEdits` and `PROTECTED_FIELDS` logic as is |
| `src/lib/admin/queue-needed.ts` | Required fields per page, shown in a warning colour when empty | **Rewrite the table** from the interview's rubric |
| `src/lib/admin/queue-urgent.ts` | Which items lose value by waiting (deadline within 4 days for additions, 14 for fixes) | Keep; change the date fields and windows |
| `src/lib/admin/queue-search.ts`, `queue-decline.ts`, `queue-picture.ts`, `queue-place.ts`, `queue-fable.ts` | Search; reject-reply choice; picture shapes; manual ordering; diff of what the chat agent changed | Pure, with tests beside them: copy with their `*.test.ts` |
| `src/lib/admin/auth.ts` | Google sign-in, per-area view/edit grants | **Replace** with the user's auth; keep the view-only / edit split |

Env the page reads: `AIRTABLE_TOKEN`, `AIRTABLE_BASE_ID`, `QUEUE_AGENT_SECRET` and
`QUEUE_AGENT_PORT` (chat agent; optional).

## Not on Next.js?

Keep [ui-checklist.md](ui-checklist.md) and the API shape above, and rebuild the page in
their framework. QueueAdmin.tsx is the spec: read its header comment and the dated
"Bryce, <date>: …" comments, which record why each behaviour exists.

## Trying the port before it's wired up

Add a demo-data switch (an env flag that makes `listQueue`, the target read and the
previews return fixtures, plus a fake signed-in user) so the page can be run, clicked
through and screenshotted before any real store or auth is connected. Use fictional records
in the fixtures, never real organisations. Gate the flag so it can't be set in production.

# Behaviour inventory

Mutation testing finds gaps only in code that exists and runs. It cannot see a behaviour that
no test touches at all, or a refusal nobody tests ("a member may not open the admin page"). The
inventory lists what the app promises to do and checks each promise against the tests.

## 1. List the behaviours

Take them from the code, not from the tests:

| Source | Rails | TypeScript / Node |
|---|---|---|
| Entry points | `bin/rails routes` | Next.js `app/**/page.tsx` and `route.ts`, Express/Fastify/Hono router files, tRPC procedures, CLI commands |
| Who may do what | `before_action` guards, Pundit/ActionPolicy policies, `authenticate` blocks in routes | middleware, `getServerSession`/auth checks in handlers, route guards |
| State changes | enum transitions, `!` methods that check a state | reducers, state machines (XState), status fields |
| Work off the request | jobs, mailers, scheduled tasks | queues, cron routes, webhooks |
| Edges with the outside | API clients, webhooks received, OAuth callbacks | the same |

For each, write the promise as a sentence: "a signed-out visitor is sent to sign in", "only the
owner can delete", "a cancelled order cannot be refunded twice".

## 2. Match each to a test

Rails: `scripts/route_hits.rb` does the entry-point and refusal part mechanically.

```bash
rm -rf tmp/route_hits && RUBYOPT="-r$SKILL/scripts/route_hits.rb" t
bin/rails runner $SKILL/scripts/route_hits.rb report
```

It lists routes no test reaches, and routes that tests reach but never see refused (no 401,
403 or 404, no halted `before_action`, no sign-in redirect from a routing constraint; a 422 from
an invalid form does not count). It needs forked test workers, not `parallelize(with:
:threads)`, and it leaves out engine routes, mounted Rack apps and `redirect()` routes. The
second list is the valuable one: each entry needs either a test that shows who may not use it,
or a one-line reason it is public (sign-in page, health check, webhook with its own signature
check).

Measured on a private Rails 8 app (Nov 2026, counting a 422 as a refusal, as an earlier version
did): 154 routes, 56 that no unit or integration test
reached (most were Devise pages and admin actions only system tests use) and 42 never refused,
among them several admin actions whose controllers each had their own guard and no non-admin
test. A guard in a shared base controller still needs one refusal test per controller: the bug
it guards is a controller that inherits from the wrong base.

TypeScript: no script. List the route or handler files, then for each search the tests for its
path or handler name (`rg -l "'/api/orders" tests e2e`). For each protected one, look for a test
that calls it signed out or as the wrong user and expects 401/403 or a redirect.

## 3. Act

- No test at all: add one behaviour test (a request/integration test, not a system test, unless
  the behaviour is in the browser).
- No refusal test: add one per guard and controller (or handler): signed out, and the wrong role
  or owner.
- Public on purpose: write the reason in the report.

Record what you added in the final report as before/after counts of the two lists.

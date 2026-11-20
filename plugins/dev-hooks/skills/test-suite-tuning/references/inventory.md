# Behaviour inventory

Mutation testing finds gaps only in code that exists and runs. It cannot see a behaviour that
no test touches at all, or a refusal nobody tests ("a member may not open the admin page"). The
inventory lists what the app promises to do and checks each promise against the tests.

## 1. List the behaviours

Take them from the code, not from the tests. The stack file says where each kind lives:

- **Entry points**: every way a request, a command or a message gets in.
- **Who may do what**: every guard, and the entry points behind it.
- **State changes**: transitions that are only allowed from some states.
- **Work off the request**: jobs, scheduled tasks, webhooks.
- **Edges with the outside**: API clients, webhooks received, OAuth callbacks.

For each, write the promise as a sentence: "a signed-out visitor is sent to sign in", "only the
owner can delete", "a cancelled order cannot be refunded twice".

Size the work before you start. Entry points and refusals are mechanical and come first. State
changes that already have large test files are better found by mutation testing than by
reading: leave them to it and say so in the report.

## 2. Match each to a test

Two lists come out of this step: entry points **no test reaches**, and entry points that tests
reach but **never see refused**. Only a run can produce them: a recorder that watches which
entry point each test hits and how it answered (Rails: `scripts/route_hits.rb`), or coverage of
the handler functions. A text search of the tests for each path is a first list at best; the
stack file says what it gets wrong. If your stack has no recorder, say in the report which of
the two lists you could not produce.

The second list is the valuable one. Each entry needs either a test that shows who may not use
it, or a one-line reason it is public (sign-in page, health check, webhook with its own
signature check).

A guard in a shared place (a base controller, a middleware, a layout) still needs a refusal
test per entry point: the bug it guards is the one entry point that does not pass through it (a
controller that inherits from the wrong base, a route declared without the guard).

## 3. Act

- **No refusal test.** If the app can list its own routes at run time (the stack file names
  the call), write **one table-driven refusal test over that list**: every route, called signed
  out, must refuse, except the routes on a short list in the test of those that are public on
  purpose, each with its reason. It covers a route added next month, which a test per route
  does not.
  Measured (Nov 2026, an app with 178 API routes): one such test stood in for 173 missing
  refusal tests. Where no route list exists: one signed-out test per guard and entry point.
- **Signed in but not allowed.** The table covers "signed out" only. Each guard that depends
  on a role or on ownership still needs its own test as the wrong role or the wrong owner.
- **No test at all**: add one behaviour test (a request or integration test, not a system test,
  unless the behaviour is in the browser).
- **Public on purpose**: write the reason in the report.
- **Prove each refusal test** with `hand_bug.py`: the bug is one guard removed, and the test
  must fail for it.

Record what you added in the final report as before/after counts of the two lists.

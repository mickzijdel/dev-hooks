# Status pane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `session-status` pane in the dev-hooks mod that tells Mick, at a glance, whether to step in now and on what.

**Architecture:** A pure `hooks/status-pane.ts` parses end reports, briefs and git output and derives a `PaneView` from stored turns; `register.tsx` records turns, tool counts, commits and background work into one `$.state` value through a write queue, and draws the view in a `Pane`.

**Tech Stack:** Claude Code mod API (TypeScript, JSX against `h`), `claude plugin test`, pytest for the parity pin.

**Spec:** `docs/superpowers/specs/2026-10-25-status-pane-design.md`

## Global Constraints

- Pane id and command `session-status`; title `Session status`.
- Opt-out env var `DEV_HOOKS_STATUS_PANE=false`.
- Auto-open only on surfaces `vscode` and `desktop` (shortcut: a fullscreen terminal could dock too; it gets `/session-status`).
- Caps: Your move 5, Changed 4, Running 4, Not checked 2; past a cap, one `+N more` row.
- Doing clamped to 2 lines (pane `bodyColumns` wide each).
- Work turn = an Edit/Write/MultiEdit/NotebookEdit call, or 10+ tool calls (end-report-reminder's rule).
- Precedence: stopped (red) > waiting, no-report (yellow) > working, running (blue) > done (green) > replied, interrupted, no-turns (dim).
- The only model call is the Summarize button (`$.model.fork`).
- `$` never crosses an import; `status-pane.ts` stays pure.
- No em dashes in any text the pane shows.

## Review Focus

1. A notification or CI turn ending "Your move: nothing" after a turn that asked something: the ask must survive (pinned in Task 2).
2. An end report written with bold labels, headings or "What I changed this session:": parsed like `end_report_missing` reads it (Task 1, parity pin in Task 6).
3. A reload mid-session: the stored value keeps drawing; a value of an older shape is declined, not crashed on (Task 3).
4. Parallel tool calls racing the state write: no lost counts (Task 3, the queue).
5. A long final message or a 755-character Doing line: clamped, never a wall (Task 4).

---

### Task 1: Parsers

**Files:**
- Create: `plugins/dev-hooks/hooks/status-pane.ts`
- Test: `plugins/dev-hooks/tests/status-pane.test.ts`

**Interfaces:**
- Produces:
  - `type EndReport = { status?: string; doneWhen: string[]; changed: string[]; notChecked: string[]; yourMove: string[] }`
  - `parseEndReport(text: string): EndReport | null`: null when no Status, Changed or Your move label is found. Items are bullets or the inline value; a plain continuation line joins the item above. `nothing`, `nothing yet`, `none` (any case, optional trailing dot) make an empty list. Bold/italic markup stripped from values.
  - `type Brief = { doing: string; doneWhen: string[] }`; `findBrief(texts: string[]): Brief | null`: the latest text holding both a `Doing:` and a `Done when:` label.
  - `parseCommits(text: string): { branch: string; sha: string }[]`: from `[branch sha] msg` and `[branch (root-commit) sha] msg` lines.
  - `endsOnQuestion(text: string): boolean`: last non-blank line, markup stripped, ends with `?`.
  - `END_REPORT_LABELS`: the Changed / Your move word patterns, the strings pinned against `hook_helpers._END_REPORT_LINES` in Task 6.

Label lines match like `hook_helpers.end_report_missing`: optional leading `>*_|-` and spaces, the label, optional ` this turn` / ` this session`, markup, then `:`; or a `#` heading holding only the label. Labels: Status, Done when, Changed (also `What changed`, `What I changed`), Assumed, Not checked, Your move.

- [ ] **Step 1: Write the failing tests** in `status-pane.test.ts`:
  - `parseEndReport('**Status:** Done.\n**Changed:** a.py\n**Your move:** nothing.')` → `{ status: 'Done.', changed: ['a.py'], yourMove: [], doneWhen: [], notChecked: [] }`
  - bullets: `'Your move:\n- merge it\n- say push\n'` → `yourMove: ['merge it', 'say push']`
  - heading form: `'## Changed\n- a\n## Your move\nmerge'` → `changed: ['a'], yourMove: ['merge']`
  - `'**What I changed this session:**\n- x\n**Your move:** y'` → `changed: ['x']`
  - continuation: `'Your move:\n- start a\n  new session'` → `['start a new session']`
  - `parseEndReport('Changed the hook so it fires.')` → `null`
  - `findBrief([briefText, 'later text'])` returns the brief; `findBrief(['no labels'])` → null
  - `parseCommits('[main 6fb8925] Merge x\n 2 files changed')` → `[{ branch: 'main', sha: '6fb8925' }]`; root-commit form parsed
  - `endsOnQuestion('Ok.\n\n**Shall I push?**\n')` → true; `endsOnQuestion('Done.')` → false
- [ ] **Step 2:** `claude plugin test plugins/dev-hooks`: the new file fails (module not found).
- [ ] **Step 3:** Implement the five exports in `status-pane.ts`.
- [ ] **Step 4:** `claude plugin test plugins/dev-hooks`: all pass.
- [ ] **Step 5:** Commit `feat(status-pane): parse end reports, briefs and commits`.

### Task 2: The view

**Files:**
- Modify: `plugins/dev-hooks/hooks/status-pane.ts`
- Test: `plugins/dev-hooks/tests/status-pane.test.ts`

**Interfaces:**
- Consumes: Task 1's types and parsers.
- Produces:
  - `type TurnRecord = { id: string; startedAt: number; typed: boolean; endedAt?: number; end?: 'answer' | 'aborted' | 'refusal' | 'error'; calls: number; edits: number; answer?: string; report?: EndReport | null; summary?: EndReport; summarizing?: boolean; summaryError?: string }`
  - `type RepoCommits = { repo: string; commits: number; lastCommitAt: number; lastPushAt?: number }`
  - `type BackgroundItem = { label: string; since: number }`
  - `type StatusPaneState = { turns: TurnRecord[]; brief: Brief | null; repos: RepoCommits[]; background: BackgroundItem[]; startedAt: number }`
  - `EMPTY_PANE_STATE(now: number): StatusPaneState`
  - `type PaneStateName = 'stopped' | 'waiting' | 'no-report' | 'working' | 'running' | 'done' | 'replied' | 'interrupted' | 'no-turns'`
  - `type PaneView = { state: PaneStateName; tone: 'red' | 'yellow' | 'blue' | 'green' | 'dim'; label: string; since: number; yourMove: string[]; doing?: string; doneWhen: { text: string; met: boolean | null }[]; doneWhenNote?: string; running: string[]; changed: string[]; repoLines: string[]; notChecked: string[]; canSummarize: boolean; turnCount: number }`
  - `paneView(s: StatusPaneState, extraRunning: BackgroundItem[], now: number): PaneView`: `extraRunning` is the live CI watches.
  - `isWorkTurn(t: TurnRecord): boolean`, `isTypedPrompt(text: string): boolean` (non-blank, not opening with `<task-notification>`, `<agent-message`, `<system-reminder>` or `[dev-hooks CI watch]`)
  - `capped(items: string[], cap: number): string[]` (adds `+N more`), `sinceLabel(at: number, now: number, tz?: string): string` → `since 09:05 (12 min)`

Window = turns from the last `typed` one on. Each ended turn classifies (report = `summary ?? report`): error/refusal → stopped; aborted → interrupted; report with Your move items or Status starting `Blocked` → waiting; report otherwise → done; no report and work turn → no-report; no report, no work, `endsOnQuestion(answer)` → waiting with Your move `answer the question in the chat`; else replied. An unended last turn → working. Background or `extraRunning` non-empty → running. The view's state is the highest by precedence; Your move is the union across the window, de-duplicated; Changed and Not checked come from the latest report in the window. Done when: brief criteria with `met` by position only when the latest report's Done when has the same count, each item matching `/\b(met|done|yes)\b|✓/i` (true) or `/not met|\bno\b|✗/i` (false); otherwise `met: null` and `doneWhenNote` = the report's Done when joined.

- [ ] **Step 1: Write the failing tests**, one per row of the spec's state table, built from `TurnRecord` fixtures, plus:
  - "a later turn's nothing keeps an earlier ask": window [typed turn reporting Your move `push`, notification turn reporting nothing] → `state: 'waiting'`, `yourMove: ['push']`
  - a typed prompt starts over: [old turn with ask, typed turn reporting nothing] → `done`
  - background running while an ask stands → `waiting`, `running` non-empty
  - ticks: brief 3 criteria, report `['met: a', 'met: b', 'not met: c']` → `[true, true, false]`; report of 1 item → all `null` and `doneWhenNote` set
  - `capped(['a','b','c','d','e','f'], 5)` → 5 items, last `+2 more`
- [ ] **Step 2:** run, see them fail.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run, all pass.
- [ ] **Step 5:** Commit `feat(status-pane): derive the pane's state from the session's turns`.

### Task 3: Recording

**Files:**
- Modify: `plugins/dev-hooks/hooks/register.tsx`, `plugins/dev-hooks/types/index.d.ts`
- Test: `plugins/dev-hooks/tests/status-pane-hook.test.tsx`

**Interfaces:**
- Consumes: Task 2's `StatusPaneState`, `EMPTY_PANE_STATE`, `isTypedPrompt`; `parseCommits`, `findBrief`, `parseEndReport`; `ci-watch.ts`'s `pushDir`.
- Produces: `PluginState['dev-hooks'].statusPane: Shaped<StatusPaneState>` (shape tag `status-pane-1`); `changePane($, fn: (s: StatusPaneState) => StatusPaneState): Promise<void>`, a queue like `changeFacts`.

Hooks (main loop only, `agentId === undefined`; one `on` per event, folded into existing hooks where one exists):
- `turn.start`: push a `TurnRecord` (`typed: isTypedPrompt(e.text)`); keep the last 20.
- existing generic `tool.call`: count `calls`, and `edits` for the four edit tools, on the open turn.
- existing `tool.call { tool: 'Bash' }`: after `next`, before the push check, `parseCommits(ran.text)`; repo = basename of `git -C <pushDir(e.command, e.cwd)> rev-parse --path-format=absolute --git-common-dir`'s parent, cached per dir; on a push, set `lastPushAt` on that repo.
- `turn.complete`: close the turn (`end: e.reason`, `answer: e.answer` capped at 20,000 chars, `report: parseEndReport(e.answer)`); `brief = findBrief(assistant texts of $.session.messages()) ?? brief`.
- existing `classic.Stop`, before its session check: `background` = `e.background_tasks` with status `running` or `pending` (label = description, else type) plus one row per `e.session_crons` entry.

- [ ] **Step 1: Write the failing tests** (answer `state.get`/`state.set` from a Map, as `session-facts.test.ts` answers the store): a turn.start / tool.call ×2 (one Edit) / turn.complete sequence stores one turn with `calls: 2, edits: 1, report.yourMove`; a Bash `git commit` result `[status-pane abc1234] x` stores one repo with `commits: 1`; a stored value with the wrong shape tag reads as `EMPTY_PANE_STATE`.
- [ ] **Step 2:** run, see them fail.
- [ ] **Step 3:** implement the contract, the queue and the hooks.
- [ ] **Step 4:** run the whole mod suite: all pass (the CI-watch and facts tests too).
- [ ] **Step 5:** Commit `feat(status-pane): record turns, tool counts, commits and background work`.

### Task 4: The pane

**Files:**
- Modify: `plugins/dev-hooks/hooks/register.tsx`
- Test: `plugins/dev-hooks/tests/status-pane-hook.test.tsx`

**Interfaces:**
- Consumes: `paneView`, `capped`, `sinceLabel`; the stored state; live CI watches as `BackgroundItem`s.

- `session.start` (existing hook): register `session-status`; if not opted out and `e.surface` is `vscode` or `desktop`, `void $.ui.open({ id: 'session-status', title: 'Session status' })`.
- `session.attach`: the same open for a `vscode`/`desktop` surface attaching later.
- `command.run { command: 'session-status' }`: open, `{ text: 'Session status pane opened.' }`.
- `ui.render { component: 'Pane', requestId: 'session-status' }`: draw the mockup's order (state line, Your move, Doing, Done when, Running, Changed + repo lines, Not checked, footer). Colours: red `red`, yellow `yellow`, blue `blue`, green `green`, dim `dimColor`. Doing clamped to `2 * bodyColumns` characters. Empty sections hidden, except Your move (`nothing`). Title row text `updated HH:MM` as a dim first line (the engine draws the pane title).

- [ ] **Step 1: Write the failing tests**: mount the pane on `terminal` and `vscode` for fixtures of waiting, working, no-report, done and no-turns; assert the state line text (`● Waiting on you`), a Your move row, `+N more` past the cap, the Summarize Button only in no-report, and `● No turns yet` for an empty state. Opening: a session started on `vscode` opens the pane; on `terminal` it doesn't; `DEV_HOOKS_STATUS_PANE=false` stops it.
- [ ] **Step 2:** run, see them fail.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run the mod suite; then `claude plugin validate --strict plugins/dev-hooks` and the type check (scratchpad tsconfig against the bundled types, as for the end-report work).
- [ ] **Step 5:** Commit `feat(status-pane): draw the session-status pane`.

### Task 5: Summarize and the clock

**Files:**
- Modify: `plugins/dev-hooks/hooks/register.tsx`
- Test: `plugins/dev-hooks/tests/status-pane-hook.test.tsx`

- Summarize Button `onPress`: mark the turn `summarizing`, `$.model.fork({ prompt: SUMMARY_PROMPT })`, store `parseEndReport(text)` as the turn's `summary`; on `isAnswered: false`, show `summary failed: <reason>` once. `SUMMARY_PROMPT` (exact): `Write the end report for the turn that just ended, as plain lines and nothing else: a "Status:" line, then "Your move:" with each action for the person as a "- " bullet, or "Your move: nothing".`
- A one-minute redraw while the pane is open: `$.clock.after(60_000)` chained, calling `$.ui.invalidate` for the pane's render (check the `InvalidatableEventName` union for the exact name), stopped when `$.ui.panes()` no longer lists the pane.

- [ ] **Step 1: Write the failing tests**: pressing Summarize with `model.fork` answered `{ isAnswered: true, text: 'Status: Done\nYour move:\n- push' }` turns the state to waiting with `push`; answered `{ isAnswered: false, reason: 'api-error' }` keeps no-report and shows the failure row.
- [ ] **Step 2:** run, see them fail.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run the mod suite.
- [ ] **Step 5:** Commit `feat(status-pane): summarize a turn on request, redraw each minute`.

### Task 6: Parity, docs, version, live check

**Files:**
- Modify: `tests/test_nudge_parity.py` (or a new `tests/test_status_pane_parity.py`), `plugins/dev-hooks/README.md`, `README.md`, `CLAUDE.md`, `plugins/dev-hooks/.claude-plugin/plugin.json` (2.65.0, description), and a `stateDiagram-v2` copy is not needed in the README (the spec holds it).

- [ ] **Step 1:** parity test: the TS `END_REPORT_LABELS` patterns equal `hook_helpers._END_REPORT_LINES`' values (read both sources as text, the way `test_nudge_parity.py` does).
- [ ] **Step 2:** docs: README mod table row for `/session-status` and the pane (states, sources, opt-out); root README mention; CLAUDE.md paragraph on the status pane (pure half, the queue, the parity pin).
- [ ] **Step 3:** full local CI: `uv run pytest -q`, `claude plugin test plugins/dev-hooks`, `claude plugin validate --strict` (marketplace + plugins), type check, `shfmt -d .`, `shellcheck`, `bash scripts/run-jscpd.sh python,bash`.
- [ ] **Step 4:** live check: a `claude -p --plugin-dir` run can't show a pane, so the drawing is covered by the mount tests; ask Mick to open `/session-status` in a new VS Code session after the merge and the plugin update.
- [ ] **Step 5:** Commit `feat(status-pane): docs, parity pin, dev-hooks 2.65.0`; merge to `main`; `claude plugin update dev-hooks@dev-hooks`.

import { expect, test } from 'claude-code/testing'

import {
  answerFacts,
  capped,
  EMPTY_PANE_STATE,
  endsOnQuestion,
  findBrief,
  isTypedPrompt,
  isWorkTurn,
  paneView,
  parseCommits,
  parseEndReport,
  sinceLabel,
  typedFrom,
} from '../hooks/status-pane'
import type { BackgroundItem, EndReport, StatusPaneState, TurnRecord } from '../hooks/status-pane'

const empty = { doneWhen: [], changed: [], notChecked: [], yourMove: [] }

test('parseEndReport reads bold inline labels, and "nothing" is an empty Your move', async () => {
  expect(parseEndReport('**Status:** Done.\n**Changed:** a.py\n**Your move:** nothing.')).toEqual({
    ...empty,
    status: 'Done.',
    changed: ['a.py'],
  })
})

test('parseEndReport reads bullets under a label', async () => {
  expect(parseEndReport('Your move:\n- merge it\n- say push\n')?.yourMove).toEqual(['merge it', 'say push'])
})

test('parseEndReport reads the heading form', async () => {
  const report = parseEndReport('## Changed\n- a\n\n## Your move\nmerge')
  expect(report?.changed).toEqual(['a'])
  expect(report?.yourMove).toEqual(['merge'])
})

test('parseEndReport reads "What I changed this session" as Changed', async () => {
  expect(parseEndReport('**What I changed this session:**\n- x\n**Your move:** y')?.changed).toEqual(['x'])
})

test('parseEndReport joins a continuation line to the item above', async () => {
  expect(parseEndReport('Your move:\n- start a\n  new session')?.yourMove).toEqual(['start a new session'])
})

test('parseEndReport reads every label, numbered items too', async () => {
  const text = [
    'Some prose first.',
    '',
    '**Status:** Done except the docs.',
    '**Done when:**',
    '- tests green: met',
    '- merged: not met',
    '**Changed:**',
    '1. `a.py`: new',
    '2. `b.py`: fixed',
    '**Assumed:** the default.',
    '**Not checked:** the GUI.',
    '**Your move:** answer the question above.',
  ].join('\n')
  expect(parseEndReport(text)).toEqual({
    status: 'Done except the docs.',
    doneWhen: ['tests green: met', 'merged: not met'],
    changed: ['`a.py`: new', '`b.py`: fixed'],
    notChecked: ['the GUI.'],
    yourMove: ['answer the question above.'],
  })
})

test('parseEndReport finds no report in a sentence that opens with the word', async () => {
  expect(parseEndReport('Changed the hook so it fires.\nYour move is easy.')).toBeNull()
})

test('findBrief takes the latest text holding both Doing and Done when', async () => {
  const brief = '**Doing:** a status pane.\n**Not doing:** pushing.\n**Done when:**\n- tests pass\n- it opens\n'
  expect(findBrief(['Doing: old\nDone when: old', brief, 'later text'])).toEqual({
    doing: 'a status pane.',
    doneWhen: ['tests pass', 'it opens'],
  })
  expect(findBrief(['no labels here', 'Doing: half a brief'])).toBeNull()
})

test('parseCommits reads git commit output, root commits too', async () => {
  expect(parseCommits('[main 6fb8925] Merge x\n 2 files changed, 3 insertions(+)')).toEqual([
    { branch: 'main', sha: '6fb8925' },
  ])
  expect(parseCommits('[status-pane (root-commit) abc1234] first')).toEqual([{ branch: 'status-pane', sha: 'abc1234' }])
  expect(parseCommits('nothing to commit, working tree clean')).toEqual([])
})

test('endsOnQuestion reads the last non-blank line', async () => {
  expect(endsOnQuestion('Ok.\n\n**Shall I push?**\n')).toBe(true)
  expect(endsOnQuestion('Is it?\n\nDone.')).toBe(false)
})

// ── The view ─────────────────────────────────────────────────────────────────────────
const T0 = Date.UTC(2026, 9, 25, 8, 53)
const NOW = T0 + 10 * 60_000
const report = (over: Partial<EndReport> = {}): EndReport => ({ ...empty, ...over })
const turn = ({ answer = 'ok', ...over }: Partial<TurnRecord> & { answer?: string } = {}): TurnRecord => ({
  id: 't',
  startedAt: T0,
  typed: true,
  endedAt: T0 + 60_000,
  end: 'answer',
  calls: 1,
  edits: 0,
  ...answerFacts(answer),
  report: null,
  ...over,
})
const state = (turns: TurnRecord[], over: Partial<StatusPaneState> = {}): StatusPaneState => ({
  ...EMPTY_PANE_STATE(T0),
  turns,
  turnsTotal: turns.length,
  ...over,
})
const CI: BackgroundItem = { label: 'CI dev-hooks@6fb8925', since: T0 + 2 * 60_000 }
const view = (s: StatusPaneState, extra: BackgroundItem[] = []) => paneView(s, extra, NOW)

test('each state the spec names, with its tone', async () => {
  const cases: [TurnRecord[], Partial<StatusPaneState>, string, string][] = [
    [[turn({ end: 'error' })], {}, 'stopped', 'red'],
    [[turn({ report: report({ yourMove: ['push'] }) })], {}, 'waiting', 'yellow'],
    [[turn({ report: report({ status: 'Blocked on the API key' }) })], {}, 'waiting', 'yellow'],
    [[turn({ answer: 'Shall I push?' })], {}, 'waiting', 'yellow'],
    [[turn({ edits: 1, answer: 'I fixed it.' })], {}, 'no-report', 'yellow'],
    [[turn({ endedAt: undefined, end: undefined })], {}, 'working', 'blue'],
    [[turn({ report: report() })], { background: [CI] }, 'running', 'blue'],
    [[turn({ report: report() })], {}, 'done', 'green'],
    [[turn({ answer: 'Here you go.' })], {}, 'replied', 'dim'],
    [[turn({ end: 'aborted' })], {}, 'interrupted', 'dim'],
    [[], {}, 'no-turns', 'dim'],
  ]
  for (const [turns, over, name, tone] of cases) {
    const v = view(state(turns, over))
    expect([name, v.state, v.tone]).toEqual([name, name, tone])
  }
})

test('a question with no report asks you to answer it', async () => {
  expect(view(state([turn({ answer: 'Shall I push?' })])).yourMove).toEqual(['answer the question in the chat'])
})

test("a later turn's nothing keeps an earlier ask", async () => {
  const v = view(
    state([turn({ report: report({ yourMove: ['push'] }) }), turn({ id: 'n', typed: false, report: report() })]),
  )
  expect([v.state, v.yourMove]).toEqual(['waiting', ['push']])
})

test('a typed prompt starts over', async () => {
  const v = view(state([turn({ report: report({ yourMove: ['push'] }) }), turn({ id: 'b', report: report() })]))
  expect([v.state, v.yourMove]).toEqual(['done', []])
})

test('background work running under an ask shows the ask, with the work listed', async () => {
  const v = view(state([turn({ report: report({ yourMove: ['push'] }) })], { background: [CI] }))
  expect(v.state).toBe('waiting')
  expect(v.running).toEqual(['CI dev-hooks@6fb8925 (8 min)'])
})

test('a live CI watch counts as running work', async () => {
  expect(view(state([turn({ report: report() })]), [CI]).state).toBe('running')
})

test('a summary stands in for a missing report', async () => {
  const t = turn({ edits: 1, answer: 'x', summary: report({ yourMove: ['merge'] }) })
  expect(view(state([t])).yourMove).toEqual(['merge'])
  expect(view(state([turn({ edits: 1, answer: 'x' })])).canSummarize).toBe(true)
  expect(view(state([t])).canSummarize).toBe(false)
})

test('Changed, Not checked and the last thing said come from the latest turn', async () => {
  const v = view(
    state([
      turn({ report: report({ changed: ['old'], notChecked: ['old'] }) }),
      turn({ id: 'b', typed: false, report: report({ changed: ['a', 'b'], notChecked: ['gui'] }) }),
    ]),
  )
  expect([v.changed, v.notChecked]).toEqual([['a', 'b'], ['gui']])
  expect(view(state([turn({ edits: 1, answer: 'I fixed it.\nMore.' })])).lastSaid).toBe('I fixed it.')
})

test('repo lines say how many commits and whether they were pushed', async () => {
  const repos = [
    { repo: 'dev-hooks', commits: 3, lastCommitAt: T0, lastPushAt: T0 + 1 },
    { repo: 'claude-config', commits: 1, lastCommitAt: T0 },
  ]
  expect(view(state([turn({ report: report() })], { repos })).repoLines).toEqual([
    'dev-hooks: 3 commits, pushed',
    'claude-config: 1 commit, not pushed',
  ])
})

test('Done when ticks by position only when the counts match', async () => {
  const brief = { doing: 'x', doneWhen: ['a', 'b', 'c'] }
  const ticked = view(state([turn({ report: report({ doneWhen: ['met: a', 'met: b', 'not met: c'] }) })], { brief }))
  expect(ticked.doneWhen.map(d => d.met)).toEqual([true, true, false])
  const loose = view(state([turn({ report: report({ doneWhen: ['all met'] }) })], { brief }))
  expect(loose.doneWhen.map(d => d.met)).toEqual([null, null, null])
  expect(loose.doneWhenNote).toBe('all met')
  const working = view(state([turn({ endedAt: undefined, end: undefined })], { brief }))
  expect(working.doneWhen.map(d => d.met)).toEqual([null, null, null])
  expect(working.doing).toBe('x')
})

test('lists are capped with a "+N more" row', async () => {
  expect(capped(['a', 'b', 'c', 'd', 'e', 'f'], 5)).toEqual(['a', 'b', 'c', 'd', '+2 more'])
  expect(capped(['a', 'b'], 5)).toEqual(['a', 'b'])
  const many = view(state([turn({ report: report({ yourMove: ['1', '2', '3', '4', '5', '6', '7'] }) })]))
  expect(many.yourMove).toEqual(['1', '2', '3', '4', '+3 more'])
})

test('since reads as a clock time and an age', async () => {
  expect(sinceLabel(T0, T0 + 12 * 60_000, 'UTC')).toBe('since 08:53 (12 min)')
  expect(sinceLabel(T0, T0 + 20_000, 'UTC')).toBe('since 08:53 (just now)')
  expect(sinceLabel(T0, T0 + 65 * 60_000, 'UTC')).toBe('since 08:53 (1 h 5 min)')
})

test('a typed prompt is one the person wrote, not a notification', async () => {
  expect(['push!', '', '<task-notification>x', '[dev-hooks CI watch] x', '<agent-message from="a">'].map(isTypedPrompt)).toEqual(
    [true, false, false, false, false],
  )
})

test('a work turn edited a file or made 10 tool calls', async () => {
  expect([turn({ edits: 1 }), turn({ calls: 10 }), turn({ calls: 9 })].map(isWorkTurn)).toEqual([true, true, false])
})

test('Stopped names the stopped turn, even when a later turn ran', async () => {
  expect(view(state([turn({ end: 'refusal' }), turn({ id: 'n', typed: false, report: report() })])).label).toBe(
    'Stopped: refused',
  )
  expect(view(state([turn({ end: 'error' })])).label).toBe('Stopped: API error')
})

// ── Found by the final review ────────────────────────────────────────────────────────
test('a label, a blank line, then prose: the prose is the value', async () => {
  const report = parseEndReport('## Status\n\nDone.\n\n## Your move\n\nMerge the branch when CI is green.')
  expect([report?.status, report?.yourMove]).toEqual(['Done.', ['Merge the branch when CI is green.']])
  expect(parseEndReport('**Your move:**\n\nMerge the branch.')?.yourMove).toEqual(['Merge the branch.'])
})

test('emphasis is stripped from values, but not from names', async () => {
  expect(parseEndReport('**Your move:** **nothing**.')?.yourMove).toEqual([])
  expect(parseEndReport('**Your move:** *nothing*')?.yourMove).toEqual([])
  expect(parseEndReport('**Status:** **Blocked** on the key\n**Your move:** x')?.status).toBe('Blocked on the key')
  expect(parseEndReport('**Changed:** `a_b.py` and snake_case_names\n**Your move:** x')?.changed).toEqual([
    '`a_b.py` and snake_case_names',
  ])
})

test('a report with no Your move line leaves it unknown, not empty', async () => {
  expect(parseEndReport('**Status:** Done.\n**Changed:** a.py')?.yourMove).toBeUndefined()
})

test('a prompt is typed by its origin; text is the fallback when none arrived', async () => {
  expect(['composer', 'sdk', 'bridge'].map(o => typedFrom(o, 'x'))).toEqual([true, true, true])
  expect(['scheduled-trigger', 'task-notification', 'peer', 'auto-continuation'].map(o => typedFrom(o, 'x'))).toEqual([
    false,
    false,
    false,
    false,
  ])
  expect([typedFrom(undefined, 'go'), typedFrom(undefined, '')]).toEqual([true, false])
})

test('the pane keeps the first line and whether the answer ends on a question', async () => {
  expect(answerFacts('First line.\n\nMore.\n\nShall I push?')).toEqual({ lastSaid: 'First line.', asksQuestion: true })
  expect(answerFacts('x'.repeat(20_000)).lastSaid?.length).toBeLessThanOrEqual(300)
})

test('a question after a report that says nothing for you is still a question', async () => {
  const v = view(state([turn({ answer: '**Your move:** nothing.\n\nWant me to push it too?', report: report() })]))
  expect([v.state, v.yourMove]).toEqual(['waiting', ['answer the question in the chat']])
})

test('a report with no Your move line never reads as Done', async () => {
  const partial = { ...report({ changed: ['a.py'] }), yourMove: undefined }
  expect(view(state([turn({ report: partial })])).state).toBe('replied')
  expect(view(state([turn({ edits: 1, report: partial })])).state).toBe('no-report')
})

test('a turn waiting on a question in the chat is waiting, not working', async () => {
  const v = view(state([turn({ endedAt: undefined, end: undefined, asking: true })]))
  expect([v.state, v.yourMove]).toEqual(['waiting', ['answer the question in the chat']])
})

test("a later turn's report covers an earlier turn that left none", async () => {
  const v = view(state([turn({ edits: 1, answer: 'Saved.' }), turn({ id: 'c', typed: false, report: report() })]))
  expect([v.state, v.canSummarize]).toEqual(['done', false])
})

test('Done when reads the verdict word, before or after the criterion', async () => {
  const brief = { doing: 'x', doneWhen: ['a', 'b', 'c'] }
  const ticks = (items: string[]) =>
    view(state([turn({ report: report({ doneWhen: items }) })], { brief })).doneWhen.map(d => d.met)
  expect(ticks(['Met: no lost counts', 'tests green: met', 'not met: c'])).toEqual([true, true, false])
  expect(ticks(['partly met: vscode only', 'met', 'met'])).toEqual([null, null, null])
})

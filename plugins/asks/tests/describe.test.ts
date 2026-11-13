import { expect, test } from 'claude-code/testing'

import { ago, describe, inOrder, labelled } from '../hooks/describe'

const ask = (move: string, context = '', changed = '', topic?: string) => ({ move, context, changed, topic })

test('a move with numbered options is a choice, with label and consequence split', async () => {
  const d = describe(
    ask(
      'Look at the Asks pane, then choose. I recommend option 1.\n1. Load the mod everywhere — adds one settings line.\n2. The card still needs work: send a screenshot.\n3. Stop here for now.',
      '**Not checked:** the pane with two real sessions.',
      'Nothing this turn.',
    ),
  )
  expect(d.kind).toBe('choose')
  expect(d.question).toBe('Look at the Asks pane, then choose.')
  expect(d.recommend).toBe('Option 1.')
  expect(d.recommended).toEqual([1])
  expect(d.options).toEqual([
    { number: 1, label: 'Load the mod everywhere', consequence: 'adds one settings line.' },
    { number: 2, label: 'The card still needs work', consequence: 'send a screenshot.' },
    { number: 3, label: 'Stop here for now.', consequence: '' },
  ])
  // "Changed: nothing" says nothing, so it is no fact row.
  expect(d.facts).toEqual([{ key: 'NOT CHECKED', value: 'the pane with two real sessions.' }])
})

test('a yes-or-no question is a go-ahead, with its steering lines kept out of the facts', async () => {
  const d = describe(
    ask(
      'Run the import migration on the rehearsal copy?\n**Recommend:** Yes. This copy is not production.\n**Blocks:** 2 more tasks',
      '**Undo:** Easy. Drop the two columns.\n\n**Risk:** The copy is shared with the data team.',
      'Migration script written.',
    ),
  )
  expect(d.kind).toBe('go-ahead')
  expect(d.question).toBe('Run the import migration on the rehearsal copy?')
  expect(d.body).toBe('')
  expect(d.recommend).toBe('Yes. This copy is not production.')
  expect(d.blocks).toBe('2 more tasks')
  expect(d.facts.map(f => f.key)).toEqual(['RISK', 'UNDO', 'CHANGED'])
})

test('a command to run is a task for the person', async () => {
  const d = describe(ask('Run `gh auth login` in a terminal, then say "done". The token expired.'))
  expect(d.kind).toBe('do')
  expect(d.command).toBe('gh auth login')
  expect(d.question).toBe('Run `gh auth login` in a terminal, then say "done".')
  expect(d.body).toBe('The token expired.')
})

test('finished work with a pull request link is a review', async () => {
  const d = describe(ask('Review the draft PR https://github.com/acme/app/pull/42 when you have time.'))
  expect(d.kind).toBe('review')
  expect(d.url).toBe('https://github.com/acme/app/pull/42')
})

test('a stated kind wins, and a long first sentence gives way to the subject line', async () => {
  const long = `Decide ${'whether this very long sentence should really be the heading of the memo '.repeat(2)}now.`
  const d = describe(ask(`${long}\n**Kind:** review`, '', '', 'Memo heading length'))
  expect(d.kind).toBe('review')
  expect(d.question).toBe('Memo heading length')
  expect(d.body).toBe(long)
})

test('an ask that is not a yes-or-no question gets no Yes button: it is answered in words', async () => {
  expect(describe(ask('Send a screenshot and say what is unclear.')).kind).toBe('reply')
  expect(describe(ask('Look at the pane after this reply.')).kind).toBe('reply')
  // A stated recommendation of yes or no makes it a go-ahead even with no question mark.
  expect(describe(ask('Decide if I may add the settings line.\n**Recommend:** Yes. It is one line.')).kind).toBe('go-ahead')
  expect(describe(ask('Decide on the settings line (recommended: yes).')).kind).toBe('reply')
})

test('an open question cannot be answered with yes, so it gets no Yes button either', async () => {
  expect(describe(ask('Which database should I use?')).kind).toBe('reply')
  expect(describe(ask('How should the export handle empty rows?')).kind).toBe('reply')
  expect(describe(ask('Should I copy the table or rename it?')).kind).toBe('reply')
  expect(describe(ask('Should I rename the table?')).kind).toBe('go-ahead')
})

test('a numbered list of steps is not a choice, and its lines stay in view', async () => {
  const d = describe(ask('Two steps for you:\n1. Type `/asks` in this session.\n2. Send me a screenshot.'))
  expect(d.kind).toBe('reply')
  expect(d.options).toEqual([])
  expect(d.body).toBe('1. Type `/asks` in this session.\n2. Send me a screenshot.')
})

test('a question is a go-ahead even when it names a command or a pull request', async () => {
  expect(describe(ask('Run `pnpm migrate` on the rehearsal copy?')).kind).toBe('go-ahead')
  expect(describe(ask('Merge https://github.com/acme/app/pull/42 now?')).kind).toBe('go-ahead')
})

test('a fact that starts with "no" but says something is shown', async () => {
  const d = describe(
    ask('Send the emails?', '**Undo:** No way back once the emails are sent.\n\n**Risk:** None.\n\n**Blocks:** Nothing yet.'),
  )
  expect(d.facts).toEqual([{ key: 'UNDO', value: 'No way back once the emails are sent.' }])
  expect(d.blocks).toBe('')
})

test('a label value runs on over its following lines', async () => {
  const { facts, rest } = labelled('Do it.\n**Risk:** shared copy,\nso tell Robin first.\n\nMore text.')
  expect(facts).toEqual([{ key: 'RISK', value: 'shared copy, so tell Robin first.' }])
  expect(rest).toBe('Do it.\n\nMore text.')
})

test('asks that block other work come first, then the oldest', async () => {
  const a = { ...ask('A?'), at: 1 }
  const b = { ...ask('B?\n**Blocks:** the push'), at: 3 }
  const c = { ...ask('C?\n**Blocks:** nothing'), at: 2 }
  expect(inOrder([a, c, b]).map(x => x.move[0])).toEqual(['B', 'A', 'C'])
})

test('a length of time is said in the fewest words', async () => {
  expect(ago(20_000)).toBe('now')
  expect(ago(12 * 60_000)).toBe('12 min')
  expect(ago(130 * 60_000)).toBe('2 h 10 min')
  expect(ago(120 * 60_000)).toBe('2 h')
  expect(ago(50 * 3_600_000)).toBe('2 d')
})

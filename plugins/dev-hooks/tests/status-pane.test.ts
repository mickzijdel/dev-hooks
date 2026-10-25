import { expect, test } from 'claude-code/testing'

import { endsOnQuestion, findBrief, parseCommits, parseEndReport } from '../hooks/status-pane'

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

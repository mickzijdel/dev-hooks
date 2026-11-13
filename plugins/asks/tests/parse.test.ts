import { expect, test } from 'claude-code/testing'

import { moveChoice, parseAsk, questionText, sessionName, statesMove, titleFrom } from '../hooks/parse'

const REPLY = [
  '**Your move:** Choose a route. I recommend route 1.',
  '1. Do the first thing.',
  '2. Do the second thing.',
  '',
  '**Changed:** Nothing. Research only.',
  '',
  '**Risk:** The plugin sees every tool call.',
  '',
  'Details (skippable)',
  '',
  '**Your move:** this one is below the line and must not be read.',
].join('\n')

test('reads the move, the change and the context above the details line', async () => {
  const ask = parseAsk(REPLY)
  expect(ask?.move).toBe('Choose a route. I recommend route 1.\n1. Do the first thing.\n2. Do the second thing.')
  expect(ask?.changed).toBe('Nothing. Research only.')
  expect(ask?.context).toBe('**Risk:** The plugin sees every tool call.')
})

test('a move of nothing, or no move, is no ask', async () => {
  expect(parseAsk('**Your move:** Nothing.\n\n**Changed:** One file.')).toBe(null)
  expect(parseAsk('**Your move:** nothing\n')).toBe(null)
  expect(parseAsk('Here is the answer to your question.')).toBe(null)
})

test('a move with no change line keeps the whole move', async () => {
  expect(parseAsk('**Your move:** Run the tests.')?.move).toBe('Run the tests.')
})

test('a move with a numbered list gives its intro, options and recommended numbers', async () => {
  const move = [
    'Choose what to try. I recommend 1 and 2 together.',
    '1. Run `claude agents`.',
    '   It lists all sessions.',
    '2. Let me read the source.',
    '3. Optional: examine the other tool.',
  ].join('\n')
  const choice = moveChoice(move)
  expect(choice.intro).toBe('Choose what to try. I recommend 1 and 2 together.')
  expect(choice.options.map(o => o.text)).toEqual([
    'Run `claude agents`. It lists all sessions.',
    'Let me read the source.',
    'Optional: examine the other tool.',
  ])
  expect(choice.recommended).toEqual([1, 2])
})

test('a move that only starts with "none" is still an ask', async () => {
  expect(parseAsk('**Your move:** None of the tests pass. Decide what to drop.')?.move).toBe(
    'None of the tests pass. Decide what to drop.',
  )
  expect(parseAsk('**Your move:** None.')).toBe(null)
  expect(parseAsk('**Your move:** Nothing is required yet.')).toBe(null)
})

test('options are numbered by position, and only numbers right after "recommend" count', async () => {
  const restarted = moveChoice('Pick one. I recommend 2, not the 1 from yesterday.\n1. First\n2. Second\n2. Third')
  expect(restarted.options.map(o => o.number)).toEqual([1, 2, 3])
  expect(restarted.recommended).toEqual([2])
  expect(moveChoice('Choose. I do not recommend this before 3 pm.\n1. A\n2. B\n3. C').recommended).toEqual([])
})

test('text after the list is not part of the last option', async () => {
  const choice = moveChoice('Choose a route.\n1. Copy the table.\n2. Rename the table.\n\nI recommend 2. Tell me if neither fits.')
  expect(choice.options.map(o => o.text)).toEqual(['Copy the table.', 'Rename the table.'])
  expect(choice.intro).toBe('Choose a route.\nI recommend 2. Tell me if neither fits.')
  expect(choice.recommended).toEqual([2])
})

test('the move label counts only at the start of a line, not quoted inside a sentence', async () => {
  expect(parseAsk('The pane reads the **Your move:** block of each reply.')).toBe(null)
  expect(statesMove('The pane reads the **Your move:** block of each reply.')).toBe(false)
  expect(parseAsk('Done.\n\n**Your move:** Ship it?')?.move).toBe('Ship it?')
})

test('a move with no list has no options', async () => {
  const choice = moveChoice('Decide on the settings line (recommended: yes).')
  expect(choice.intro).toBe('Decide on the settings line (recommended: yes).')
  expect(choice.options).toEqual([])
  expect(choice.recommended).toEqual([])
})

test('a session name leaves out reminders and tags, and is cut short', async () => {
  const first = '<system-reminder>\nThe user started this session without a folder.\n</system-reminder>\nI want a UI for asks'
  expect(sessionName(first, 60)).toBe('I want a UI for asks')
  expect(sessionName('<command-name>/asks</command-name>', 60)).toBe('')
  expect(sessionName('a'.repeat(70), 60)).toBe(`${'a'.repeat(60)}…`)
})

test('the title is the last one the transcript holds', async () => {
  expect(titleFrom('"customTitle":"Old"\n"customTitle":"Claude Code \\"asks\\" UI"\n')).toBe('Claude Code "asks" UI')
  expect(titleFrom('')).toBe('')
  expect(titleFrom('not json')).toBe('')
})

test('the context leaves out the brief link', async () => {
  const reply = '**Your move:** Do it.\n\n**Changed:** One file.\n\n**Risk:** None.\n\nBrief: [brief.md](brief.md)'
  expect(parseAsk(reply)?.context).toBe('**Risk:** None.')
})

test('a question lists its options', async () => {
  const input = { questions: [{ question: 'Which one?', options: [{ label: 'A' }, { label: 'B' }] }] }
  expect(questionText(input)).toBe('Which one?\n- A\n- B')
  expect(questionText({})).toBe('')
})

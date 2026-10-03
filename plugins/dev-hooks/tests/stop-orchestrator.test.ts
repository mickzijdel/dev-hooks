import { expect, test } from 'claude-code/testing'

import { mergeBlocks, stopHooks, stopReason } from '../hooks/register'

const ran = (exitCode: number, stdout = '', stderr = '') => ({ exitCode, stdout, stderr })

test('stopHooks lists every Stop command in order, with its timeout', async () => {
  const hooks = {
    hooks: {
      PostToolUse: [{ hooks: [{ type: 'command', command: 'bash lint.sh' }] }],
      Stop: [
        {
          matcher: '',
          hooks: [
            { type: 'command', command: 'bash a.sh' },
            { type: 'command', command: 'bash b.sh', timeout: 120 },
          ],
        },
        { hooks: [{ type: 'command', command: 'bash c.sh' }] },
      ],
    },
  }

  expect(stopHooks(hooks)).toEqual([
    { command: 'bash a.sh', timeoutMs: 600_000 },
    { command: 'bash b.sh', timeoutMs: 120_000 },
    { command: 'bash c.sh', timeoutMs: 600_000 },
  ])
})

test('stopHooks skips non-command hooks and tolerates a config with no Stop', async () => {
  expect(stopHooks({ hooks: { Stop: [{ hooks: [{ type: 'prompt', prompt: 'x' }] }] } })).toEqual([])
  expect(stopHooks({ modules: ['./register.tsx'] })).toEqual([])
  expect(stopHooks(null)).toEqual([])
})

test('stopReason reads a decision:block JSON answer', async () => {
  expect(stopReason(ran(0, '{"decision":"block","reason":"[review-reminder] run a review"}\n'))).toBe(
    '[review-reminder] run a review',
  )
})

test('stopReason reads exit 2 as a block with stderr as the reason', async () => {
  expect(stopReason(ran(2, '', 'tests failed\n'))).toBe('tests failed')
})

test('stopReason treats silence, other JSON, plain text and errors as no block', async () => {
  expect(stopReason(ran(0))).toBeNull()
  expect(stopReason(ran(0, '{"continue":true}'))).toBeNull()
  expect(stopReason(ran(0, 'Checking things...\n'))).toBeNull()
  expect(stopReason(ran(1, '', 'jq: not found'))).toBeNull()
  expect(stopReason(ran(2, '', '   '))).toBeNull()
})

test('mergeBlocks joins the reasons into one block after any block from beneath', async () => {
  expect(mergeBlocks(undefined, [])).toBeUndefined()
  expect(mergeBlocks('voice', [])).toBe('voice')
  expect(mergeBlocks(undefined, ['a', 'b'])).toBe('a\n\nb')
  expect(mergeBlocks('voice', ['a'])).toBe('voice\n\na')
})

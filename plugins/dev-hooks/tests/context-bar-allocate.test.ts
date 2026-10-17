import { expect, test } from 'claude-code/testing'

import { allocate } from '../hooks/register'

const seg = (tokens: number) => ({ name: 'x', tokens, color: 'text', kind: 'used' as const })

test('allocate fills exactly the bar width', async () => {
  const cells = allocate([seg(15000), seg(3000), seg(120000), seg(62000)], 57)
  expect(cells.reduce((a, b) => a + b, 0)).toBe(57)
})

test('allocate is proportional', async () => {
  expect(allocate([seg(1), seg(3)], 8)).toEqual([2, 6])
})

test('allocate with no tokens draws nothing', async () => {
  expect(allocate([seg(0), seg(0)], 20)).toEqual([0, 0])
})

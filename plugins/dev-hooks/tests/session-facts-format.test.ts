import { expect, test } from 'claude-code/testing'

import { ago, formatFacts } from '../hooks/register'
import type { Facts } from '../types'

const NOW = 1_791_015_800_000
const MIN = 60_000

test('ago reads as a short relative time', async () => {
  expect(ago(NOW - 20_000, NOW)).toBe('just now')
  expect(ago(NOW - 7 * MIN, NOW)).toBe('7m ago')
  expect(ago(NOW - 75 * MIN, NOW)).toBe('1h15m ago')
  expect(ago(NOW - 26 * 60 * MIN, NOW)).toBe('1d ago')
})

test('formatFacts summarises a session in plain text with relative times', async () => {
  const facts: Facts = {
    updatedAt: NOW - 10_000,
    skills: [{ skill: 'dev-hooks:compress-comments', at: NOW - 3 * MIN }],
    agents: [{ description: 'Look up default hook timeout', subagentType: 'claude-code-guide', at: NOW - 40 * MIN }],
    repos: [
      { root: null, files: ['/home/u/.claude/memory/x.md'], added: 4, bySubagent: 0 },
      {
        root: '/home/u/code/app',
        files: ['/home/u/code/app/tests/a.py', '/home/u/code/app/lib/b.sh'],
        added: 202,
        bySubagent: 1,
      },
    ],
    stops: [
      { at: NOW - 30 * MIN, block: null },
      { at: NOW - 2 * MIN, block: '[review-reminder] You changed code this session.\nRun a review.' },
    ],
  }

  expect(formatFacts(facts, NOW, '/home/u')).toBe(
    [
      'Session facts · updated just now',
      '',
      'Skills (1)',
      '  3m ago   dev-hooks:compress-comments',
      '',
      'Subagents (1)',
      '  40m ago  claude-code-guide · Look up default hook timeout',
      '',
      'Edits via Edit/Write (Bash-made edits are not tracked)',
      '  ~/code/app · +202 lines · 2 files · 1 edit by subagents',
      '    tests/a.py',
      '    lib/b.sh',
      '  outside any repo · +4 lines · 1 file',
      '    ~/.claude/memory/x.md',
      '',
      'Stops (2, 1 blocked)',
      '  2m ago   [review-reminder] You changed code this session.',
      '',
      '/session-facts json prints the raw record; /session-facts nudges, Stop-nudge outcomes across sessions.',
    ].join('\n'),
  )
})

test('formatFacts says so plainly when nothing has been recorded', async () => {
  const empty: Facts = { updatedAt: 0, skills: [], agents: [], repos: [], stops: [] }

  expect(formatFacts(empty, NOW, '/home/u')).toBe(
    [
      'Session facts · nothing recorded yet',
      '',
      'Skills: none',
      'Subagents: none',
      'Edits via Edit/Write (Bash-made edits are not tracked): none',
      'Stops: none',
      '',
      '/session-facts json prints the raw record; /session-facts nudges, Stop-nudge outcomes across sessions.',
    ].join('\n'),
  )
})

test('formatFacts lists only the stops that blocked', async () => {
  const facts: Facts = {
    updatedAt: NOW,
    skills: [],
    agents: [],
    repos: [],
    stops: [
      { at: NOW - 9 * MIN, block: null },
      { at: NOW - 8 * MIN, block: null },
    ],
  }

  expect(formatFacts(facts, NOW, '/home/u').split('\n')).toContain('Stops (2, none blocked)')
})

test('formatFacts lists this session\'s Stop nudges with their outcome once one fired', async () => {
  const facts: Facts = {
    updatedAt: NOW,
    skills: [],
    agents: [],
    repos: [],
    stops: [],
    nudges: [
      { hook: 'review-reminder', at: NOW - 5 * MIN, summary: 'x', outcome: 'acted', evidence: 'skill code-review' },
      { hook: 'memory-reminder', at: NOW - MIN, summary: 'y' },
    ],
  }

  const lines = formatFacts(facts, NOW, '/home/u').split('\n')
  expect(lines).toContain('Stop nudges (2)')
  expect(lines).toContain('  5m ago   review-reminder · acted (skill code-review)')
  expect(lines).toContain('  1m ago   memory-reminder · pending')
})

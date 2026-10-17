import { expect, test } from 'claude-code/testing'

import {
  ciNote,
  ciStatusLine,
  ciToast,
  ciVerdict,
  githubRepo,
  isDryRun,
  isGitPush,
  parsePushOutput,
  pushDir,
} from '../hooks/ci-watch'
import type { Run } from '../hooks/ci-watch'

const SHA = '762caa326fb1da9dda327189ee7b075a5677cc09'
const run = (over: Partial<Run> = {}): Run => ({
  databaseId: 37111047147,
  workflowName: 'ci',
  status: 'completed',
  conclusion: 'success',
  headSha: SHA,
  url: 'https://github.com/mickzijdel/dev-hooks/actions/runs/37111047147',
  event: 'push',
  ...over,
})

test('isGitPush matches the forms ci-watch-reminder.sh matches', async () => {
  for (const cmd of [
    'git push',
    'git push origin main',
    'git -C /repo push',
    'git commit -m x && git push -u origin feat',
    'GIT_SSH_COMMAND=ssh git push',
  ]) {
    expect(isGitPush(cmd)).toBe(true)
  }
  for (const cmd of ['git config remote.origin.pushurl x', 'git switch main', 'git pushall', 'echo git status\npush it']) {
    expect(isGitPush(cmd)).toBe(false)
  }
})

test('isDryRun spots --dry-run and -n on the push', async () => {
  expect(isDryRun('git push --dry-run origin main')).toBe(true)
  expect(isDryRun('git push -n')).toBe(true)
  expect(isDryRun('git push origin main')).toBe(false)
  expect(isDryRun('git push origin main && grep -n x f')).toBe(false)
})

test('pushDir follows git -C and a leading cd, else the cwd', async () => {
  expect(pushDir('git push', '/s')).toBe('/s')
  expect(pushDir('git -C /repo push', '/s')).toBe('/repo')
  expect(pushDir('git -C sub push origin main', '/s/')).toBe('/s/sub')
  expect(pushDir('cd "/my repo" && git push', '/s')).toBe('/my repo')
  expect(pushDir('cd ../other; git push', '/s')).toBe('/s/../other')
})

test('parsePushOutput reads the remote and every ref line git prints', async () => {
  const out = [
    'To github.com:mickzijdel/dev-hooks.git',
    '   cfe1e84..4a22bfc  HEAD -> main',
    ' + 4a22bfc...f59cb0b fix -> fix (forced update)',
    ' * [new branch]      feat -> feat',
    ' * [new tag]         v1 -> v1',
    ' - [deleted]         gone',
    ' ! [rejected]        old -> old (non-fast-forward)',
  ].join('\n')

  expect(parsePushOutput(out)).toEqual({
    remote: 'github.com:mickzijdel/dev-hooks.git',
    refs: [
      { sha: '4a22bfc', src: 'HEAD', dst: 'main' },
      { sha: 'f59cb0b', src: 'fix', dst: 'fix' },
      { src: 'feat', dst: 'feat' },
      { src: 'v1', dst: 'v1' },
    ],
  })
  expect(parsePushOutput('Everything up-to-date\n')).toEqual({ remote: undefined, refs: [] })
})

test('githubRepo reads owner/repo from every GitHub URL spelling', async () => {
  expect(githubRepo('git@github.com:mickzijdel/dev-hooks.git')).toBe('mickzijdel/dev-hooks')
  expect(githubRepo('github.com:mickzijdel/dev-hooks.git')).toBe('mickzijdel/dev-hooks')
  expect(githubRepo('https://github.com/mickzijdel/dev-hooks')).toBe('mickzijdel/dev-hooks')
  expect(githubRepo('https://x-access-token:abc@github.com/o/r.git')).toBe('o/r')
  expect(githubRepo('ssh://git@github.com/o/r.git/')).toBe('o/r')
  expect(githubRepo('git@gitlab.com:o/r.git')).toBeNull()
  expect(githubRepo('../remote.git')).toBeNull()
})

test('ciVerdict selects runs by head sha, never by recency', async () => {
  const stale = run({ headSha: 'aaaaaaa', status: 'in_progress', conclusion: '' })
  expect(ciVerdict([stale], SHA).verdict).toBe('none')
  expect(ciVerdict([stale, run()], SHA)).toEqual({ verdict: 'success', runs: [run()] })
})

test('ciVerdict waits for every run, and a failure outranks a cancellation', async () => {
  const lint = run({ workflowName: 'lint', status: 'in_progress', conclusion: '' })
  expect(ciVerdict([run(), lint], SHA).verdict).toBe('pending')
  expect(ciVerdict([run({ conclusion: 'cancelled' }), run({ conclusion: 'failure' })], SHA).verdict).toBe('failure')
  expect(ciVerdict([run({ conclusion: 'timed_out' })], SHA).verdict).toBe('failure')
  expect(ciVerdict([run({ conclusion: 'cancelled' }), run()], SHA).verdict).toBe('cancelled')
  expect(ciVerdict([run({ conclusion: 'skipped' })], SHA).verdict).toBe('success')
})

test('ciStatusLine shows each watch, and clears with none left', async () => {
  expect(ciStatusLine([])).toBeUndefined()
  expect(
    ciStatusLine([
      { repo: 'mickzijdel/dev-hooks', sha: SHA, done: 0, total: 0 },
      { repo: 'o/r', sha: 'bff62b2eb832', done: 1, total: 2 },
    ]),
  ).toBe('CI: dev-hooks@762caa3 waiting for its run · r@bff62b2 1/2 runs done')
})

test('a failure note names the failed run and how to read its log', async () => {
  const failed = run({ databaseId: 35830926133, conclusion: 'failure' })
  expect(ciToast('mickzijdel/dev-hooks', SHA, 'failure', [failed])).toBe('✗ CI failed · dev-hooks@762caa3: ci')
  const note = ciNote('mickzijdel/dev-hooks', SHA, 'failure', [failed])
  expect(note).toContain('CI FAILED')
  expect(note).toContain('gh run view 35830926133 --repo mickzijdel/dev-hooks --log-failed')
})

test('a pass and a lookup error read as such', async () => {
  expect(ciToast('mickzijdel/dev-hooks', SHA, 'success', [run()])).toBe('✓ CI passed · dev-hooks@762caa3')
  expect(ciNote('mickzijdel/dev-hooks', SHA, 'success', [run()])).toContain('CI passed.')
  expect(ciNote('o/r', SHA, 'none', [], 'gh: not logged in')).toContain("couldn't read its GitHub Actions runs (gh: not logged in)")
})

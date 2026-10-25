import { expect, test } from 'claude-code/testing'

import {
  ciNote,
  ciStatusLine,
  ciToast,
  ciVerdict,
  gitDir,
  githubRepo,
  isDryRun,
  isGitPush,
  isQuietPush,
  parsePushOutput,
  pushDir,
  pushRepositories,
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

test('isQuietPush reads -q and --quiet on the push itself', async () => {
  expect(['git push -q', 'git push --quiet origin main', 'git -C r push -q'].map(isQuietPush)).toEqual([true, true, true])
  expect(['git push', 'git commit -q && git push', 'git push origin quiet'].map(isQuietPush)).toEqual([false, false, false])
})

test('gitDir finds the directory of any git subcommand, the same way', async () => {
  expect(gitDir('git add a && git commit -m x', '/s', 'commit')).toBe('/s')
  expect(gitDir('git -C /repo commit -m x', '/s', 'commit')).toBe('/repo')
  expect(gitDir('cd .worktrees/x && git add . && git commit -m y', '/s', 'commit')).toBe('/s/.worktrees/x')
  expect(gitDir('cd /a && git -C /b push', '/s', 'push')).toBe(pushDir('cd /a && git -C /b push', '/s'))
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

  expect(parsePushOutput(out)).toEqual([
    {
      remote: 'github.com:mickzijdel/dev-hooks.git',
      refs: [
        { sha: '4a22bfc', src: 'HEAD', dst: 'main' },
        { sha: 'f59cb0b', src: 'fix', dst: 'fix' },
        { src: 'feat', dst: 'feat' },
        { src: 'v1', dst: 'v1' },
      ],
    },
  ])
  expect(parsePushOutput('Everything up-to-date\n')).toEqual([])
})

test('parsePushOutput gives each push its own remote, and none where the To line was cut', async () => {
  const out = [
    '   1111111..2222222  main -> main',
    'To github.com:o/fork.git',
    '   3333333..4444444  main -> main',
    'To github.com:o/upstream.git',
    '   5555555..6666666  main -> main',
  ].join('\n')

  expect(parsePushOutput(out)).toEqual([
    { refs: [{ sha: '2222222', src: 'main', dst: 'main' }] },
    { remote: 'github.com:o/fork.git', refs: [{ sha: '4444444', src: 'main', dst: 'main' }] },
    { remote: 'github.com:o/upstream.git', refs: [{ sha: '6666666', src: 'main', dst: 'main' }] },
  ])
})

test('pushRepositories reads the repository each push names, null for a bare push', async () => {
  expect(pushRepositories('git push')).toEqual([null])
  expect(pushRepositories('git push 2>&1 | tail -1')).toEqual([null])
  expect(pushRepositories('git push upstream main 2>&1 | tail -1')).toEqual(['upstream'])
  expect(pushRepositories('git push -u --force-with-lease origin feat')).toEqual(['origin'])
  expect(pushRepositories('git push -o ci.skip upstream main')).toEqual(['upstream'])
  expect(pushRepositories('git push -- upstream main')).toEqual(['upstream'])
  expect(pushRepositories('git -C /repo push >/dev/null')).toEqual([null])
  expect(pushRepositories('git log --oneline upstream/main..main | cat && git push upstream main 2>&1 | tail -1')).toEqual(['upstream'])
  expect(pushRepositories('git push origin main && git push "upstream" main')).toEqual(['origin', 'upstream'])
  expect(pushRepositories('git -c push.default=current push git@github.com:o/r.git')).toEqual(['git@github.com:o/r.git'])
  expect(pushRepositories('(cd sub && git push upstream)')).toEqual(['upstream'])
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

import type { On, PreToolUseResult } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'
import type { Engine, MockClock } from 'claude-code/testing'

import { commandTimeout, guardQuestion, guardTimeoutReason, isGuardAsk } from '../hooks/register'

const GUARD_ASK = "dev-hooks guard — please confirm: You're about to push the `main` branch directly."
const COMMAND = 'git push origin main'

// Stands in for the command hooks beneath (the guard's verdict), the person answering
// the dialog, and the tool itself; records what reached each.
function world(on: On, verdict: PreToolUseResult, answer: string | Error) {
  const seen = { asked: [] as string[], ran: 0 }
  on('classic.PreToolUse', () => verdict)
  on('tool.call', { tool: 'AskUserQuestion' }, (_$, e) => {
    const question = e.questions[0]?.question ?? ''
    seen.asked.push(question)
    if (answer instanceof Error) return { deny: answer.message }
    return { result: { questions: e.questions, answers: { [question]: answer } }, text: answer }
  })
  on('tool.call', { tool: 'Bash' }, () => {
    seen.ran += 1
    return { result: { stdout: 'ok', stderr: '', interrupted: false }, text: 'ok' }
  })
  return seen
}

test('isGuardAsk recognises only the guard’s own questions', async () => {
  expect(isGuardAsk(GUARD_ASK)).toBe(true)
  expect(isGuardAsk('dev-hooks guard — Printing `.env` puts a secret in the transcript.')).toBe(true)
  expect(isGuardAsk('Some other hook wants a confirmation')).toBe(false)
  expect(isGuardAsk(undefined)).toBe(false)
})

test('guardQuestion shows the reason and the command, and ends as a question', async () => {
  const q = guardQuestion(GUARD_ASK, COMMAND)
  expect(q).toContain("You're about to push the `main` branch directly.")
  expect(q).toContain(COMMAND)
  expect(q.endsWith('?')).toBe(true)
  expect(q.startsWith('dev-hooks guard')).toBe(false)
})

test('guardQuestion shortens a very long command', async () => {
  const q = guardQuestion(GUARD_ASK, `echo ${'x'.repeat(2000)}`)
  expect(q.length).toBeLessThan(800)
})

test('a guard question goes to the person, and Allow lets the command run', async ($, on) => {
  const seen = world(on, { ask: GUARD_ASK }, 'Allow')

  const ran = await $.tool.call({ tool: 'Bash', command: COMMAND })

  expect(seen.asked).toHaveLength(1)
  expect(seen.ran).toBe(1)
  expect(ran.deny).toBeUndefined()
  expect(ran.isError).toBeFalsy()
})

test('Deny refuses the command and tells Claude why', async ($, on) => {
  const seen = world(on, { ask: GUARD_ASK }, 'Deny')

  const ran = await $.tool.call({ tool: 'Bash', command: COMMAND })

  expect(seen.ran).toBe(0)
  expect(String(ran.text ?? ran.deny)).toContain('declined')
})

test('a question from another hook is left to the normal permission flow', async ($, on) => {
  const seen = world(on, { ask: 'Some other hook wants a confirmation' }, 'Allow')

  await $.tool.call({ tool: 'Bash', command: COMMAND })

  expect(seen.asked).toHaveLength(0)
})

test('a hard deny stays a deny and never reaches the person', async ($, on) => {
  const seen = world(on, { deny: 'BLOCKED by dev-hooks guard: rm -rf /' }, 'Allow')

  const ran = await $.tool.call({ tool: 'Bash', command: 'rm -rf /' })

  expect(seen.asked).toHaveLength(0)
  expect(seen.ran).toBe(0)
  expect(String(ran.text ?? ran.deny)).toContain('BLOCKED')
})

test('when the dialog cannot be answered, the guard’s question stands', async ($, on) => {
  const seen = world(on, { ask: GUARD_ASK }, new Error('no one to ask'))

  const ran = await $.tool.call({ tool: 'Bash', command: COMMAND })

  expect(seen.asked).toHaveLength(1)
  // The original `ask` goes on to the normal permission flow (the kit lets it through).
  expect(seen.ran).toBe(1)
  expect(ran.deny).toBeUndefined()
})

test('in an interactive session a dismissed dialog refuses, not falls back to auto mode', async ($, on) => {
  const seen = world(on, { ask: GUARD_ASK }, new Error('dismissed'))
  // session.start's other work, answered so it reaches the end.
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('session.id', () => ({ value: 's1' }))
  on('store.keys', () => ({ value: [] }))
  on('store.get', () => ({ value: undefined }))
  on('fs.read', () => ({ value: '{}' }))
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })

  const ran = await $.tool.call({ tool: 'Bash', command: COMMAND })

  expect(seen.ran).toBe(0)
  expect(String(ran.text ?? ran.deny)).toContain('dismissed')
})

const MAIN_ASK =
  "dev-hooks guard — please confirm: You're about to commit the `main` branch directly. The safer habit is to make changes on a separate branch and open a pull request, so `main` always stays working. Confirm if you really want to change `main` directly."

// The person never answers: the dialog's call stays pending.
function unanswered(on: On, verdict: PreToolUseResult) {
  const seen = { ran: 0 }
  on('classic.PreToolUse', () => verdict)
  on('tool.call', { tool: 'AskUserQuestion' }, () => new Promise<never>(() => {}))
  on('tool.call', { tool: 'Bash' }, () => {
    seen.ran += 1
    return { result: { stdout: 'ok', stderr: '', interrupted: false }, text: 'ok' }
  })
  return seen
}

test('guardTimeoutReason sends a main-branch change to a worktree', async () => {
  expect(guardTimeoutReason(MAIN_ASK, 60)).toContain('worktree')
  expect(guardTimeoutReason(MAIN_ASK, 120)).toContain('120s')
  expect(guardTimeoutReason(GUARD_ASK.replace('push the `main` branch directly', 'print a secret'), 60)).not.toContain('worktree')
})

test('an unanswered dialog refuses after the timeout, with what to do instead', async ($, on) => {
  const clock = mock.clock(on)
  mock.env(on, {})
  const seen = unanswered(on, { ask: MAIN_ASK })

  let settled = false
  const call = $.tool.call({ tool: 'Bash', command: 'git commit -m wip' })
  void call.then(() => (settled = true))
  await clock.advance(119_000)
  expect(settled).toBe(false)
  await clock.advance(1_000)
  const ran = await call

  expect(seen.ran).toBe(0)
  expect(String(ran.text ?? ran.deny)).toContain('worktree')
})

test('the timeout can be changed, or switched off with 0', async ($, on) => {
  const clock = mock.clock(on)
  mock.env(on, { DEV_HOOKS_GUARD_DIALOG_TIMEOUT: '5' })
  unanswered(on, { ask: MAIN_ASK })

  const call = $.tool.call({ tool: 'Bash', command: 'git commit -m wip' })
  await clock.advance(5_000)
  expect(String((await call).text)).toContain('5s')
})

test('with the timeout switched off the dialog waits as long as it takes', async ($, on) => {
  const clock = mock.clock(on)
  mock.env(on, { DEV_HOOKS_GUARD_DIALOG_TIMEOUT: '0' })
  const seen = unanswered(on, { ask: MAIN_ASK })
  let settled = false

  void $.tool.call({ tool: 'Bash', command: 'git commit -m wip' }).then(() => (settled = true))
  await clock.advance(3_600_000)

  expect(settled).toBe(false)
  expect(seen.ran).toBe(0)
})

test('commandTimeout reads a leading DEV_HOOKS_GUARD_DIALOG_TIMEOUT= on the command', async () => {
  expect(commandTimeout('DEV_HOOKS_GUARD_DIALOG_TIMEOUT=600 git push')).toBe(600)
  expect(commandTimeout('FOO=1 DEV_HOOKS_GUARD_DIALOG_TIMEOUT=0 git push')).toBe(0)
  expect(commandTimeout("cd x && DEV_HOOKS_GUARD_DIALOG_TIMEOUT='30' git commit -m y")).toBe(30)
  expect(commandTimeout('git push')).toBeUndefined()
  expect(commandTimeout('echo DEV_HOOKS_GUARD_DIALOG_TIMEOUT=5')).toBeUndefined()
  expect(commandTimeout('DEV_HOOKS_GUARD_DIALOG_TIMEOUT=soon git push')).toBeUndefined()
})

test('Claude can set the wait on the command itself, over the session setting', async ($, on) => {
  const clock = mock.clock(on)
  mock.env(on, { DEV_HOOKS_GUARD_DIALOG_TIMEOUT: '5' })
  const seen = unanswered(on, { ask: MAIN_ASK })
  let settled = false

  const call = $.tool.call({ tool: 'Bash', command: 'DEV_HOOKS_GUARD_DIALOG_TIMEOUT=600 git commit -m wip' })
  void call.then(() => (settled = true))
  await clock.advance(599_000)
  expect(settled).toBe(false)
  await clock.advance(1_000)

  expect(String((await call).text)).toContain('600s')
  expect(seen.ran).toBe(0)
})

test('the dialog tells the person how long it waits', async () => {
  expect(guardQuestion(GUARD_ASK, COMMAND, 120)).toContain('2 min')
  expect(guardQuestion(GUARD_ASK, COMMAND, 0)).not.toContain('refuse')
})

// Stands in for the engine, which draws the dialog itself: record the props the plugin
// passed down (what the person would see) and answer with the engine's own node.
type Drawn = { question?: string; options?: { label: string; description?: string }[] }
function drawDialog(on: On) {
  const drawn: Drawn[] = []
  on('ui.render', { component: 'AskUserQuestion' }, (_$, e) => {
    drawn.push((e.props.questions[0] ?? {}) as Drawn)
    return { type: 'engine', ref: 0 } as const
  })
  return drawn
}

const dialogProps = (question: string) => ({
  tool: 'AskUserQuestion',
  questions: [
    { question, header: 'dev-hooks', multiSelect: false, options: [{ label: 'Allow', description: '' }, { label: 'Deny', description: '' }] },
  ],
})

test('a dialog that timed out is redrawn as a note saying it no longer does anything', async ($, on) => {
  const clock = mock.clock(on)
  mock.env(on, {})
  unanswered(on, { ask: MAIN_ASK })
  const drawn = drawDialog(on)
  const asked = guardQuestion(MAIN_ASK, 'git commit -m wip', 120)

  const call = $.tool.call({ tool: 'Bash', command: 'git commit -m wip' })
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'dev-hooks', surface, component: 'AskUserQuestion', props: dialogProps(asked) })
    await ui.unmount()
  }
  expect(drawn.map(d => d.question)).toEqual([asked, asked])

  await clock.advance(120_000)
  await call

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'dev-hooks', surface, component: 'AskUserQuestion', props: dialogProps(asked) })
    await ui.unmount()
  }
  const note = drawn.at(-1)
  expect(note?.question).toMatch(/timed out/i)
  expect(note?.question).toContain('worktree')
  expect(note?.question).toContain('git commit -m wip')
  expect(note?.options?.map(o => o.label)).toEqual(['Close', 'OK'])
})

test('other dialogs are drawn as they were', async ($, on) => {
  const drawn = drawDialog(on)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'dev-hooks', surface, component: 'AskUserQuestion', props: dialogProps('Which colour?') })
    await ui.unmount()
  }
  expect(drawn.map(d => d.question)).toEqual(['Which colour?', 'Which colour?'])
})

// The dialog outlives its timeout: the person can still answer it later. `answer` resolves
// the pending dialog; prompts Claude was sent are collected.
function answeredLate(on: On, verdict: PreToolUseResult) {
  const w = { asked: 0, ran: [] as string[], prompts: [] as string[], answer: (_text: string) => {} }
  on('classic.PreToolUse', () => verdict)
  on('tool.call', { tool: 'AskUserQuestion' }, (_$, e) => {
    w.asked += 1
    const question = e.questions[0]?.question ?? ''
    return new Promise(resolve => {
      w.answer = text => resolve({ result: { questions: e.questions, answers: { [question]: text } }, text })
    })
  })
  on('tool.call', { tool: 'Bash' }, (_$, e) => {
    w.ran.push(e.command)
    return { result: { stdout: 'ok', stderr: '', interrupted: false }, text: 'ok' }
  })
  on('prompt.submit', (_$, e) => {
    w.prompts.push(e.text)
    return { text: e.text }
  })
  return w
}

async function timeOut($: Engine, clock: MockClock, command: string) {
  const call = $.tool.call({ tool: 'Bash', command })
  await clock.advance(120_000)
  return call
}

test('a late Allow tells Claude, and lets that exact command through once without asking', async ($, on) => {
  const clock = mock.clock(on)
  mock.env(on, {})
  const w = answeredLate(on, { ask: MAIN_ASK })

  expect(String((await timeOut($, clock, 'git commit -m wip')).text)).toContain('did not run')
  expect(w.ran).toEqual([])
  w.answer('Allow')
  await clock.advance(0)
  expect(w.prompts.at(-1)).toContain('Allow')
  expect(w.prompts.at(-1)).toContain('git commit -m wip')

  const asked = w.asked
  await $.tool.call({ tool: 'Bash', command: 'git commit -m wip' })
  expect(w.asked).toBe(asked)
  expect(w.ran).toEqual(['git commit -m wip'])

  // Used once: the next attempt asks again.
  void $.tool.call({ tool: 'Bash', command: 'git commit -m wip' })
  await clock.advance(0)
  expect(w.asked).toBe(asked + 1)
})

test('a late Allow covers only that command, and only for ten minutes', async ($, on) => {
  const clock = mock.clock(on)
  mock.env(on, {})
  const w = answeredLate(on, { ask: MAIN_ASK })

  await timeOut($, clock, 'git commit -m wip')
  w.answer('Allow')
  await clock.advance(0)
  const asked = w.asked

  void $.tool.call({ tool: 'Bash', command: 'git commit -m other' })
  await clock.advance(0)
  expect(w.asked).toBe(asked + 1)

  await clock.advance(10 * 60_000)
  void $.tool.call({ tool: 'Bash', command: 'git commit -m wip' })
  await clock.advance(0)
  expect(w.asked).toBe(asked + 2)
  expect(w.ran).toEqual([])
})

test('a late Deny or a typed reply reaches Claude', async ($, on) => {
  const clock = mock.clock(on)
  mock.env(on, {})
  const w = answeredLate(on, { ask: MAIN_ASK })

  await timeOut($, clock, 'git commit -m one')
  w.answer('Deny')
  await clock.advance(0)
  expect(w.prompts.at(-1)).toMatch(/Deny/)
  expect(w.prompts.at(-1)).toMatch(/don't run/i)

  await timeOut($, clock, 'git commit -m two')
  w.answer('Put it on a branch called fix-typo please')
  await clock.advance(0)
  expect(w.prompts.at(-1)).toContain('Put it on a branch called fix-typo please')
  expect(w.prompts.at(-1)).toContain('git commit -m two')
})

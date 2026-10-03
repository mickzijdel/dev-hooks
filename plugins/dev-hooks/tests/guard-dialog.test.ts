import type { On, PreToolUseResult } from 'claude-code'
import { expect, test } from 'claude-code/testing'

import { guardQuestion, isGuardAsk } from '../hooks/register'

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

// dev-hooks' function-hook module (Claude Code mods, 2.1.287+). Command hooks stay in
// hooks.json; this file holds what only a mod can do, such as drawing UI.
//
// /context-bar: the context window as a stacked bar above the prompt, one color per
// /context category, refreshed after every turn from the local (API-free) estimate.
//
// Session facts: what this session did, recorded as it happens rather than rebuilt
// from git and the transcript at Stop — skills expanded (main loop and subagents),
// subagents dispatched, files edited per repo with net growth, and the Stop verdict
// the command hooks returned. The Stop orchestration below hands it to the Stop hooks.
//
// Stop orchestration: the module runs dev-hooks' own Stop command hooks itself and
// returns their reasons as one block. It marks the session with DEV_HOOKS_MOD_SESSION,
// which makes the copies Claude Code runs directly stand down (reminder_stop_init), and
// runs its own copies with DEV_HOOKS_ORCHESTRATED set. Without this module (an older
// Claude Code, mods off) nothing is marked and the command hooks run as before.
//
// Stop-nudge outcomes: each reason the orchestration returns is resolved at the next
// Stop as acted on or not (nudge-outcomes.ts), shown by /session-facts nudges.
//
// CI watch: after a git push the module follows that push's GitHub Actions runs and
// tells the person and Claude how they ended (the block marked below).
import type { EngineInterface, Register } from 'claude-code'

import type { Facts, Nudge, NudgeRecord, Segment, Snapshot } from '../types'
import {
  ciNote,
  ciStatusLine,
  ciToast,
  ciVerdict,
  githubRepo,
  isDryRun,
  isGitPush,
  parsePushOutput,
  parseRuns,
  pushDir,
  RUN_FIELDS,
  watchingNote,
} from './ci-watch'
import type { Run, Watch } from './ci-watch'
import {
  formatNudgeStats,
  hookName,
  mergeNudgeLog,
  newNudge,
  NUDGE_LOG_KEY,
  nudgeExport,
  resolvePending,
  toRecord,
} from './nudge-outcomes'

const isShown = { plugin: 'dev-hooks', key: 'contextBarShown' } as const
const snapshot = { plugin: 'dev-hooks', key: 'contextBarSnapshot' } as const

const formatTokens = (n: number) =>
  n >= 1000 ? `${(n / 1000).toFixed(n >= 100_000 ? 0 : 1)}k` : `${n}`

// Largest-remainder split, so the cells always add up to the bar's width
// and any category with tokens gets at least the cell its share earns.
export const allocate = (segments: Segment[], width: number): number[] => {
  const total = segments.reduce((sum, s) => sum + s.tokens, 0)
  if (total === 0 || width <= 0) return segments.map(() => 0)
  const exact = segments.map(s => (s.tokens / total) * width)
  const cells = exact.map(Math.floor)
  let left = width - cells.reduce((sum, c) => sum + c, 0)
  const byRemainder = exact
    .map((x, i) => ({ i, rest: x - Math.floor(x) }))
    .sort((a, b) => b.rest - a.rest)
  for (const { i } of byRemainder) {
    if (left-- <= 0) break
    cells[i] = (cells[i] ?? 0) + 1
  }
  return cells
}

async function refresh($: EngineInterface) {
  const { context } = await $.session.usage({ breakdown: 'summary' })
  const b = context.breakdown
  if (!b) return
  const next: Snapshot = {
    segments: b.categories
      .filter(c => c.kind !== 'deferred' && c.tokens > 0)
      .map(c => ({ name: c.name, tokens: c.tokens, color: c.color, kind: c.kind as Segment['kind'] })),
    totalTokens: b.totalTokens,
    maxTokens: b.rawMaxTokens,
    percentage: b.percentage,
  }
  await $.state.set(snapshot, next)
}

type Patch = { lines: string[] }[]

// Net growth: a replaced line is a -/+ pair, not growth. A created file's
// patch is empty, so count its content instead.
export const netAdded = (patch: Patch | undefined, created: string | undefined): number => {
  const lines = (patch ?? []).flatMap(hunk => hunk.lines)
  if (lines.length === 0 && created !== undefined) {
    return created === '' ? 0 : created.replace(/\n$/, '').split('\n').length
  }
  return lines.filter(l => l.startsWith('+')).length - lines.filter(l => l.startsWith('-')).length
}

const FACTS_TTL_MS = 30 * 86_400_000
const emptyFacts = (): Facts => ({ updatedAt: 0, skills: [], agents: [], repos: [], stops: [] })

// $.store, not $.state: facts must survive a reboot or a resumed session.
async function loadFacts($: EngineInterface, sessionId?: string): Promise<Facts> {
  const id = sessionId ?? (await $.session.id())
  return ((await $.store.get(`facts:${id}`)) as Facts | undefined) ?? emptyFacts()
}

// The store has no compare-and-set and tool calls run in parallel, so every
// read-modify-write goes through one queue.
let factsQueue: Promise<unknown> = Promise.resolve()

function changeFacts($: EngineInterface, fn: (f: Facts) => Facts, sessionId?: string): Promise<Facts> {
  const run = factsQueue.then(async () => {
    const id = sessionId ?? (await $.session.id())
    const next = { ...fn(await loadFacts($, id)), updatedAt: Date.now() }
    await $.store.set(`facts:${id}`, next)
    return next
  })
  factsQueue = run.catch(() => undefined)
  return run
}

// Returns the facts kept, by session id.
async function pruneFacts($: EngineInterface): Promise<Map<string, Facts>> {
  const cutoff = Date.now() - FACTS_TTL_MS
  const kept = new Map<string, Facts>()
  for (const key of await $.store.keys()) {
    if (!key.startsWith('facts:')) continue
    const f = (await $.store.get(key)) as Facts | undefined
    if (!f || f.updatedAt < cutoff) await $.store.delete(key)
    else kept.set(key.slice('facts:'.length), f)
  }
  return kept
}

export const ago = (at: number, now: number): string => {
  const mins = Math.floor((now - at) / 60_000)
  if (mins < 1) return 'just now'
  if (mins < 60) return `${mins}m ago`
  if (mins < 24 * 60) return `${Math.floor(mins / 60)}h${mins % 60 ? `${mins % 60}m` : ''} ago`
  return `${Math.floor(mins / (24 * 60))}d ago`
}

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`

// This session's Stop nudges, shown only once one fired.
const nudgeSection = (nudges: Nudge[], when: (at: number) => string): string[] =>
  nudges.length === 0
    ? []
    : [
        '',
        `Stop nudges (${nudges.length})`,
        ...nudges.map(n => `  ${when(n.at)} ${n.hook} · ${n.outcome ? `${n.outcome} (${n.evidence})` : 'pending'}`),
      ]

// Plain text: command output is shown as-is, not rendered as markdown.
export const formatFacts = (f: Facts, now: number, home: string): string => {
  const tilde = (path: string) => (home && path.startsWith(`${home}/`) ? `~${path.slice(home.length)}` : path)
  const when = (at: number) => ago(at, now).padEnd(8)
  // "Title: none" when empty; otherwise the heading (with its count) and the rows.
  const section = (title: string, count: string, rows: string[]) =>
    rows.length === 0 ? [`${title}: none`] : [`${title}${count}`, ...rows, '']

  const repos = [...f.repos].sort((a, b) => Number(a.root === null) - Number(b.root === null))
  const edits = repos.flatMap(r => {
    const where = r.root === null ? 'outside any repo' : tilde(r.root)
    const inRepo = (file: string) => r.root !== null && file.startsWith(`${r.root}/`)
    const bySub = r.bySubagent > 0 ? ` · ${plural(r.bySubagent, 'edit')} by subagents` : ''
    return [
      `  ${where} · ${r.added >= 0 ? '+' : ''}${r.added} lines · ${plural(r.files.length, 'file')}${bySub}`,
      ...r.files.map(file => `    ${inRepo(file) ? file.slice((r.root ?? '').length + 1) : tilde(file)}`),
    ]
  })
  const blocked = f.stops.filter(s => s.block !== null)

  const lines = [
    f.updatedAt ? `Session facts · updated ${ago(f.updatedAt, now)}` : 'Session facts · nothing recorded yet',
    '',
    ...section('Skills', ` (${f.skills.length})`, f.skills.map(s => `  ${when(s.at)} ${s.skill}`)),
    ...section(
      'Subagents',
      ` (${f.agents.length})`,
      f.agents.map(a => `  ${when(a.at)} ${a.subagentType} · ${a.description}`),
    ),
    ...section('Edits via Edit/Write (Bash-made edits are not tracked)', '', edits),
    ...(f.stops.length === 0
      ? ['Stops: none']
      : [
          `Stops (${f.stops.length}, ${blocked.length || 'none'} blocked)`,
          ...blocked.map(s => `  ${when(s.at)} ${(s.block ?? '').split('\n')[0]}`),
        ]),
    ...nudgeSection(f.nudges ?? [], when),
  ]
  if (lines[lines.length - 1] !== '') lines.push('')
  return [
    ...lines,
    '/session-facts json prints the raw record; /session-facts nudges, Stop-nudge outcomes across sessions.',
  ].join('\n')
}

const repoRoots = new Map<string, string | null>()

async function repoRoot($: EngineInterface, file: string): Promise<string | null> {
  const dir = file.slice(0, file.lastIndexOf('/')) || '/'
  const known = repoRoots.get(dir)
  if (known !== undefined) return known
  const run = await $.process.run(['git', '-C', dir, 'rev-parse', '--show-toplevel'])
  const root = run.exitCode === 0 ? run.stdout.trim() : null
  repoRoots.set(dir, root)
  return root
}

export type StopHook = { command: string; timeoutMs: number }

// Claude Code's default for a command hook with no `timeout`, in seconds.
const DEFAULT_HOOK_TIMEOUT_S = 600

type HookEntry = { type?: string; command?: string; timeout?: number }

export const stopHooks = (config: unknown): StopHook[] => {
  const groups = (config as { hooks?: { Stop?: { hooks?: HookEntry[] }[] } } | null)?.hooks?.Stop ?? []
  return groups
    .flatMap(group => group.hooks ?? [])
    .filter((h): h is HookEntry & { command: string } => h.type === 'command' && typeof h.command === 'string')
    .map(h => ({ command: h.command, timeoutMs: (h.timeout ?? DEFAULT_HOOK_TIMEOUT_S) * 1000 }))
}

// A command hook's Stop answer, read as Claude Code reads it: exit 2 blocks with
// stderr as the reason; exit 0 blocks only with a decision:block JSON answer.
export const stopReason = (run: { exitCode: number; stdout: string; stderr: string }): string | null => {
  if (run.exitCode === 2) return run.stderr.trim() || null
  if (run.exitCode !== 0) return null
  try {
    const out = JSON.parse(run.stdout) as { decision?: unknown; reason?: unknown }
    return out.decision === 'block' && typeof out.reason === 'string' && out.reason.trim() ? out.reason : null
  } catch {
    return null
  }
}

export const mergeBlocks = (below: string | undefined, reasons: string[]): string | undefined => {
  const all = [...(below ? [below] : []), ...reasons]
  return all.length > 0 ? all.join('\n\n') : undefined
}

async function ownStopHooks($: EngineInterface): Promise<StopHook[]> {
  return stopHooks(JSON.parse(await $.fs.read(`${$.plugin.root}/hooks/hooks.json`)))
}

// A failed orchestration is remembered against this plugin version, so a broken
// release doesn't cost every new session its first Stop; a new version tries again.
const ORCHESTRATION_FAILED = 'stopOrchestrationFailed'

async function pluginVersion($: EngineInterface): Promise<string> {
  const manifest = JSON.parse(await $.fs.read(`${$.plugin.root}/.claude-plugin/plugin.json`)) as { version?: string }
  return manifest.version ?? 'unknown'
}

// Runs dev-hooks' Stop commands as Claude Code would and merges their reasons after
// `below` (any block from hooks beneath the module).
async function orchestrateStop(
  $: EngineInterface,
  e: StopInput,
  below: string | undefined,
): Promise<string | undefined> {
  const stdin = JSON.stringify(e)
  // The facts reach the shell hooks as a file (reminder_transcript_invoked reads it):
  // they see skills and agents run inside subagents, which the transcript doesn't.
  // Optional — without them the hooks fall back to the transcript.
  const factsFile = `${(await $.env.get('TMPDIR')) || '/tmp'}/dev-hooks-facts-${e.session_id}.json`
  const hasFacts = await $.fs
    .write(factsFile, JSON.stringify(await loadFacts($)))
    .then(() => true, () => false)
  const env = {
    CLAUDE_PLUGIN_ROOT: $.plugin.root,
    DEV_HOOKS_ORCHESTRATED: '1',
    ...(hasFacts ? { DEV_HOOKS_FACTS_FILE: factsFile } : {}),
  }
  const hooks = await ownStopHooks($)
  const runs = await Promise.all(
    hooks.map(hook =>
      $.process
        .run(['bash', '-c', hook.command], { cwd: e.cwd, stdin, env, timeoutMs: hook.timeoutMs })
        .then(stopReason, () => null),
    ),
  )
  const block = mergeBlocks(below, runs.filter((r): r is string => r !== null))
  const stop = { at: Date.now(), block: block ?? null }
  await changeFacts($, f => ({ ...f, stops: [...f.stops, stop].slice(-20) })).catch(() => undefined)
  const fired = hooks.flatMap((hook, i) => {
    const reason = runs[i]
    return reason ? [{ hook: hookName(hook.command), reason }] : []
  })
  await trackNudges($, e, fired).catch(() => undefined)
  return block
}

// ── Guard dialog ─────────────────────────────────────────────────────────────────
// When dangerous-command-guard.sh asks (its `ask` modes), the mod puts the question to
// the person in Claude Code's own dialog: a PreToolUse `ask` is answered by the
// auto-mode classifier, the dialog is not. Allow only withdraws the guard's question —
// the normal permission flow still runs — and Deny refuses; a hard deny is never asked.
export const GUARD_PREFIX = 'dev-hooks guard — '

export const isGuardAsk = (ask: string | undefined): ask is string => !!ask && ask.startsWith(GUARD_PREFIX)

const COMMAND_SHOWN = 300

const waitLabel = (seconds: number) => (seconds % 60 === 0 ? `${seconds / 60} min` : `${seconds}s`)

export const guardQuestion = (ask: string, command: string, seconds = 0): string => {
  const reason = ask.slice(GUARD_PREFIX.length).replace(/^please confirm:\s*/i, '')
  const shown = command.length > COMMAND_SHOWN ? `${command.slice(0, COMMAND_SHOWN)}…` : command
  const wait = seconds > 0 ? `\n\n(No answer within ${waitLabel(seconds)} refuses it.)` : ''
  return `${reason}\n\nCommand: ${shown}${wait}\n\nLet it run?`
}

// An unanswered dialog refuses after this long, and tells Claude the safer route instead of
// leaving it stuck. DEV_HOOKS_GUARD_DIALOG_TIMEOUT (seconds; 0 waits forever) set in front of
// the command itself wins — Claude may pick a longer wait, since a timeout only ever refuses —
// then the session's setting, then this default.
const DEFAULT_GUARD_TIMEOUT_S = 120

const COMMAND_TIMEOUT_RE =
  /(?:^|[;&|]\s*)(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*DEV_HOOKS_GUARD_DIALOG_TIMEOUT=(['"]?)(\d+)\1(?=\s)/

export const commandTimeout = (command: string): number | undefined => {
  const match = COMMAND_TIMEOUT_RE.exec(command)
  return match ? Number(match[2]) : undefined
}

export const guardTimeoutReason = (ask: string, seconds: number): string => {
  const base =
    `No answer in the dev-hooks guard dialog within ${seconds}s, so this command did not run.` +
    ' (If the person may need longer, put DEV_HOOKS_GUARD_DIALOG_TIMEOUT=<seconds> in front of the command; 0 waits indefinitely.)'
  return /the `[^`]+` branch directly/.test(ask)
    ? `${base} Make this change on a separate branch in a git worktree instead (branch off the current HEAD), not directly on the main branch.`
    : `${base} Ask the person in the chat before trying again, or find a route that doesn't need this command.`
}

// From session.start: whether a person is there to answer the dialog.
let isInteractive = false

async function guardTimeoutSeconds($: EngineInterface, command: string): Promise<number> {
  const own = commandTimeout(command)
  if (own !== undefined) return own
  const raw = await $.env.get('DEV_HOOKS_GUARD_DIALOG_TIMEOUT').catch(() => undefined)
  const seconds = Number(raw)
  return raw !== undefined && raw.trim() !== '' && Number.isFinite(seconds) && seconds >= 0
    ? seconds
    : DEFAULT_GUARD_TIMEOUT_S
}

// ── Stop-nudge outcomes ─────────────────────────────────────────────────────────
// Each reason the orchestration returns is a nudge in this session's facts; the next
// Stop resolves the pending ones as acted/ignored/declined/unknown (nudge-outcomes.ts
// holds the remedy per hook), and the resolved ones go to a cross-session log in the
// store (`nudgeOutcomes`), exported for the weekly automation review.

type StopInput = { session_id: string; cwd: string; last_assistant_message?: string }

// A session idle this long with a nudge still pending never reached another Stop or a
// clean session end (killed, crashed): resolve it from its facts at the next start.
const NUDGE_SWEEP_IDLE_MS = 6 * 3_600_000

async function trackNudges($: EngineInterface, e: StopInput, fired: { hook: string; reason: string }[]) {
  const now = Date.now()
  let resolved: Nudge[] = []
  await changeFacts($, f => {
    const ev = { facts: f, refired: fired.map(x => x.hook), lastMessage: e.last_assistant_message, atStop: true }
    const r = resolvePending(f, ev, now)
    resolved = r.resolved
    if (fired.length === 0) return r.facts
    const added = fired.map(x => newNudge(x.hook, x.reason, now))
    return { ...r.facts, nudges: [...(r.facts.nudges ?? []), ...added].slice(-100) }
  })
  await logNudges($, resolved.map(n => toRecord(e.session_id, n)))
}

// The session is ending: whatever is still pending gets no further Stop.
async function closeNudges($: EngineInterface, sessionId: string) {
  if (!((await loadFacts($, sessionId)).nudges ?? []).some(n => n.outcome === undefined)) return
  let resolved: Nudge[] = []
  await changeFacts(
    $,
    f => {
      const r = resolvePending(f, { facts: f, refired: [], atStop: false }, Date.now())
      resolved = r.resolved
      return r.facts
    },
    sessionId,
  )
  await logNudges($, resolved.map(n => toRecord(sessionId, n)))
}

// At session start: resolve abandoned sessions' pending nudges, and re-add every resolved
// nudge the kept facts hold, repairing a log write another process raced.
async function sweepNudges($: EngineInterface, kept: Map<string, Facts>, current: string) {
  const now = Date.now()
  const records: NudgeRecord[] = []
  for (const [id, f] of kept) {
    let facts = f
    const pending = (f.nudges ?? []).some(n => n.outcome === undefined)
    if (id !== current && pending && f.updatedAt < now - NUDGE_SWEEP_IDLE_MS) {
      facts = resolvePending(f, { facts: f, refired: [], atStop: false }, now).facts
      await $.store.set(`facts:${id}`, facts)
    }
    for (const n of facts.nudges ?? []) if (n.outcome !== undefined) records.push(toRecord(id, n))
  }
  await logNudges($, records)
}

async function loadNudgeLog($: EngineInterface): Promise<NudgeRecord[]> {
  return ((await $.store.get(NUDGE_LOG_KEY)) as NudgeRecord[] | undefined) ?? []
}

async function logNudges($: EngineInterface, records: NudgeRecord[]) {
  if (records.length === 0) return
  const now = Date.now()
  const log = mergeNudgeLog(await loadNudgeLog($), records, now)
  await $.store.set(NUDGE_LOG_KEY, log)
  // Beside the prompt log and hook-fires.jsonl; only where that directory already exists.
  const dir = `${(await $.env.get('HOME')) ?? ''}/.claude/automation-review`
  if (await $.fs.exists(dir)) await $.fs.write(`${dir}/stop-nudges.json`, `${JSON.stringify(nudgeExport(log, now))}\n`)
}

// ── CI watch ────────────────────────────────────────────────────────────────────────
// After a successful `git push` the module watches that push's GitHub Actions runs:
// progress in the status line, a toast when they end, and the outcome handed to Claude
// (a pass as a conversation note, a failure as a prompt that wakes the session). It
// marks the session with DEV_HOOKS_CI_WATCH_SESSION so ci-watch-reminder.sh stands down;
// DEV_HOOKS_CI_WATCH=false turns both off. Watches live in module variables: a reload
// of the module drops them.
const CI_FIRST_POLL_MS = 3_000
const CI_APPEAR_MS = 120_000
const CI_RETRY_MS = 5_000
const CI_POLL_MS = 15_000
const CI_GIVE_UP_MS = 90 * 60_000

const ciWatches = new Map<string, Watch & { startedAt: number }>()

async function ciOptedOut($: EngineInterface): Promise<boolean> {
  return (await $.env.get('DEV_HOOKS_CI_WATCH')) === 'false'
}

async function claimCiWatch($: EngineInterface) {
  if (!(await ciOptedOut($))) await $.env.set('DEV_HOOKS_CI_WATCH_SESSION', await $.session.id())
}

function showCiStatus($: EngineInterface) {
  $.ui.status(ciStatusLine([...ciWatches.values()]))
}

async function git($: EngineInterface, cwd: string, ...args: string[]): Promise<string | null> {
  const run = await $.process.run(['git', '-C', cwd, ...args]).catch(() => null)
  return run?.exitCode === 0 ? run.stdout.trim() : null
}

// The commits a push sent to GitHub, from its output; a quiet push (`-q`) prints no
// ref lines, so it falls back to HEAD and the branch's default remote.
async function pushTargets($: EngineInterface, command: string, output: string): Promise<{ repo: string; sha: string }[]> {
  const root = await git($, pushDir(command, await $.session.cwd()), 'rev-parse', '--show-toplevel')
  if (root === null) return []
  const workflows = await $.fs.list(`${root}/.github/workflows`).catch(() => [])
  if (!workflows.some(w => /\.ya?ml$/.test(w.name))) return []

  const pushed = parsePushOutput(output)
  if (pushed.refs.length === 0 && /Everything up-to-date/.test(output)) return []
  const repo = githubRepo(pushed.remote ?? (await git($, root, 'ls-remote', '--get-url')) ?? '')
  if (repo === null) return []
  const refs = pushed.refs.length > 0 ? pushed.refs.map(r => r.sha ?? r.src) : ['HEAD']
  const shas = await Promise.all(refs.map(ref => git($, root, 'rev-parse', `${ref}^{commit}`)))
  return [...new Set(shas.filter((s): s is string => s !== null))].map(sha => ({ repo, sha }))
}

async function startCiWatch($: EngineInterface, target: { repo: string; sha: string }) {
  const key = `${target.repo}@${target.sha}`
  if (ciWatches.has(key)) return
  ciWatches.set(key, { ...target, done: 0, total: 0, startedAt: await $.clock.now() })
  showCiStatus($)
  $.clock.after(CI_FIRST_POLL_MS, () => void pollCi($, key))
}

async function pollCi($: EngineInterface, key: string) {
  const w = ciWatches.get(key)
  if (!w) return
  try {
    let runs: Run[] = []
    let error: string | undefined
    try {
      const argv = ['gh', 'run', 'list', '--repo', w.repo, '--commit', w.sha, '--json', RUN_FIELDS, '--limit', '50']
      const run = await $.process.run(argv, { timeoutMs: 30_000 })
      if (run.exitCode === 0) runs = parseRuns(run.stdout)
      else error = run.stderr.trim().split('\n')[0] || `gh exited ${run.exitCode}`
    } catch (err) {
      error = String(err)
    }
    const { verdict, runs: mine } = ciVerdict(runs, w.sha)
    const elapsed = (await $.clock.now()) - w.startedAt
    if (verdict === 'pending' ? elapsed < CI_GIVE_UP_MS : verdict === 'none' && elapsed < CI_APPEAR_MS) {
      w.done = mine.filter(r => r.status === 'completed').length
      w.total = mine.length
      showCiStatus($)
      $.clock.after(verdict === 'none' ? CI_RETRY_MS : CI_POLL_MS, () => void pollCi($, key))
      return
    }

    ciWatches.delete(key)
    showCiStatus($)
    $.ui.toast(ciToast(w.repo, w.sha, verdict, mine), { timeoutMs: verdict === 'success' ? 8_000 : 20_000 })
    const note = ciNote(w.repo, w.sha, verdict, mine, error)
    // A failure needs Claude to act, so it starts a turn (once the session is idle);
    // anything else is read with Claude's next request without waking it.
    if (verdict === 'failure') await $.prompt.submit({ text: note })
    else await $.session.append({ message: { type: 'user', content: [{ type: 'text', text: note }] } })
  } catch (err) {
    ciWatches.delete(key)
    showCiStatus($)
    $.ui.log(`dev-hooks: CI watch for ${key} failed: ${String(err)}`)
  }
}
// ── end CI watch ────────────────────────────────────────────────────────────────────

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    isInteractive = e.isInteractive
    await $.command.register({
      name: 'context-bar',
      description: 'Toggle a stacked context-usage bar above the prompt',
    })
    await $.command.register({
      name: 'session-facts',
      description: 'Show what dev-hooks recorded about this session (nudges: Stop-nudge outcomes)',
    })
    const kept = await pruneFacts($)
    await sweepNudges($, kept, await $.session.id()).catch(() => undefined)
    if ((await $.state.get(isShown)).value) await refresh($)
    // Only take the Stop hooks over once their config reads cleanly, and not on a
    // version whose orchestration already failed; otherwise leave the session unmarked
    // so the command hooks keep running directly.
    const failedOn = await $.store.get(ORCHESTRATION_FAILED)
    if ((await ownStopHooks($)).length > 0 && failedOn !== (await pluginVersion($))) {
      await $.env.set('DEV_HOOKS_MOD_SESSION', await $.session.id())
    }
    await claimCiWatch($)

    return next(e)
  })

  on('command.run', { command: 'context-bar' }, async $ => {
    const shown = !(await $.state.get(isShown)).value
    await $.state.set(isShown, shown)
    if (shown) await refresh($)

    return { text: shown ? 'Context bar on.' : 'Context bar off.' }
  })

  on('session.measure', async ($, e, next) => {
    if ((await $.state.get(isShown)).value) await refresh($)

    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey || !(await $.state.get(isShown)).value) return next(e)
    const snap = (await $.state.get(snapshot)).value
    const { Box, Text } = $.ui.resolve(e)

    if (!snap) {
      return (
        <Box>
          <Text dimColor>Context bar: waiting for the first measurement…</Text>
        </Box>
      )
    }

    const summary = ` ${snap.percentage}% · ${formatTokens(snap.totalTokens)}/${formatTokens(snap.maxTokens)}`
    const width = Math.max(10, e.props.bodyColumns - summary.length - 1)
    const cells = allocate(snap.segments, width)
    const glyph = (s: Segment) => (s.kind === 'free' ? '░' : s.kind === 'buffer' ? '▒' : '█')

    return (
      <Box flexDirection="column">
        <Box>
          <Text>
            {snap.segments.map((s, i) => (
              <Text color={s.color} dimColor={s.kind === 'free'}>
                {glyph(s).repeat(cells[i] ?? 0)}
              </Text>
            ))}
          </Text>
          <Text dimColor>{summary}</Text>
        </Box>
        <Box flexWrap="wrap">
          {snap.segments.map(s => (
            <Text>
              <Text color={s.color}>{glyph(s)} </Text>
              <Text dimColor>
                {s.name} {formatTokens(s.tokens)}
                {'  '}
              </Text>
            </Text>
          ))}
        </Box>
      </Box>
    )
  })

  on('command.run', { command: 'session-facts' }, async ($, e) => {
    const [sub, arg] = e.args.trim().split(/\s+/)
    if (sub === 'nudges') {
      const days = Number(arg) > 0 ? Number(arg) : 7
      return { text: formatNudgeStats(await loadNudgeLog($), Date.now(), days) }
    }
    const f = await loadFacts($)
    if (sub === 'json') return { text: JSON.stringify(f, null, 2) }

    return { text: formatFacts(f, Date.now(), (await $.env.get('HOME')) ?? '') }
  })

  on('skill.prompt', async ($, e, next) => {
    const at = Date.now()
    await changeFacts($, f => ({ ...f, skills: [...f.skills, { skill: e.skill, at }].slice(-200) }))

    return next(e)
  })

  on('agent.spawn', async ($, e, next) => {
    const agent = { description: e.description, subagentType: e.subagentType, at: Date.now() }
    await changeFacts($, f => ({ ...f, agents: [...f.agents, agent].slice(-200) }))

    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    const ran = await next(e)
    if (ran.deny !== undefined || ran.isError || (e.tool !== 'Edit' && e.tool !== 'Write')) return ran

    const result = ran.result as { structuredPatch?: Patch; type?: string } | undefined
    const created = e.tool === 'Write' && result?.type === 'create' ? e.content : undefined
    const added = netAdded(result?.structuredPatch, created)
    const root = await repoRoot($, e.file_path)
    const bySubagent = e.agentId === undefined ? 0 : 1

    await changeFacts($, f => {
      const prev = f.repos.find(r => r.root === root) ?? { root, files: [], added: 0, bySubagent: 0 }
      const repo = {
        root,
        files: prev.files.includes(e.file_path) ? prev.files : [...prev.files, e.file_path],
        added: prev.added + added,
        bySubagent: prev.bySubagent + bySubagent,
      }
      const lastEdit = { ...f.lastEdit, [e.file_path]: Date.now() }
      return { ...f, repos: [...f.repos.filter(r => r.root !== root), repo], lastEdit }
    })

    return ran
  })

  on('session.end', async ($, e, next) => {
    await closeNudges($, e.sessionId).catch(() => undefined)

    return next(e)
  })

  // CI watch: a push that went through starts a watch on its runs.
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const ran = await next(e)
    if (ran.deny !== undefined || ran.isError || e.tool !== 'Bash') return ran
    if (!isGitPush(e.command) || isDryRun(e.command) || (await ciOptedOut($))) return ran

    const targets = await pushTargets($, e.command, ran.text ?? '')
    if (targets.length === 0) return ran
    for (const target of targets) await startCiWatch($, target)

    return { ...ran, context: [...(ran.context ?? []), watchingNote(targets)] }
  })

  // Sees the command hooks' Stop verdict folded last-write-wins: with several
  // blocking, only the last reason arrives here (Claude still gets them all).
  on('classic.Stop', async ($, e, next) => {
    const below = await next(e)
    if ((await $.env.get('DEV_HOOKS_MOD_SESSION')) !== e.session_id) return below

    try {
      const block = await orchestrateStop($, e, below.block)
      return block === undefined ? below : { ...below, block }
    } catch (error) {
      // The command hooks stood down for this session, so a failure here would
      // silence every later Stop too: hand Stop back to them from the next turn.
      await $.env.set('DEV_HOOKS_MOD_SESSION', undefined)
      await $.store.set(ORCHESTRATION_FAILED, await pluginVersion($).catch(() => 'unknown')).catch(() => undefined)
      $.ui.log(`dev-hooks: Stop orchestration failed, the Stop hooks run directly from now on: ${String(error)}`)
      return below
    }
  })

  on('classic.PreToolUse', async ($, e, next) => {
    const decided = await next(e)
    if (e.tool !== 'Bash' || !isGuardAsk(decided.ask)) return decided
    const seconds = await guardTimeoutSeconds($, e.command)
    const asked = $.ui.ask(guardQuestion(decided.ask, e.command, seconds), {
      header: 'dev-hooks',
      options: ['Allow', 'Deny'],
    })
    let answer: string
    try {
      const never = new Promise<never>(() => {})
      // A timer that can't run means no timeout, never a decision.
      const timedOut = seconds > 0 ? $.clock.sleep(seconds * 1000).then(() => undefined, () => never) : never
      const first = await Promise.race([asked, timedOut])
      if (first === undefined) {
        asked.catch(() => undefined)
        return { deny: guardTimeoutReason(decided.ask, seconds) }
      }
      answer = first
    } catch {
      // Dismissed: refuse, since handing the question back would let auto mode answer
      // it. With no one to ask at all (claude -p) the guard's question stands as it was.
      return isInteractive
        ? { deny: 'The dev-hooks guard dialog was dismissed, so this command did not run.' }
        : decided
    }
    if (answer === 'Allow') {
      const { ask: _withdrawn, ...rest } = decided
      return rest
    }
    return { deny: `The person declined this command in the dev-hooks guard dialog (answer: ${answer}).` }
  })
}

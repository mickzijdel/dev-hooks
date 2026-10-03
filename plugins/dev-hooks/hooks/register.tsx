// dev-hooks' function-hook module (Claude Code mods, 2.1.287+). Command hooks stay in
// hooks.json; this file holds what only a mod can do, such as drawing UI.
//
// /context-bar: the context window as a stacked bar above the prompt, one color per
// /context category, refreshed after every turn from the local (API-free) estimate.
//
// Session facts: what this session did, recorded as it happens rather than rebuilt
// from git and the transcript at Stop — skills expanded (main loop and subagents),
// subagents dispatched, files edited per repo with net growth, and the Stop verdict
// the command hooks returned. Observation only; nothing reads it back yet.
import type { EngineInterface, Register } from 'claude-code'

import type { Facts, Segment, Snapshot } from '../types'

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
async function loadFacts($: EngineInterface): Promise<Facts> {
  const id = await $.session.id()
  return ((await $.store.get(`facts:${id}`)) as Facts | undefined) ?? emptyFacts()
}

// The store has no compare-and-set and tool calls run in parallel, so every
// read-modify-write goes through one queue.
let factsQueue: Promise<unknown> = Promise.resolve()

function changeFacts($: EngineInterface, fn: (f: Facts) => Facts): Promise<Facts> {
  const run = factsQueue.then(async () => {
    const id = await $.session.id()
    const next = { ...fn(await loadFacts($)), updatedAt: Date.now() }
    await $.store.set(`facts:${id}`, next)
    return next
  })
  factsQueue = run.catch(() => undefined)
  return run
}

async function pruneFacts($: EngineInterface) {
  const cutoff = Date.now() - FACTS_TTL_MS
  for (const key of await $.store.keys()) {
    if (!key.startsWith('facts:')) continue
    const f = (await $.store.get(key)) as Facts | undefined
    if (!f || f.updatedAt < cutoff) await $.store.delete(key)
  }
}

export const ago = (at: number, now: number): string => {
  const mins = Math.floor((now - at) / 60_000)
  if (mins < 1) return 'just now'
  if (mins < 60) return `${mins}m ago`
  if (mins < 24 * 60) return `${Math.floor(mins / 60)}h${mins % 60 ? `${mins % 60}m` : ''} ago`
  return `${Math.floor(mins / (24 * 60))}d ago`
}

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`

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
  ]
  if (lines[lines.length - 1] !== '') lines.push('')
  return [...lines, '/session-facts json prints the raw record.'].join('\n')
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

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'context-bar',
      description: 'Toggle a stacked context-usage bar above the prompt',
    })
    await $.command.register({
      name: 'session-facts',
      description: 'Show what dev-hooks recorded about this session',
    })
    await pruneFacts($)
    if ((await $.state.get(isShown)).value) await refresh($)

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
    const f = await loadFacts($)
    if (e.args.trim() === 'json') return { text: JSON.stringify(f, null, 2) }

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
      return { ...f, repos: [...f.repos.filter(r => r.root !== root), repo] }
    })

    return ran
  })

  // Sees the command hooks' Stop verdict folded last-write-wins: with several
  // blocking, only the last reason arrives here (Claude still gets them all).
  on('classic.Stop', async ($, e, next) => {
    const verdict = await next(e)
    const stop = { at: Date.now(), block: verdict.block ?? null }
    await changeFacts($, f => ({ ...f, stops: [...f.stops, stop].slice(-20) }))

    return verdict
  })
}

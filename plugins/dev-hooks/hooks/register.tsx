// dev-hooks' function-hook module (Claude Code mods, 2.1.287+). Command hooks stay in
// hooks.json; this file holds what only a mod can do, such as drawing UI.
//
// /context-bar: the context window as a stacked bar above the prompt, one color per
// /context category, refreshed after every turn from the local (API-free) estimate.
import type { EngineInterface, Register } from 'claude-code'

import type { Segment, Snapshot } from '../types'

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

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'context-bar',
      description: 'Toggle a stacked context-usage bar above the prompt',
    })
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
}

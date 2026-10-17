import { expect, test } from 'claude-code/testing'

const BAND = {
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isWorking: false,
    maxRows: 10,
    bodyColumns: 80,
    scroll: { offset: 0, bodyRows: 10 },
    view: {},
  },
} as const

const TOGGLE = {
  command: 'context-bar',
  args: '',
  origin: { kind: 'composer' },
  presentation: { isFullscreen: false, columns: 80 },
} as const

const category = (
  name: string,
  tokens: number,
  color: string,
  kind: 'used' | 'free' | 'buffer',
) => ({
  name,
  tokens,
  color,
  kind,
  isDeferred: false,
})

test('the bar appears only after /context-bar, with a legend per category', async ($, on) => {
  // Stands in for the engine's own (empty) band beneath the mod.
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
    const { Box } = $.ui.resolve(e)
    return <Box />
  })
  on('session.usage', () => ({
    value: {
      startedAt: 0,
      rateLimits: [],
      context: {
        tokens: 50_000,
        window: 200_000,
        percent: 25,
        breakdown: {
          categories: [
            category('System prompt', 5_000, 'promptBorder', 'used'),
            category('Messages', 45_000, 'permission', 'used'),
            category('Free space', 117_000, 'inactive', 'free'),
            category('Autocompact buffer', 33_000, 'warning', 'buffer'),
          ],
          totalTokens: 50_000,
          maxTokens: 200_000,
          rawMaxTokens: 200_000,
          autocompactSource: 'model-default',
          percentage: 25,
          gridRows: [],
          model: 'test',
          memoryFiles: [],
          mcpTools: [],
          agents: [],
          isAutoCompactEnabled: true,
          apiUsage: null,
        },
      },
    },
  }))

  for (const surface of ['terminal', 'desktop'] as const) {
    const before = await $.ui.mount({ plugin: 'dev-hooks', surface, ...BAND })
    expect(await before.find({ type: 'Text', text: /Messages/ })).toBeUndefined()
    await before.unmount()
  }

  const ran = await $.command.run(TOGGLE)
  expect(ran.text).toBe('Context bar on.')

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'dev-hooks', surface, ...BAND })
    expect(await ui.find({ type: 'Text', text: /25% · 50\.0k\/200k/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Messages 45\.0k/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Autocompact buffer 33\.0k/ })).toBeDefined()
    await ui.unmount()
  }

  expect((await $.command.run(TOGGLE)).text).toBe('Context bar off.')
})

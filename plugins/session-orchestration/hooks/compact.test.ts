import { expect, mock, test } from 'claude-code/testing'

import { canCompact, ctxOf, parseActions, parseActivity } from './register'

const PANE = { plugin: 'session-orchestration', component: 'Pane', requestId: 'coordinator' } as const
const PROPS = { title: 'Coordinator', isFocused: false, bodyColumns: 160, placement: 'dock', scroll: { offset: 0, bodyRows: 60 }, view: {} } as const
const NOW = Date.UTC(2026, 9, 13, 12, 0)
const S = (minAgo: number) => String(NOW / 1000 - minAgo * 60)
// An --activity line: id name state written doing since last ctx window status kind.
const line = (id: string, name: string, state: string, ctx: number, win: number, status: string, kind = 'background') =>
  [id, name, state, S(1), '', '0', 'Done.', String(ctx), String(win), status, kind].join('\t')

test('context fill: a percentage, dim, amber from 80%, red from 90%; Compact only for an idle background session', () => {
  const [a, b, c, d] = parseActivity([
    line('11111111-1', 'a', 'blocked', 124_000, 200_000, 'idle'),
    line('22222222-1', 'b', 'working', 850_000, 1_000_000, 'busy'),
    line('33333333-1', 'c', 'blocked', 950_000, 1_000_000, 'waiting'),
    line('44444444-1', 'd', '', 0, 200_000, 'idle', 'interactive'),
  ].join('\n'))
  expect(ctxOf(a)).toEqual([['ctx 62%', { dimColor: true }], [' ']])
  expect(ctxOf(b)[0]).toEqual(['ctx 85%', { color: 'warning', bold: true }])
  expect(ctxOf(c)[0]).toEqual(['ctx 95%', { color: 'error', bold: true }])
  expect(ctxOf(d)).toEqual([]) // unknown
  expect([a, b, c, d].map(canCompact)).toEqual([true, false, false, false])
  // A project action can't take Compact's key.
  expect(parseActions('[{"label":"Zap","hotkey":"z","command":"x"}]').errors[0]).toMatch(/pane's own \(Compact\)/)
})

const STATUS = `PROJ-4157  Code Review    app#76 OPEN no-human-approval  | no-wt | sess:"fix it" blocked | Race to settle

Other sessions:
  "busy one" working 8m — Reading (claude attach 22222222)`

test('rows show ctx; an idle session\'s card offers Compact, which runs session-status --compact and says how it went', async ($, on) => {
  mock.clock(on, { now: NOW })
  const runs: string[][] = []
  const toasts: string[] = []
  on('ui.toast', async (_, e) => {
    toasts.push(String(e.text ?? e))
    return { value: undefined }
  })
  on('process.run', async (_, e) => {
    const args = e.argv.slice(2)
    runs.push(args)
    const stdout = args[0] === '--activity'
      ? [line('11111111-aaaa', 'fix it', 'blocked', 870_000, 1_000_000, 'idle'), line('22222222-bbbb', 'busy one', 'working', 300_000, 1_000_000, 'busy')].join('\n')
      : args[0] === '--compact' ? '"fix it" (11111111) is compacting: stopped while idle, resumed with /compact\n'
      : args.length === 0 ? STATUS : ''
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'refresh' })
  const text = async (key: string) => (await ui.find({ type: 'Button', key }))?.text

  expect(await text('task-PROJ-4157')).toBe('PROJ-4157 needs human review ctx 87% (Code Review) Race to settle')
  expect(await text('other-22222222')).toMatch(/ctx 30% 8m$/)
  // The busy session: no Compact.
  await ui.press({ key: 'other-22222222' })
  expect(await ui.find({ type: 'Button', key: 'act-z' })).toBeUndefined()
  // The idle one: Compact, which runs the command and toasts its line.
  await ui.press({ key: 'task-PROJ-4157' })
  await ui.press({ key: 'act-z' })
  expect(runs).toContainEqual(['--compact', '11111111-aaaa'])
  expect(toasts.some(t => /is compacting/.test(t))).toBe(true)
  await ui.unmount()
})

test('a second Compact press while one runs does nothing but say so; the button reads Compacting…', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const runs: string[][] = []
  const toasts: string[] = []
  let release = () => {}
  let started = false
  let done = false
  const held = new Promise<void>(r => { release = r })
  on('ui.toast', async (_, e) => {
    toasts.push(String(e.text ?? e))
    return { value: undefined }
  })
  on('process.run', async (_, e) => {
    const args = e.argv.slice(2)
    runs.push(args)
    if (args[0] === '--compact') {
      started = true
      await held // still stopping and resuming
    }
    const stdout = args[0] === '--activity' ? line('11111111-aaaa', 'fix it', 'blocked', 870_000, 1_000_000, started && !done ? 'busy' : 'idle')
      : args[0] === '--compact' ? '"fix it" (11111111) is compacting\n' : args.length === 0 ? STATUS : ''
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'refresh' })
  await ui.press({ key: 'task-PROJ-4157' })
  const first = ui.press({ key: 'act-z' })
  // Until the first press has marked it (no fixed sleep: the redraw takes what it takes).
  const label = async () => (await ui.find({ type: 'Button', key: 'act-z' }))?.text ?? ''
  for (let i = 0; i < 200 && !/Compacting…/.test(await label()); i++) await clock.settle()
  expect(await label()).toMatch(/Compacting…/)
  await ui.press({ key: 'act-z' })
  expect(toasts).toContain('Compact "fix it" is already running')
  // The minute tick reads it busy (resumed, compacting): the card still says Compacting…, not nothing.
  await clock.advance(60_000)
  expect(await label()).toMatch(/Compacting…/)
  done = true
  release()
  await first
  expect(runs.filter(r => r[0] === '--compact')).toHaveLength(1)
  expect((await ui.find({ type: 'Button', key: 'act-z' }))?.text).toMatch(/Compact$/)
  await ui.unmount()
})

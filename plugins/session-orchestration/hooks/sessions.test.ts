import { expect, mock, test } from 'claude-code/testing'

import { dur, otherOf, parseActivity, progressOf } from './register'

const PANE = { plugin: 'session-orchestration', component: 'Pane', requestId: 'coordinator' } as const
const PROPS = { title: 'Coordinator', isFocused: false, bodyColumns: 160, placement: 'dock', scroll: { offset: 0, bodyRows: 60 }, view: {} } as const

const NOW = Date.UTC(2026, 9, 13, 12, 0) // ms
const S = (minAgo: number) => String(NOW / 1000 - minAgo * 60) // epoch seconds, minutes ago

test('activity lines, durations, progress and the quiet flag', () => {
  const [a, ...rest] = parseActivity(`1111aaaa-0\tfix it\tworking\t${S(12)}\tRunning the tests\t${S(5)}\tStarting.\njunk\n`)
  expect(rest).toEqual([])
  expect(a).toMatchObject({ name: 'fix it', state: 'working', doing: 'Running the tests', last: 'Starting.' })
  expect([dur(5 * 60_000), dur(80 * 60_000), dur(120 * 60_000), dur(3 * 86_400_000)]).toEqual(['5m', '1h20m', '2h', '3d'])
  expect(progressOf(a, NOW).map(f => f.text)).toEqual(['Running the tests · 5m', 'no output for 12m'])
  // Written 2m ago: not quiet. Not working: nothing.
  expect(progressOf(a && { ...a, written: Number(S(2)) }, NOW).map(f => f.text)).toEqual(['Running the tests · 5m'])
  expect(progressOf(a && { ...a, state: 'idle' }, NOW)).toEqual([])
  expect(otherOf('"PROJ-5143 review" working 8m · reviews PROJ-5143 — Reading the diff (claude attach 59a69b1c)')).toEqual({
    name: 'PROJ-5143 review', state: 'working', age: '8m', review: 'PROJ-5143', last: 'Reading the diff',
    command: 'claude attach 59a69b1c', id: '59a69b1c',
  })
  expect(otherOf('"review inbox" idle 2h (CLAUDE_CONFIG_DIR=~/.claude-work claude attach 2de9059d)'))
    .toMatchObject({ name: 'review inbox', state: 'idle', review: undefined, last: '', id: '2de9059d' })
  expect(otherOf('"PROJ-1-fix" idle 2h · superseded by 0a1b2c3d — Done (claude attach 4292213b)'))
    .toMatchObject({ name: 'PROJ-1-fix', superseded: '0a1b2c3d', last: 'Done', id: '4292213b' })
})

const STATUS = `PROJ-4157  Code Review    app#76 OPEN no-human-approval  | no-wt | sess:"fix it" working | Race to settle

Other sessions:
  "old docs" done 1h — Sent the report (claude attach 4292213b)
  "PROJ-5143 review" working 8m · reviews PROJ-5143 — Reading the diff (claude attach 59a69b1c)
  "review inbox" idle 2h — Ready to merge (claude attach 2de9059d)
  "quoted" idle 1h — Committed as "fix: x" (claude attach 7777aaaa)
  "bare" done 1h (claude attach 8888aaaa)`

test('task rows and Other sessions say what a working session is doing, and flag a quiet one', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  let activity = [
    `1111aaaa-1\tfix it\tworking\t${S(12)}\tRunning the tests\t${S(5)}\tStarting.`,
    `59a69b1c-2\tPROJ-5143 review\tworking\t${S(1)}\tRead the diff\t${S(3)}\tReading the diff`,
    `2de9059d-3\treview inbox\tidle\t${S(120)}\t\t0\tReady to merge`,
  ].join('\n')
  on('process.run', async (_, e) => {
    const arg = e.argv[2] ?? ''
    const stdout = arg === '--activity' ? activity : arg === '' ? STATUS : arg === '--urls' ? 'ticket https://jira/{key}' : ''
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'refresh' })
  const text = async (key: string) => (await ui.find({ type: 'Button', key }))?.text

  // The task row: its progress instead of "session working", and the quiet flag.
  expect(await text('task-PROJ-4157')).toBe('PROJ-4157 Running the tests · 5m, no output for 12m, needs human review (Code Review) Race to settle')
  // Other sessions: a review leads with its task key; an idle one shows its last line.
  expect((await ui.find({ type: 'Button', key: 'sec-Other sessions' }))?.text).toMatch(/OTHER SESSIONS 5 /)
  // Running first, then idle, then done.
  const keys = (await ui.findAll({ type: 'Button' })).map(b => b.key).filter(k => /^other-[0-9a-f]+$/.test(String(k)))
  expect(keys).toEqual(['other-59a69b1c', 'other-2de9059d', 'other-7777aaaa', 'other-4292213b', 'other-8888aaaa'])
  // A last line ending in a quote is still an Other session, not one waiting on you; no last line, no gap.
  expect(await text('other-7777aaaa')).toBe('quoted Committed as "fix: x" 1h')
  expect(await text('other-8888aaaa')).toBe('bare 1h')
  expect(await ui.find({ type: 'Text', text: /nothing on you/ })).toBeDefined()
  expect(await text('other-59a69b1c')).toBe('PROJ-5143 review Read the diff · 3m 8m')
  expect(await text('other-2de9059d')).toBe('review inbox Ready to merge 2h')
  await ui.press({ key: 'other-59a69b1c' })
  expect(await ui.find({ type: 'Link', text: /PROJ-5143/ })).toBeDefined() // linked to its ticket
  expect(await ui.find({ type: 'Button', key: 'act-a' })).toBeDefined()

  // A minute on, the activity refresh alone moves the clocks; once the session writes again the flag goes.
  activity = activity.replace(`\t${S(12)}\tRunning`, `\t${S(0)}\tRunning`)
  await clock.advance(60_000)
  expect(await text('task-PROJ-4157')).toBe('PROJ-4157 Running the tests · 6m, needs human review (Code Review) Race to settle')
  await ui.unmount()
})

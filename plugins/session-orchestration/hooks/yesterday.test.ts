import { expect, mock, test } from 'claude-code/testing'

import { BUILTIN_KEYS, parseYesterday, stepDay } from './register'

const PANE = { plugin: 'session-orchestration', component: 'Pane', requestId: 'coordinator' } as const
const PROPS = { title: 'Coordinator', isFocused: false, bodyColumns: 160, placement: 'dock', scroll: { offset: 0, bodyRows: 60 }, view: {} } as const
const NOW = Date.UTC(2026, 9, 22, 7, 0) // a Thursday
const OUT = (since: string) => `Since: ${since}
PROJ-1\tIn Review\tFix it
  Wed 10:52\tapp#292 merged
  Wed 14:32\tJira: Code Review → Ready for Test
"probe"\t\t
  Wed 09:00\tsession "probe" (09:00–09:00): Probe done.`

test('parseYesterday: the since line, tasks with their events, keyless sessions, a tracker failure, stray lines', () => {
  const r = parseYesterday(`Since: 2026-10-21 Wed (picked)\nNote: stg is unreachable\nTracker lookup failed:\n  signed out\n${OUT('x').split('\n').slice(1).join('\n')}\nusage: oops`)
  expect(r.since).toBe('2026-10-21 Wed (picked)')
  expect(r.failed).toEqual(['signed out'])
  expect(r.tasks.map(t => [t.key, t.status, t.title, t.events.length])).toEqual([['PROJ-1', 'In Review', 'Fix it', 2], ['"probe"', '', '', 1]])
  expect(r.tasks[0]?.events[1]).toEqual({ when: 'Wed 14:32', text: 'Jira: Code Review → Ready for Test' })
  expect(r.other).toEqual(['usage: oops'])
})

test('stepDay skips the weekend both ways; y, b and n are the pane\'s own keys', () => {
  expect(stepDay('2026-10-19', -1)).toBe('2026-10-16')
  expect(stepDay('2026-10-16', 1)).toBe('2026-10-19')
  expect(stepDay('2026-10-21', -1)).toBe('2026-10-20')
  expect(['y', 'b', 'n'].every(k => BUILTIN_KEYS[k])).toBe(true)
})

test('y opens the Yesterday tab on the last working day; b steps a weekday back, n on, back to the last working day', async ($, on) => {
  mock.clock(on, { now: NOW })
  const runs: string[][] = []
  on('process.run', async (_, e) => {
    const args = e.argv.slice(2)
    runs.push(args)
    const stdout = args[0] === '--yesterday' ? OUT(args[1] ? `${args[1]} Tue (picked)` : '2026-10-21 Wed (last working day)') : ''
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'yesterday' })
  expect(runs).toContainEqual(['--yesterday'])
  expect(await ui.find({ type: 'Text', text: /Since 2026-10-21 Wed \(last working day\)/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /PROJ-1 In Review Fix it/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Wed 10:52 +app#292 merged/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /OTHER WORK/ })).toBeDefined()
  expect(await ui.find({ type: 'Button', key: 'yd-later' })).toBeUndefined()
  await ui.press({ key: 'yd-earlier' })
  expect(runs).toContainEqual(['--yesterday', '2026-10-20'])
  expect(await ui.find({ type: 'Text', text: /Since 2026-10-20 Tue \(picked\)/ })).toBeDefined()
  await ui.press({ key: 'yd-later' })
  expect(runs.filter(r => r[0] === '--yesterday').at(-1)).toEqual(['--yesterday', '2026-10-21'])
  // On to today: back to the last working day.
  await ui.press({ key: 'yd-later' })
  expect(runs.filter(r => r[0] === '--yesterday').at(-1)).toEqual(['--yesterday'])
  expect(await ui.find({ type: 'Button', key: 'yd-later' })).toBeUndefined()
  // The stub's summary printed nothing: the list stays, with the reason.
  expect(await ui.find({ type: 'Text', text: /Summary failed \(exit 0\): the list instead/ })).toBeDefined()
  // Off again: the task board is back.
  await ui.press({ key: 'yesterday' })
  expect(await ui.find({ type: 'Text', text: /Since / })).toBeUndefined()
  await ui.unmount()
})

test('the summary replaces the list once written, from the reading on stdin; s shows the list; a failed one leaves the list', async ($, on) => {
  mock.clock(on, { now: NOW })
  const stdins: string[] = []
  let fail = false
  let reads = 0
  on('process.run', async (_, e) => {
    const summary = String(e.argv[1]).endsWith('/standup-summary')
    if (summary) stdins.push(e.init?.stdin ?? '')
    // Each reading a little different (a new event), as a real refresh's would be.
    const stdout = summary ? (fail ? 'model call failed: rate limited' : 'Yesterday I merged PROJ-1.\n')
      : e.argv[2] === '--yesterday' ? OUT('2026-10-21 Wed (last working day)') + (reads++ ? `\n  Wed 15:0${reads}\tJira: moved` : '') : ''
    return { value: { exitCode: summary && fail ? 1 : 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'yesterday' })
  expect(stdins).toEqual([OUT('2026-10-21 Wed (last working day)')])
  expect(await ui.find({ type: 'Text', text: /^Yesterday I merged PROJ-1\.$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /PROJ-1 In Review Fix it/ })).toBeUndefined()
  await ui.press({ key: 'yd-list' })
  expect(await ui.find({ type: 'Text', text: /PROJ-1 In Review Fix it/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^Yesterday I merged PROJ-1\.$/ })).toBeUndefined()
  // The list chosen: a refresh runs no summary; back to the summary runs one for the new reading.
  await ui.press({ key: 'refresh' })
  expect(stdins).toHaveLength(1)
  await ui.press({ key: 'yd-list' })
  expect(stdins).toHaveLength(2)
  fail = true
  await ui.press({ key: 'refresh' })
  expect(await ui.find({ type: 'Text', text: /Summary failed \(model call failed: rate limited\): the list instead/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /PROJ-1 In Review Fix it/ })).toBeDefined()
  await ui.unmount()
})

import type { On, ToolCallResult } from 'claude-code'
import type { Engine } from 'claude-code/testing'
import { expect, mock, test } from 'claude-code/testing'

import { HANDED_TTL, handedId, handedProblem, onYouOf, parseHanded, ranText, runConsent } from './register'

const PANE = { plugin: 'session-orchestration', component: 'Pane', requestId: 'coordinator' } as const
const PROPS = { title: 'Coordinator', isFocused: false, bodyColumns: 120, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} } as const
const DIR = '/h/.cache/session-status/commands'
const ok = { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false }

test('a handed-over command is one plain line; a file that fails the same checks is ignored', async () => {
  expect(handedProblem('PROJ-1', 'plugin-release x', 'Releases it')).toBeUndefined()
  const bad = [['PROJ 1', 'a', 'b'], ['PROJ-1', '', 'b'], ['PROJ-1', 'a', ' '], ['PROJ-1', 'a\nb', 'c'], ['PROJ-1', 'a\u001b[2Jb', 'c'],
    ['PROJ-1', 'a‮b', 'c'], ['PROJ-1', 'x'.repeat(2001), 'c'], ['PROJ-1', 42, 'c'], ['PROJ-1', 'a\u200bb', 'c'], ['PROJ-1', 'a', 'b\u2028c']] as const
  expect(bad.map(([k, c, w]) => handedProblem(k, c, w) !== undefined)).toEqual(bad.map(() => true))
  const h = { id: await handedId('s1', 'ls'), key: 'PROJ-1', session: 's1', cwd: '/w', account: '', command: 'ls', what: 'Lists', at: 1 }
  expect(h.id).toMatch(/^[0-9a-f]{16}$/)
  expect(await handedId('s1', 'ls')).toBe(h.id) // the same command again replaces it
  expect(parseHanded(JSON.stringify(h))).toEqual(h)
  expect(parseHanded(JSON.stringify({ ...h, command: 'a\nb' }))).toBeUndefined()
  expect(parseHanded(JSON.stringify({ ...h, id: '../x' }))).toBeUndefined()
  expect(parseHanded('not json')).toBeUndefined()
  // Counted on you under its task, once with the task's other items.
  expect([...onYouOf([], undefined, undefined, [h, { ...h, id: 'b' }]).set]).toEqual(['PROJ-1'])
  expect(runConsent(h)).toBe('The user pressed "Run" in the coordinator pane on this exact command: ls')
  expect(ranText(h, false, 'refused: no')).toContain('it failed: refused: no. Command: ls.')
})

test('hand_command writes the command for the pane, with who handed it', async ($, on) => {
  mock.clock(on, { now: 5000 })
  mock.env(on, { HOME: '/h', CLAUDE_CONFIG_DIR: '/h/.claude-work' })
  on('session.id', async () => ({ value: 'sess-1' }))
  on('session.cwd', async () => ({ value: '/w/tree' }))
  const wrote: { path: string; text: string }[] = []
  on('fs.write', async (_, e) => {
    wrote.push({ path: e.path, text: e.text })
    return { value: undefined }
  })
  const bad = await $.tool.call({ tool: 'mcp__session-orchestration__hand_command', key: 'PROJ-1', command: 'a\nb', what: 'x' })
  expect(bad.deny).toContain('one line')
  const r = await $.tool.call({ tool: 'mcp__session-orchestration__hand_command', key: 'PROJ-1', command: 'plugin-release rnd-x', what: 'Releases the plugin' })
  const id = await handedId('sess-1', 'plugin-release rnd-x')
  expect(String(r.result)).toContain('! plugin-release rnd-x')
  expect(wrote.map(w => w.path)).toEqual([`${DIR}/${id}.json`])
  expect(JSON.parse(wrote[0]?.text ?? '')).toEqual({
    id, key: 'PROJ-1', session: 'sess-1', cwd: '/w/tree', account: '/h/.claude-work', command: 'plugin-release rnd-x', what: 'Releases the plugin', at: 5000,
  })
})

// The pane open, with these command files in DIR; records Bash calls, removals and prompts.
async function pane($: Engine, on: On, files: object[], bash: () => ToolCallResult) {
  mock.clock(on, { now: 10_000 })
  mock.env(on, { HOME: '/h' })
  const rm: string[] = [], calls: { command: string; consent?: string }[] = [], prompts: string[] = []
  on('process.run', async (_, e) => {
    if (e.argv[0] === 'rm') rm.push(String(e.argv[2]))
    const out = e.argv.includes('--root') ? '/w\n' : e.argv.includes('--agents') ? 'sess-9\tplugin-x\tworking\tclaude\t1\t/repo\tbackground\n' : ''
    return { value: { ...ok, stdout: out } }
  })
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  on('fs.exists', async (_, e) => ({ value: e.path === DIR }))
  on('fs.list', async () => ({ value: files.map((f, i) => ({ name: `${(f as { id?: string }).id ?? i}.json`, kind: 'file' as const, size: 1, mtimeMs: 0, isLink: false })) }))
  on('fs.read', async (_, e) => ({ value: JSON.stringify(files.find(f => e.path.endsWith(`/${(f as { id?: string }).id}.json`)) ?? {}) }))
  on('tool.call', { tool: 'Bash' }, async (_, e) => {
    calls.push({ command: e.command, consent: (e as { consent?: string }).consent })
    return bash()
  })
  on('prompt.submit', async (_, e) => {
    prompts.push(e.text)
    return { text: e.text }
  })
  await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  return { ui, rm, calls, prompts }
}

test('the pane lists handed commands under their key; Run makes the Bash call with the press as consent, then clears it', async ($, on) => {
  const h = { id: 'a'.repeat(16), key: 'PROJ-1', session: 'sess-1234-x', cwd: '/w', account: '', command: 'plugin-release rnd-x', what: 'Releases the plugin', at: 9000 }
  const old = { ...h, id: 'b'.repeat(16), command: 'echo old', at: 10_000 - HANDED_TTL - 1 }
  const { ui, rm, calls, prompts } = await pane($, on, [h, old], () => ({ result: { stdout: 'released 0.36.0', stderr: '', interrupted: false }, text: 'released 0.36.0' }))
  expect(await ui.find({ type: 'Text', text: '! plugin-release rnd-x' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '! echo old' })).toBeUndefined() // past its TTL: removed
  expect([...new Set(rm)]).toEqual([`${DIR}/${old.id}.json`]) // each read removes it: the sweep reads twice
  await ui.press({ key: `hrun-${h.id}` })
  expect(calls).toEqual([{ command: 'plugin-release rnd-x', consent: runConsent(h) }])
  expect(rm).toContain(`${DIR}/${h.id}.json`)
  expect(prompts).toEqual([ranText(h, true, 'released 0.36.0')])
  expect(await ui.find({ type: 'Text', text: '! plugin-release rnd-x' })).toBeUndefined()
  await ui.unmount()
})

test('a command from a session this pane runs shows wherever it works, saying where from; another project\'s stays out', async ($, on) => {
  // sess-9 is in the sweep's agents (a plugin session in another repo's worktree); sess-7 is no session of this pane's.
  const h = { id: 'd'.repeat(16), key: 'plugin-x', session: 'sess-9', cwd: '/repo/.claude/worktrees/x', account: '', command: 'plugin-release x', what: 'Releases it', at: 9000 }
  const other = { ...h, id: 'e'.repeat(16), key: 'FM-1', session: 'sess-7', cwd: '/fm', command: 'echo fm' }
  const inside = { ...h, id: 'f'.repeat(16), key: 'PROJ-3', session: 'sess-3', cwd: '/w', command: 'echo here' }
  const { ui } = await pane($, on, [h, other, inside], () => ({ result: '' }))
  expect(await ui.find({ type: 'Text', text: '! plugin-release x' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'handed over from /repo/.claude/worktrees/x; it runs in /w' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '! echo here' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'handed over from /w; it runs in /w' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: '! echo fm' })).toBeUndefined()
  await ui.unmount()
})

test('a refused Run keeps the command with what happened, for another try or Copy', async ($, on) => {
  const h = { id: 'c'.repeat(16), key: 'PROJ-2', session: 'sess-5678', cwd: '/w', account: '/h/.claude-work', command: 'git push origin main', what: 'Pushes main', at: 9000 }
  const { ui, rm, prompts } = await pane($, on, [h], () => ({ deny: 'Permission denied by the user' }))
  expect(await ui.find({ type: 'Text', text: "handed over under /h/.claude-work; it runs under this session's" })).toBeDefined()
  await ui.press({ key: `hrun-${h.id}` })
  expect(rm).toEqual([])
  expect(prompts).toEqual([ranText(h, false, 'refused: Permission denied by the user')])
  expect(await ui.find({ type: 'Text', text: 'last run: refused: Permission denied by the user' })).toBeDefined()
  await ui.press({ key: `hdrop-${h.id}` })
  expect(rm).toEqual([`${DIR}/${h.id}.json`])
  await ui.unmount()
})

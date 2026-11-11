import type { On, ToolCallResult } from 'claude-code'
import type { Engine } from 'claude-code/testing'
import { expect, mock, test } from 'claude-code/testing'

import { HANDED_TTL, handedId, handedProblem, onYouOf, parseHanded, ranText, retryText, runConsent, runTail, sameCommand, USER_NO } from './register'

const PANE = { plugin: 'session-orchestration', component: 'Pane', requestId: 'coordinator' } as const
const PROPS = { title: 'Coordinator', isFocused: false, bodyColumns: 120, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} } as const
const DIR = '/h/.cache/session-status/commands'
const CLAIMS = '/h/.cache/session-status/handed-claims/'
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
  // A failure keeps its last lines and stderr's; a success its last line.
  expect(runTail('a\nb\nc\nd\nnothing pushed', 'error: auth failed\nnothing pushed', false)).toBe('c | d | nothing pushed | error: auth failed')
  expect(runTail('a\nreleased 1.0\n', 'warn: x', true)).toBe('released 1.0')
  expect(runTail('a\nreleased 1.0\n', '', true)).toBe('released 1.0')
  expect(runTail('checking for errors... done\nnothing pushed', 'error', false)).toBe('checking for errors... done | nothing pushed | error')
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
  on('fs.read', async (_, e) => ({ value: wrote.find(w => w.path === e.path)?.text ?? '' }))
  const rm: string[] = []
  on('process.run', async (_, e) => {
    if (e.argv[0] === 'rm') rm.push(String(e.argv[2]))
    return { value: ok }
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
  // withdraw: its own file goes; another key, or a command never handed, removes nothing.
  const call = (key: string, command: string) => $.tool.call({ tool: 'mcp__session-orchestration__hand_command', key, command, withdraw: true })
  expect(String((await call('PROJ-2', 'plugin-release rnd-x')).result)).toContain('Nothing to withdraw')
  expect(String((await call('PROJ-1', 'other')).result)).toContain('Nothing to withdraw')
  expect(rm).toEqual([])
  expect(String((await call('PROJ-1', 'plugin-release rnd-x')).result)).toContain(`Withdrawn (id ${id})`)
  expect(rm).toEqual([`${DIR}/${id}.json`])
})

test('a command the pane has as an action (a sign-in button) is refused, pointing at the button', async ($, on) => {
  expect(sameCommand('npx -y @x/tool-cli@latest  login')).toBe('tool-cli login')
  expect(sameCommand('npx --yes @x/tool-cli@1.2.3 login')).toBe('tool-cli login')
  expect(sameCommand('git push origin a@b')).toBe('git push origin a@b')
  expect(sameCommand('ssh deploy@prod restart')).not.toBe(sameCommand('ssh deploy@dev restart'))
  expect(sameCommand('ssh deploy@10.0.0.1 restart')).not.toBe(sameCommand('ssh deploy@10.0.0.2 restart'))
  expect(sameCommand('npm i @types/node')).toBe('npm i @types/node')
  expect(sameCommand('tool-cli@2 login')).toBe('tool-cli login')
  mock.clock(on, { now: 5000 })
  mock.env(on, { HOME: '/h' })
  on('session.id', async () => ({ value: 'sess-1' }))
  on('session.cwd', async () => ({ value: '/w/tree' }))
  const acts = '/w/.claude/coordinator-actions.json'
  on('process.run', async (_, e) => ({ value: { ...ok, stdout: e.argv.includes('--root') ? '/w\n' : '' } }))
  on('fs.exists', async (_, e) => ({ value: e.path === acts }))
  on('fs.read', async () => ({ value: JSON.stringify([{ label: 'Tool login', hotkey: 'g', command: 'npx -y @x/tool-cli@latest login' }]) }))
  const wrote: string[] = []
  on('fs.write', async (_, e) => {
    wrote.push(e.path)
    return { value: undefined }
  })
  const r = await $.tool.call({ tool: 'mcp__session-orchestration__hand_command', key: 'PROJ-1', command: 'npx @x/tool-cli login', what: 'Signs in' })
  expect(r.deny).toContain('the pane\'s "Tool login" action (key g)')
  expect(wrote).toEqual([])
  const other = await $.tool.call({ tool: 'mcp__session-orchestration__hand_command', key: 'PROJ-1', command: 'tool-cli logout', what: 'Signs out' })
  expect(other.deny).toBeUndefined()
  expect(wrote).toHaveLength(1)
})

// The pane open, with these command files in DIR; records Bash calls, removals and prompts.
async function pane($: Engine, on: On, files: object[], bash: () => ToolCallResult, claims = '') {
  mock.clock(on, { now: 10_000 })
  mock.env(on, { HOME: '/h' })
  on('session.id', async () => ({ value: 'sess-c' }))
  const rm: string[] = [], calls: { command: string; consent?: string }[] = [], prompts: string[] = [], wrote: string[] = []
  on('fs.write', async (_, e) => {
    wrote.push(`${e.path}\t${e.text}`)
    return { value: undefined }
  })
  on('process.run', async (_, e) => {
    if (e.argv[0] === 'rm') rm.push(String(e.argv[2]))
    const out = e.argv.includes('--root') ? '/w\n' : e.argv.includes('--agents') ? 'sess-9\tplugin-x\tworking\tclaude\t1\t/repo\tbackground\n' : ''
    return { value: { ...ok, stdout: out } }
  })
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  on('fs.exists', async (_, e) => ({ value: e.path === DIR || files.some(f => e.path === `${DIR}/${(f as { id?: string }).id}.json`) }))
  on('fs.list', async () => ({ value: files.map((f, i) => ({ name: `${(f as { id?: string }).id ?? i}.json`, kind: 'file' as const, size: 1, mtimeMs: 0, isLink: false })) }))
  on('fs.read', async (_, e) => ({ value: e.path.startsWith(CLAIMS) ? claims : JSON.stringify(files.find(f => e.path.endsWith(`/${(f as { id?: string }).id}.json`)) ?? {}) }))
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
  return { ui, rm, calls, prompts, wrote }
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

test('a command this project\'s pane listed stays for the next coordinator once its session has ended', async ($, on) => {
  // sess-9 is live: its command is claimed for this root. sess-gone ended (a handover), its command claimed earlier;
  // sess-old's is no longer there, so its claim goes. No session's command file is rewritten.
  const h = { id: '1'.repeat(16), key: 'plugin-x', session: 'sess-9', cwd: '/repo/.claude/worktrees/x', account: '', command: 'plugin-release x', what: 'Releases it', at: 9000 }
  const gone = { ...h, id: '2'.repeat(16), session: 'sess-gone', command: 'plugin-release y' }
  const elsewhere = { ...gone, id: '3'.repeat(16), command: 'plugin-release z' }
  const { ui, wrote } = await pane($, on, [h, gone, elsewhere], () => ({ result: '' }), `${gone.id}\n${'4'.repeat(16)}\n`)
  expect(wrote.filter(w => w.startsWith(DIR))).toEqual([])
  expect(wrote.filter(w => w.startsWith(CLAIMS)).map(w => w.split('\t')[1]).at(-1)).toBe(`${gone.id}\n${h.id}`)
  expect(await ui.find({ type: 'Text', text: '! plugin-release y' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '! plugin-release z' })).toBeUndefined()
  await ui.unmount()
})

test('a command its session withdrew (its file gone) is not run when Run is pressed before the next read', async ($, on) => {
  const h = { id: '9'.repeat(16), key: 'PROJ-4', session: 'sess-4', cwd: '/w', account: '', command: 'teams-send msg.txt', what: 'Posts the reply', at: 9000 }
  const files: object[] = [h]
  const { ui, calls, prompts } = await pane($, on, files, () => ({ result: '' }))
  expect(await ui.find({ type: 'Text', text: '! teams-send msg.txt' })).toBeDefined()
  files.length = 0 // the session sent it itself on a relayed approval and removed its file
  await ui.press({ key: `hrun-${h.id}` })
  expect(calls).toEqual([])
  expect(prompts).toEqual([])
  expect(await ui.find({ type: 'Text', text: '! teams-send msg.txt' })).toBeUndefined()
  await ui.unmount()
})

test('a refused Run keeps the command with what happened, for another try or Copy', async ($, on) => {
  const h = { id: 'c'.repeat(16), key: 'PROJ-2', session: 'sess-5678', cwd: '/w', account: '/h/.claude-work', command: 'git push origin main', what: 'Pushes main', at: 9000 }
  const { ui, rm, prompts } = await pane($, on, [h], () => ({ deny: 'Permission denied by the user' }))
  expect(await ui.find({ type: 'Text', text: "handed over under /h/.claude-work; it runs under this session's" })).toBeDefined()
  await ui.press({ key: `hrun-${h.id}` })
  expect(rm).toEqual([])
  expect(prompts).toEqual([ranText(h, false, 'refused: Permission denied by the user')]) // the user's own No: no retry
  expect(await ui.find({ type: 'Text', text: 'last run: refused: Permission denied by the user' })).toBeDefined()
  await ui.press({ key: `hdrop-${h.id}` })
  expect(rm).toEqual([`${DIR}/${h.id}.json`])
  await ui.unmount()
})

test('a Run refused for want of a permission prompt asks the coordinator to make the call, where the prompt shows', async ($, on) => {
  const h = { id: 'c'.repeat(16), key: 'PROJ-2', session: 'sess-5678', cwd: '/w', account: '', command: 'make land-5', what: 'Lands it', at: 9000 }
  const { ui, rm, prompts } = await pane($, on, [h], () => ({ deny: 'needs a person approval, which a mod\'s own call cannot ask for' }))
  await ui.press({ key: `hrun-${h.id}` })
  expect(rm).toEqual([])
  expect(prompts).toEqual([retryText(h, 'refused: needs a person approval, which a mod\'s own call cannot ask for')])
  expect(prompts[0]).toContain('Make that Bash call yourself now, this exact command, so your permission prompt asks the user: make land-5.')
  expect(USER_NO.test("The user doesn't want to proceed with this tool use.")).toBe(true)
  await ui.unmount()
})

test('the coordinator withdraws a command its pane lists once it is done another way; a command it does not list finds nothing', async ($, on) => {
  const h = { id: '7'.repeat(16), key: 'PROJ-5', session: 'sess-5', cwd: '/w', account: '', command: 'make land-7', what: 'Lands it', at: 9000 }
  const { ui, rm } = await pane($, on, [h], () => ({ result: '' }))
  expect(await ui.find({ type: 'Text', text: '! make land-7' })).toBeDefined()
  const call = (key: string, command: string) => $.tool.call({ tool: 'mcp__session-orchestration__hand_command', key, command, withdraw: true })
  expect(String((await call('PROJ-5', 'make land-8')).result)).toContain('Nothing to withdraw')
  expect(String((await call('PROJ-5', 'make land-7')).result)).toContain('Withdrawn from the pane (handed over by sess-5)')
  expect(rm).toContain(`${DIR}/${h.id}.json`)
  expect(await ui.find({ type: 'Text', text: '! make land-7' })).toBeUndefined()
  await ui.unmount()
})

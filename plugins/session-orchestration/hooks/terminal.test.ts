import { expect, mock, test } from 'claude-code/testing'

import { openArgs } from './register'

const PANE = { plugin: 'session-orchestration', component: 'Pane', requestId: 'coordinator' } as const
const PROPS = { title: 'Coordinator', isFocused: false, bodyColumns: 160, placement: 'dock', scroll: { offset: 0, bodyRows: 60 }, view: {} } as const
const NOW = Date.UTC(2026, 9, 18, 12, 0)
const S = (minAgo: number) => String(NOW / 1000 - minAgo * 60)

test('session-status --open arguments: the prefix picks the account, plain claude this process\'s', () => {
  expect(openArgs('attach', 'CLAUDE_CONFIG_DIR=~/.claude-work claude attach 22222222', 'w one', '/p/w', undefined))
    .toEqual(['--open', 'view', '--account', '~/.claude-work', 'w one attach', '/p/w', '--', 'claude', 'attach', '22222222'])
  expect(openArgs('logs', 'claude attach 1111', 'x', '', '/home/u/.claude-work'))
    .toEqual(['--open', 'split', '--account', '/home/u/.claude-work', '', '--', 'claude', 'logs', '1111'])
  expect(openArgs('attach', 'env -u CLAUDE_CONFIG_DIR claude attach 1111', 'x', '', '/home/u/.claude-work')).not.toContain('--account')
  expect(openArgs('attach', 'no command here', 'x', '', undefined)).toBeUndefined()
})

const STATUS = `PROJ-4157  Code Review    app#76 OPEN no-human-approval  | no-wt | sess:"fix it" working | Race to settle

Other sessions:
  "w one" blocked 8m — Asked (CLAUDE_CONFIG_DIR=~/.claude-work claude attach 22222222)`

test('with a terminal, Attach in tab leads a waiting card, runs session-status --open, and copies the command when it opens nothing', async ($, on) => {
  mock.clock(on, { now: NOW })
  mock.env(on, {})
  const runs: string[][] = []
  const toasts: string[] = []
  const copied: string[] = []
  let opened = { exitCode: 0, stdout: 'window 1 tab 2 terminal 3\n', stderr: '' }
  let term = 'ghostty'
  on('ui.toast', async (_, e) => {
    toasts.push(String(e.text ?? e))
    return { value: undefined }
  })
  on('ui.copy', async (_, e) => {
    copied.push(e.text)
    return { value: { isCopied: true } }
  })
  const acts = [
    ['1111aaaa-1', 'fix it', 'working', S(1), 'Running', S(5), 'Starting.', '0', '0', 'busy', 'background', '/p/here', 'claude'],
    ['22222222-bbbb', 'w one', 'blocked', S(8), '', '0', 'Asked', '0', '0', 'waiting', 'background', '/p/w', 'CLAUDE_CONFIG_DIR=~/.claude-work claude'],
  ].map(f => f.join('\t')).join('\n')
  on('process.run', async (_, e) => {
    runs.push([...e.argv])
    const out = (r: { exitCode: number; stdout: string; stderr: string }) => ({ value: { ...r, isStdoutTruncated: false, isStderrTruncated: false } })
    const args = e.argv.slice(2)
    if (args[0] === '--open') return out(opened)
    if (args[0] === '--config') return out({ exitCode: 0, stdout: `${term}\n`, stderr: '' })
    return out({ exitCode: 0, stderr: '', stdout: args[0] === '--activity' ? acts : args[0] === '--agents' ? '1111aaaa-1\tfix it\tworking\tclaude\n22222222-bbbb\tw one\tblocked\tCLAUDE_CONFIG_DIR=~/.claude-work claude' : args.length === 0 ? STATUS : '' })
  })
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'refresh' })
  const labels = async () => (await ui.findAll({ type: 'Button' })).filter(b => String(b.key).startsWith('act-')).map(b => b.text)

  // The waiting session: Attach in tab first, in its account and folder.
  await ui.press({ key: 'other-22222222' })
  expect((await labels())[0]).toBe('Attach in tab')
  await ui.press({ key: 'act-t' })
  expect(runs.at(-1)?.slice(2)).toEqual(['--open', 'view', '--account', '~/.claude-work', 'w one attach', '/p/w', '--', 'claude', 'attach', '22222222'])
  expect(toasts.at(-1)).toBe('Attached "w one" in ghostty')

  // Nothing opened (Ghostty not running): the command copied instead, with the terminal's last stderr line; any
  // other failure: its words.
  opened = { exitCode: 2, stdout: 'claude logs 22222222\n', stderr: 'note: ghostty: using ~/.config/x\nGhostty is not running\n' }
  await ui.press({ key: 'act-l' })
  expect(copied.at(-1)).toBe('CLAUDE_CONFIG_DIR=~/.claude-work claude logs 22222222')
  expect(toasts.at(-1)).toBe('Ghostty is not running: copied CLAUDE_CONFIG_DIR=~/.claude-work claude logs 22222222')
  opened = { exitCode: 3, stdout: '', stderr: 'AppleScript error: nope\n' }
  await ui.press({ key: 'act-t' })
  expect(toasts.at(-1)).toBe('ghostty: AppleScript error: nope (exit 3)')

  // A working task's session: the copy Attach first, the tab after it.
  await ui.press({ key: 'task-PROJ-4157' })
  const l = await labels()
  expect(l.indexOf('Attach')).toBeLessThan(l.indexOf('Attach in tab'))

  // The plain terminal: only the copy Attach.
  term = 'plain'
  await ui.press({ key: 'refresh' })
  await ui.press({ key: 'other-22222222' })
  expect(await labels()).not.toContain('Attach in tab')
  expect(await labels()).not.toContain('Logs in split')
  expect(await labels()).toContain('Attach')
  await ui.unmount()
})

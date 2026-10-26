import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

import { HIDDEN_BY_MARKDOWN, byKind, kindCounts, attachFor, clip, fixesOf, groupOf, keyIn, leftoverCommand, notice, wrapText, facts, orderTasks, parsePending, parseStatus, parseTask, pendingOf, prsOf, BUILTIN_KEYS, USAGE_EXTRA, usageName } from './register'

test('status rows parse whatever the columns hold', async () => {
  const pad = (k: string, st: string) => `${k.padEnd(9)} ${st.padEnd(14)} `
  expect(parseTask(`${pad('A-1', 'Selected for Development')}| no-wt | sess:—`)).toMatchObject({ status: 'Selected for Development', extra: '' })
  expect(parseTask(`${pad('A-2', '')}app#1 OPEN  | no-wt | sess:—`)).toMatchObject({ status: '', extra: 'app#1 OPEN' })
  expect(parseTask(`${pad('A-3', '-')}no-wt | sess:—`)).toMatchObject({ status: '' })
  expect(parseTask(`${pad('A-4', 'Open')}no-wt | sess:"fix it" idle | Fix "foo" bar`))
    .toMatchObject({ sess: { name: 'fix it', state: 'idle' }, title: 'Fix "foo" bar' })
  // A guess isn't an owner: the row has no session, the guess kept aside.
  expect(parseTask(`${pad('A-6', 'Open')}no-wt | sess:— (maybe 61c8fb76: 12 mentions) | Spike`))
    .toMatchObject({ sess: { name: '', state: 'none', maybe: '61c8fb76: 12 mentions' }, title: 'Spike' })
  const st = parseStatus(`${pad('A-5', 'Open')}no-wt | sess:"s" idle | Spike: options:`)
  expect(st.tasks.map(t => t.key)).toEqual(['A-5'])
  expect(st.sections).toEqual([])
  expect(orderTasks(st.tasks).map(t => t.key)).toEqual(['A-5'])
  expect(parsePending('- one\n\n## Log\n- 2026-01-01 carried 1')?.map(p => p.text)).toEqual(['one'])
})

const PANE = { plugin: 'session-orchestration', component: 'Pane', requestId: 'coordinator' } as const
const PROPS = { title: 'Coordinator', isFocused: false, bodyColumns: 120, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} } as const

test('open_pane says when the folder is not set up for coordination', async ($, on) => {
  mock.clock(on)
  const renamed: string[] = []
  on('command.run', { command: 'rename' }, async (_, e) => {
    renamed.push(e.args)
    return { text: 'renamed' }
  })
  on('turn.complete', async () => ({ text: '' }))
  // under /work's adapter: --root is the parent until this folder gets its own
  let check = { exitCode: 3, stdout: 'covered by a parent: /work (work-coordinator) covers this folder\n' }
  let rootDir = '/work'
  on('process.run', async (_, e) => ({ value: {
    ...(e.argv.includes('--check') ? check : { exitCode: 0, stdout: e.argv.includes('--root') ? rootDir : '' }),
    stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
  }))
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  const kept = 'This session keeps its name until the folder is set up; open_pane names it then.'
  const c = await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  expect(c.result).toBe(`Coordinator pane open. ${kept} This folder is covered by a parent: /work (work-coordinator) covers this folder. Tell the user, and ask whether this folder gets a coordinator of its own; if they meant the parent's project, its coordinator runs from there (skill setting-up-coordination).`)
  check = { exitCode: 1, stdout: 'unconfigured: /work/scratch has no adapter and no replies folder line\n' }
  const r = await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  expect(r.result).toBe(`Coordinator pane open. ${kept} Not set up for coordination (unconfigured: /work/scratch has no adapter and no replies folder line): run session-status --init and propose the setup (skill setting-up-coordination).`)
  // set up (--write --own): the root moved to the folder, and open_pane names it after the folder, not the parent
  check = { exitCode: 0, stdout: 'configured: /work/scratch (scratch-coordinator)\nactive: tracker=none host=github delegate=off\n' }
  rootDir = '/work/scratch'
  const d = await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  expect(d.result).toBe('Coordinator pane open. This session becomes "scratch-coordinator" when this turn ends: put that name in briefs. Coordination config: active: tracker=none host=github delegate=off.')
  await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
  expect(renamed).toEqual(['scratch-coordinator'])
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'refresh' }) // joins the sweep the open started
  await ui.unmount()
})

test('open_pane names the coordinator <project>-coordinator', async ($, on) => {
  mock.clock(on)
  const renamed: string[] = []
  on('command.run', { command: 'rename' }, async (_, e) => {
    renamed.push(e.args)
    return { text: 'renamed' }
  })
  on('process.run', async (_, e) => ({ value: {
    exitCode: 0, stdout: e.argv.includes('--root') ? '/work/myproj' : '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
  }))
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  on('turn.complete', async () => ({ text: '' }))
  const r = await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  expect([renamed, r.result]).toEqual([[], 'Coordinator pane open. This session becomes "myproj-coordinator" when this turn ends: put that name in briefs.'])
  const end = { answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' } as const
  await $.turn.complete(end)
  await $.turn.complete({ ...end, turnId: 't2' })
  expect(renamed).toEqual(['myproj-coordinator']) // once
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'refresh' }) // joins the sweep the open started
  await ui.unmount()
})

test('name_session renames any session at turn end and refuses a bad name', async ($, on) => {
  const renamed: string[] = []
  on('command.run', { command: 'rename' }, async (_, e) => {
    renamed.push(e.args)
    return { text: 'renamed' }
  })
  on('turn.complete', async () => ({ text: '' }))
  const call = (name: unknown) => $.tool.call({ tool: 'mcp__session-orchestration__name_session', name })
  const bad = await Promise.all(['PROJ-1 fix', '', 'x'.repeat(65), 'a/b', 42, '-n', 'myproj-coordinator'].map(call))
  expect(bad.map(r => r.deny !== undefined)).toEqual([true, true, true, true, true, true, true])
  const sub = await $.tool.call({ tool: 'mcp__session-orchestration__name_session', name: 'PROJ-9-x', agentId: 'a1' })
  expect(sub.deny).toBeDefined()
  const r = await call('PROJ-1234-fix-settler')
  expect([renamed, r.result]).toEqual([[], 'This session becomes "PROJ-1234-fix-settler" when this turn ends.'])
  const end = { answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' } as const
  await $.turn.complete(end)
  await $.turn.complete({ ...end, turnId: 't2' })
  expect(renamed).toEqual(['PROJ-1234-fix-settler']) // once
})

test('a queued approval becomes buttons; a click submits the answer once and clears it', async ($, on) => {
  mock.clock(on)
  const submitted: string[] = []
  on('prompt.submit', async (_, e) => {
    submitted.push(e.text)
    return { text: e.text }
  })
  on('process.run', async (_, e) => ({ value: {
    exitCode: 0, stdout: e.argv.includes('--pending') ? 'PENDING TEXT' : 'STATUS TEXT', stderr: '',
    isStdoutTruncated: false, isStderrTruncated: false },
  }))
  on('ui.open', async () => ({ value: { isPlaced: true } }))

  const bad = await $.tool.call({ tool: 'mcp__session-orchestration__ask_approval', key: 'ABC-1', question: 'q', options: ['only one'] })
  expect(bad.deny).toBeDefined()
  await $.tool.call({
    tool: 'mcp__session-orchestration__ask_approval', key: 'ABC-1', question: 'Merge ABC-1\n(PR #5)?',
    options: ['Yes, merge ABC-1', "No, don't merge ABC-1"],
  })

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  expect(await ui.find({ type: 'Button', text: 'Yes, merge ABC-1' })).toBeDefined()
  await ui.press({ key: 'ask-1-0' })
  expect(submitted).toEqual(['Approval pane answer for ABC-1: Yes, merge ABC-1. Asked: Merge ABC-1 (PR #5)?'])
  await ui.unmount()

  const again = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  expect(await again.find({ type: 'Button', text: 'Yes, merge ABC-1' })).toBeUndefined()
  expect(await again.find({ type: 'Text', text: 'STATUS TEXT' })).toBeDefined()
  expect(await again.find({ type: 'Text', text: 'PENDING TEXT' })).toBeDefined()
})

const STATUS = `PROJ-4157  Code Review    app#76 OPEN no-human-approval  | wt dirty:0 unpushed:0 | sess:— | Race to settle
PROJ-4679  In Development app#236 OPEN CONFLICT  | wt dirty:2 unpushed:1 | sess:"pr review proj-4679" blocked | Decisive automap
PROJ-4842  Code Review    app#258 OPEN  | no-wt | sess:e9d81c83 closed 26h | Extend settler

Waiting on you:
  "pr review proj-4679" (CLAUDE_CONFIG_DIR=~/.claude-work claude attach 61c8fb76) — blocked: Bash \`touch x\`

Notices:
  * mail      Accountant: pay the levy`
const PENDING = `# Pending

Intro paragraph.

- 2026-10-05 PROJ-4679 (#236): waiting on
  a prod release.
- 2026-10-07 PROJ-4842 all done.

## Handoff log
2026-09-29 carried 2`

const URLS = 'ticket https://jira.example/browse/{key}\npr https://bb.example/repos/{repo}/pull-requests/{id}'
const AGENTS = '61c8fb76-aaaa\tpr review proj-4679\tblocked\tCLAUDE_CONFIG_DIR=~/.claude-work claude'
const ROW_4679 = 'PROJ-4679  In Development app#236 OPEN +Ann  | no-wt | sess:"pr review proj-4679" idle | Decisive automap'
const LEFTOVER = '\nLeftovers (task finished):\n  PROJ-4177 Done — session "old": claude stop 18a61163'

function sweep(on: On, status = STATUS) {
  const runs: string[][] = []
  on('process.run', async (_, e) => {
    runs.push(e.argv.slice(2))
    const arg = e.argv[2]
    const stdout = arg === '--pending' ? PENDING : arg === '--urls' ? URLS : arg === '--agents' ? AGENTS : arg === 'PROJ-4679' ? ROW_4679 : status
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  return runs
}

test('rows say what they wait on in plain words; a section title toggles wrapping', async ($, on) => {
  mock.clock(on)
  sweep(on, `${STATUS}\nPROJ-5131  Code Review    app#269 MERGED   | no-wt | sess:— | Tighten docs${LEFTOVER}`)
  await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'refresh' }) // joins the sweep the open started
  // PROJ-4679 is blocked, has a session waiting and a pending item: one thing on the user.
  expect(await ui.find({ type: 'Text', text: /^◆ +1 on you +4 tasks · 2 pending$/ })).toBeDefined()
  const row = async (key: string) => [
    (await ui.find({ type: 'Button', key: `${key}:lead` }))?.text, (await ui.find({ type: 'Button', key }))?.text,
  ]
  // the session row drew PROJ-4679's solid chip; its task row repeats it in words
  expect(await row('task-PROJ-4679')).toEqual([' NEEDS YOU    ', 'PROJ-4679 merge conflict, 1 unpushed commit (In Development) Decisive automap'])
  expect(await row('task-PROJ-4157')).toEqual([' '.repeat(15), 'PROJ-4157 Race to settle']) // the In review heading says it
  expect(await row('task-PROJ-5131')).toEqual([' MERGED       ', 'PROJ-5131 not yet Ready for Test (Code Review) Tighten docs'])
  expect(await row('task-PROJ-4842')).toEqual([' CODE REVIEW  ', 'PROJ-4842 Extend settler']) // nothing known: the status
  expect(await row('wait-61c8fb76')).toEqual(['● SESSION  ', 'PROJ-4679 pr review blocked: Bash `touch x`']) // the engine draws its hotkey, `1: `, before it
  expect(await row('Notices-mail      Accountant: pay the levy')).toEqual([' MAIL         ', 'Accountant: pay the levy'])
  expect((await row('pend-PROJ-4679 (#236): waiting on a prod release.'))[1]).toBe('PROJ-4679 (#236): waiting on a prod release.')
  expect(await ui.find({ type: 'Text', text: /carried/ })).toBeUndefined()
  await ui.press({ key: 'sec-Pending' })
  expect(await ui.find({ type: 'Text', text: /▾/ })).toBeDefined()
  await ui.unmount()
})

test('a selected task shows its details and actions: attach, links, refresh, ask', async ($, on) => {
  mock.clock(on)
  const runs = sweep(on)
  const copied: string[] = []
  on('ui.copy', async (_, e) => {
    copied.push(e.text)
    return { value: { isCopied: true } }
  })
  const submitted: string[] = []
  const origins: unknown[] = []
  on('prompt.submit', async (_, e) => {
    submitted.push(e.text)
    origins.push(e.origin)
    return { text: e.text }
  })
  await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'refresh' })

  expect(await ui.find({ type: 'Button', key: 'act-k' })).toBeUndefined()
  await ui.press({ key: 'task-PROJ-4679' })
  expect(await ui.find({ type: 'Text', text: /In Development · app#236 OPEN CONFLICT · wt 2 dirty 1 unpushed · pr review proj-4679 blocked/ })).toBeDefined()
  expect((await ui.find({ type: 'Link', text: 'PROJ-4679' }))?.props.href).toBe('https://jira.example/browse/PROJ-4679')
  expect((await ui.find({ type: 'Link', text: 'app#236' }))?.props.href).toBe('https://bb.example/repos/app/pull-requests/236')
  await ui.press({ key: 'act-a' })
  expect(copied).toEqual(['CLAUDE_CONFIG_DIR=~/.claude-work claude attach 61c8fb76'])
  await ui.press({ key: 'act-k' })
  expect(submitted).toEqual(['Coordinator pane: where does task PROJ-4679 (session blocked on you, merge conflict, 1 unpushed commit) stand, and what\'s next? Answer briefly.'])
  expect(submitted[0]?.startsWith('Approval pane answer for ')).toBe(false)
  expect(origins).toEqual([{ kind: 'plugin', name: 'session-orchestration' }]) // the plugin's prompt, not asUser

  await ui.press({ key: 'act-u' })
  expect(runs.at(-1)).toEqual(['PROJ-4679'])
  expect((await ui.find({ type: 'Button', key: 'task-PROJ-4679' }))?.text).toBe('PROJ-4679 approved by Ann (In Development) Decisive automap')
  expect((await ui.find({ type: 'Button', key: 'task-PROJ-4157:lead' }))?.text).toBe(' '.repeat(15)) // other rows stay
  await ui.press({ key: 'task-PROJ-4679' }) // pressed again: deselected
  expect(await ui.find({ type: 'Button', key: 'act-u' })).toBeUndefined()
  await ui.unmount()
})

test('a notice can be dismissed; a leftover\'s command copied', async ($, on) => {
  mock.clock(on)
  sweep(on, `${STATUS}${LEFTOVER}`)
  const copied: string[] = []
  on('ui.copy', async (_, e) => {
    copied.push(e.text)
    return { value: { isCopied: true } }
  })
  await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'refresh' })
  await ui.press({ key: 'Notices-mail      Accountant: pay the levy' })
  await ui.press({ key: 'act-x' })
  expect(await ui.find({ type: 'Text', text: /pay the levy/ })).toBeUndefined()
  expect(await ui.find({ type: 'Button', key: 'sec-Notices' })).toBeUndefined()
  await ui.press({ key: 'Leftovers (task finished)-PROJ-4177 Done — session "old": claude stop 18a61163' })
  await ui.press({ key: 'act-c' })
  expect(copied).toEqual(['claude stop 18a61163'])
  await ui.unmount()
})

test('a stale prompt is listed apart, not counted on you, with Stop', async ($, on) => {
  mock.clock(on)
  const stale = '\n\nStale prompts:\n  "probe" (claude attach 91d21a06) — blocked: Bash `curl x` · unanswered 7h; stop: claude stop 91d21a06'
  sweep(on, `${STATUS}${stale}`)
  const copied: string[] = []
  on('ui.copy', async (_, e) => {
    copied.push(e.text)
    return { value: { isCopied: true } }
  })
  await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'refresh' })
  expect((await ui.find({ type: 'Button', key: 'sec-Stale prompts' }))?.text).toMatch(/STALE PROMPTS 1 /)
  expect((await ui.find({ type: 'Button', key: 'sec-Waiting on you' }))?.text).toMatch(/WAITING ON YOU 1 /)
  expect((await ui.find({ type: 'Button', key: 'wait-91d21a06:lead' }))?.text).toBe(' STALE        ')
  await ui.press({ key: 'wait-91d21a06' })
  await ui.press({ key: 'act-s' })
  expect(copied).toEqual(['claude stop 91d21a06'])
  await ui.unmount()
})

test('facts read the adapter\'s words', async () => {
  const t = (extra: string, status = 'Code Review', wt = '') =>
    facts({ key: 'A-1', status, extra, wt, sess: { name: '', state: 'none', maybe: '' }, title: '' }).map(f => f.text)
  expect(t('app#1 OPEN !Bob,+ann.smith')).toEqual(['changes asked by Bob', 'approved by ann.smith'])
  expect(t('app#1 OPEN +1 no-conflict conflicting')).toEqual(['']) // no reviewer named 1, no conflict
  expect(t('app#12 OPEN · changes requested by 8bob · approved by ann · mergeable'))
    .toEqual(['changes asked by 8bob', 'approved by ann'])
  expect(t('app#1 OPEN CONFLICT')).toEqual(['merge conflict'])
  expect(t('app#1 MERGED | ↩09-14 Nikolay→CR, since: #1 merged, 0 comment(s) → RfT if deployed |'))
    .toEqual(['sent back by Nikolay', 'not yet Ready for Test'])
  expect(t('app#1 MERGED', 'Ready for Test')).toEqual([''])
  expect(t('app#1 OPEN no-human-approval | (PRs as of 09:12) |')).toEqual(['needs human review', 'PR info from 09:12'])
  expect(prsOf({ key: 'A-1', status: '', extra: 'app#1 OPEN  web#22 MERGED', wt: '', sess: { name: '', state: 'none', maybe: '' }, title: '' }))
    .toEqual([{ repo: 'app', id: '1', state: 'OPEN' }, { repo: 'web', id: '22', state: 'MERGED' }])
  expect(pendingOf('PROJ-1 (#2): waiting on the user: a release')).toEqual({ key: 'PROJ-1', onYou: true })
  expect(pendingOf('all done, waiting on review')).toEqual({ key: undefined, onYou: false })
  expect(attachFor('aaaaaaaa-1\tdup\tidle\tclaude\nbbbbbbbb-2\tdup\tidle\tclaude', 'dup')).toBeUndefined() // ambiguous: none
  expect(attachFor('aaaaaaaa-1\tone\tidle\tclaude', 'one')).toBe('claude attach aaaaaaaa')
})

test('a cut row ends in an ellipsis and never overruns', () => {
  const text = (segs: [string, unknown?][]) => segs.map(([t]) => t).join('')
  expect(text(clip([['PROJ-1 '], ['merge conflict', {}], [' Title']], 13))).toBe('PROJ-1 merge…')
  expect(text(clip([['abc'], ['def']], 6))).toBe('abcdef')
  expect(text(clip([['abc '], ['def']], 4))).toBe('abc…')
  expect(text(clip([['abcdef']], 0))).toBe('')
})

test('detail text wraps at spaces within the width', () => {
  expect(wrapText('aa bb cc', 5)).toEqual(['aa bb', 'cc'])
  expect(wrapText('abcdefgh ij', 4)).toEqual(['abcd', 'efgh', 'ij']) // a long word is broken, nothing lost
  expect(wrapText('', 4)).toEqual([])
})

test('WAITING ON YOU lists what the header counts: sessions, pending items on you a live session is behind; DECISIONS the rest', async ($, on) => {
  mock.clock(on)
  const pending = '- 2026-10-05 PROJ-3849 (#224): on you: reply to a review.\n- 2026-10-05 PROJ-4679 your call: prod data.\n- 2026-10-06 docs-audit (61c8fb76): on you: pick findings.'
  on('process.run', async (_, e) => {
    const arg = e.argv[2]
    const stdout = arg === '--pending' ? pending : arg === '--urls' ? URLS : arg === '--agents' ? AGENTS : STATUS
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  const statuses: (string | undefined)[] = []
  on('ui.status', async (_, e) => {
    statuses.push(e.text)
    return { value: undefined }
  })
  await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'refresh' })
  expect(await ui.find({ type: 'Text', text: /^◆ +3 on you / })).toBeDefined()
  expect(statuses.at(-1)).toBe('◆ 3 on you · /coordinator') // the header's count, under the prompt too
  expect((await ui.find({ type: 'Button', key: 'sec-Waiting on you' }))?.text).toMatch(/WAITING ON YOU 2 /)
  expect(await ui.find({ type: 'Text', text: /blocked: Bash `touch x`/ })).toBeDefined() // what it waits on (hooks/blocked.sh)
  // names a live session: under Waiting on you, numbered after the session
  expect((await ui.find({ type: 'Button', key: 'on-docs-audit (61c8fb76): on you: pick findings.:lead' }))?.props.hotkey).toBe('2')
  // no live session behind it (no row, no live id): DECISIONS, numbered on
  expect((await ui.find({ type: 'Button', key: 'sec-Decisions' }))?.text).toMatch(/DECISIONS 1 /)
  const top = await ui.find({ type: 'Button', key: 'on-PROJ-3849 (#224): on you: reply to a review.:lead' })
  expect([top?.text, top?.props.hotkey]).toEqual(['● PENDING  ', '3'])
  await ui.press({ key: 'on-PROJ-3849 (#224): on you: reply to a review.' })
  expect((await ui.find({ type: 'Button', key: 'on-PROJ-3849 (#224): on you: reply to a review.:lead' }))?.text).toBe('● PENDING  ') // the card marks it, the lead stays
  expect((await ui.find({ type: 'Button', key: 'pend-PROJ-3849 (#224): on you: reply to a review.:lead' }))?.text).toBe(' ON YOU       ') // the repeat, in words
  expect(await ui.find({ type: 'Button', key: 'on-PROJ-4679 your call: prod data.' })).toBeUndefined() // its session is listed
  await ui.unmount()
})

test('notices, leftovers and session names read only what they mean', () => {
  expect(notice('mail      Accountant: pay the levy')).toEqual({ label: 'mail', text: 'Accountant: pay the levy' })
  expect(notice('teams DM  Ann: hi')).toEqual({ label: 'DM', text: 'Ann: hi' })
  expect(notice('Accountant: pay the levy  by Friday').label).toBe('note') // no source column
  expect(leftoverCommand('PROJ-1 Done — session "fix: login": claude stop abcd1234')).toBe('claude stop abcd1234')
  expect(leftoverCommand('PROJ-2 Done — worktree clean+merged: git -C app worktree remove x')).toBe('git -C app worktree remove x')
  const keys = new Set(['PROJ-4679'])
  expect(keyIn('pr review proj-4679', keys)).toBe('PROJ-4679')
  expect(keyIn('try claude-3 prompt', keys)).toBeUndefined()
})

const RUN = { command: 'coordinator', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 110 } } as const
test('/coordinator opens the pane (at any width: the person asked); /coordinator close closes it', async ($, on) => {
  mock.clock(on)
  on('process.run', async () => ({ value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  const events: string[] = []
  on('ui.open', async (_, e) => {
    events.push(`open ${e.id}`)
    return { value: { isPlaced: true } }
  })
  on('ui.close', async (_, e) => {
    events.push(`close ${e.id}`)
    return { value: undefined }
  })
  expect((await $.command.run({ ...RUN, args: '' })).text).toBe('Coordinator pane open.')
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'refresh' }) // joins the sweep the open started
  await ui.unmount()
  expect((await $.command.run({ ...RUN, args: 'Close' })).text).toBe('Coordinator pane closed.')
  expect((await $.command.run({ ...RUN, args: 'clsoe' })).text).toMatch(/^Unknown argument "clsoe"/)
  expect(events).toEqual(['open coordinator', 'close coordinator'])
})

test('tasks group as Projects\' Overview does: needs action, in review, working, landing, idle', () => {
  const g = (extra: string, state = 'none') => groupOf({ key: 'A-1', status: 'Code Review', extra, wt: '', sess: { name: 's', state, maybe: '' }, title: '' })
  expect(g('app#1 OPEN +Ann')).toBe('Landing')
  expect(g('app#12 OPEN · changes requested by 8bob · mergeable')).toBe('Needs action')
  expect(g('app#12 OPEN · approved by 8bob · mergeable')).toBe('Landing')
  expect(g('app#1 OPEN +ci-bot no-human-approval')).toBe('In review') // a review still due
  expect(g('app#1 OPEN +Ann CONFLICT')).toBe('Needs action') // approved, but something to fix first
  expect(g('app#1 OPEN no-human-approval')).toBe('In review')
  expect(g('app#1 OPEN no-human-approval', 'working')).toBe('Working')
  expect(g('app#1 MERGED', 'idle')).toBe('Needs action') // merged, not yet Ready for Test
  expect(g('')).toBe('Idle')
  const fx = (extra: string) => fixesOf(facts({ key: 'A-1', status: 'Code Review', extra, wt: '', sess: { name: '', state: 'none', maybe: '' }, title: '' })).map(f => f.label)
  expect(fx('app#1 OPEN !Bob CONFLICT CI-FAILED | ↩09-14 Ann→CR |')).toEqual(['Resolve conflicts', 'Fix CI', 'Address comments'])
  expect(fx('app#1 MERGED | ↩09-14 Ann→CR |')).toEqual([]) // a send-back isn't PR comments
  expect(fx('app#1 OPEN +Ann')).toEqual([])
})

const RESOLVED_STATUS = `PROJ-4157  Code Review    app#76 OPEN +Ann CI-FAILED  | no-wt | sess:"fix 4157" idle | Race to settle
PROJ-4842  Code Review    app#258 OPEN +Ann  | no-wt | sess:— | Extend settler

Resolved (idle a week):
  PROJ-4177 Done — session "old": claude stop 18a61163`

test('a task card offers the fixes that apply and sends them through the coordinator; Resolved opens on press', async ($, on) => {
  mock.clock(on)
  sweep(on, RESOLVED_STATUS)
  const submitted: string[] = []
  on('prompt.submit', async (_, e) => {
    submitted.push(e.text)
    return { text: e.text }
  })
  await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'refresh' })
  expect((await ui.find({ type: 'Button', key: 'sec-Needs action' }))?.text).toMatch(/NEEDS ACTION 1 /)
  expect((await ui.find({ type: 'Button', key: 'sec-Landing' }))?.text).toMatch(/LANDING 1 /)
  expect(await ui.find({ type: 'Button', key: 'sec-Tasks' })).toBeUndefined()
  await ui.press({ key: 'task-PROJ-4157' })
  expect(await ui.find({ type: 'Button', key: 'act-o' })).toBeUndefined() // no conflict: no Resolve conflicts
  await ui.press({ key: 'act-f' })
  expect(submitted).toEqual(['Coordinator pane action for PROJ-4157: tell the session that owns it to fix the failing CI build (app#76). Relay it per coordinator.md (Card actions).'])
  // Resolved: its count, its items only once pressed.
  expect((await ui.find({ type: 'Button', key: 'sec-Resolved (idle a week)' }))?.text).toMatch(/RESOLVED \(IDLE A WEEK\) 1 ▸/)
  expect(await ui.find({ type: 'Text', text: /18a61163/ })).toBeUndefined()
  await ui.press({ key: 'sec-Resolved (idle a week)' })
  expect(await ui.find({ type: 'Text', text: /18a61163/ })).toBeDefined()
  await ui.unmount()
})

test('asks group per key, one line each until opened; an open ask shows its body file as markdown and its sha256', async ($, on) => {
  mock.clock(on)
  const submitted: string[] = []
  on('prompt.submit', async (_, e) => {
    submitted.push(e.text)
    return { text: e.text }
  })
  on('process.run', async () => ({ value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  // '## Nit\n\nUse `foo()` here.' then an ESC [31m and a newline
  on('fs.read', async () => ({ value: { base64: 'IyMgTml0CgpVc2UgYGZvbygpYCBoZXJlLhtbMzFtCg==' } }))
  const sha = 'fb45bdda1ae27282b4844fa4afa557cbcc9621cefc02ce030fa715a27e31006c'
  const ask = (key: string, question: string, extra = {}) => $.tool.call({
    tool: 'mcp__session-orchestration__ask_approval', key, question, options: [`Yes, ${question}`, `No, ${key}`], ...extra,
  })

  const wrong = await ask('PROJ-1', `post comment /tmp/c.md on app#2 (sha256 ${'0'.repeat(64)})`, { body_file: '/tmp/c.md', kind: 'issue' })
  expect(wrong.deny).toMatch(/must name its sha256 \(fb45bdda/)
  expect((await ask('PROJ-1', 'post comment /tmp/c.md on app#2', { body_file: '/tmp/c.md', kind: 'issue' })).deny).toMatch(/must name its sha256/)
  expect((await ask('PROJ-1', 'post', { body_file: 'rel.md' })).deny).toBeDefined()
  await ask('PROJ-1', `post comment /tmp/c.md on app#2 (sha256 ${sha})`, { body_file: '/tmp/c.md', kind: 'issue', target: 'app#2 src/a.ts:42', details: 'Replies to **the reviewer**' })
  await ask('PROJ-1', 'merge app#2')
  await ask('PROJ-2', 'merge app#3')

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  expect((await ui.find({ type: 'Text', text: /APPROVE/ }))?.text).toBe(' ⚑ APPROVE 3  3 new')
  expect((await ui.find({ type: 'Button', key: 'askgrp-PROJ-1' }))?.text).toMatch(/^▸ PROJ-1 2 asks · 1 issue · 2 new · /)
  expect(await ui.find({ type: 'Button', key: 'askrow-1' })).toBeUndefined() // groups start closed
  await ui.press({ key: 'askgrp-PROJ-1' })
  expect((await ui.find({ type: 'Button', key: 'askrow-1' }))?.text).toMatch(/^▸ NEW  ISSUE  post comment \/tmp\/c\.md on app#2 \(sha256 fb45bdda…\) /)
  expect(await ui.find({ type: 'Button', key: 'ask-1-0' })).toBeUndefined() // asks start closed
  await ui.press({ key: 'askrow-1' })
  expect((await ui.find({ type: 'Markdown', key: 'askbody-1' }))?.props.text).toBe('## Nit\n\nUse `foo()` here.\\x1b[31m\n') // the ESC shown, not sent
  expect((await ui.find({ type: 'Markdown', key: 'askdetails-1' }))?.props.text).toBe('Replies to **the reviewer**')
  expect(await ui.find({ type: 'Text', text: `body /tmp/c.md · sha256 ${sha}` })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'target app#2 src/a.ts:42' })).toBeDefined()
  expect((await ui.find({ type: 'Button', key: 'askgrp-PROJ-1' }))?.text).toMatch(/^▾ PROJ-1 2 asks · 1 issue · 1 new · /)
  await ui.press({ key: 'ask-1-0' })
  expect((await ask('PROJ-3', `merge app#4 (sha256 ${sha})`)).deny).toMatch(/pass it as body_file/)
  expect((await ask('PROJ-3', 'merge app#4', { options: ['Yes\u202e', 'No'] })).deny).toMatch(/control or bidi/)
  // The answer line is unchanged: the option, then the question in full, sha256 and all.
  expect(submitted).toEqual([`Approval pane answer for PROJ-1: Yes, post comment /tmp/c.md on app#2 (sha256 ${sha}). Asked: post comment /tmp/c.md on app#2 (sha256 ${sha})`])
  // PROJ-1's last ask is alone in its open group: drawn open, so seen; PROJ-2's group stays closed.
  expect(await ui.find({ type: 'Button', key: 'ask-2-0' })).toBeDefined()
  expect((await ui.find({ type: 'Text', text: /APPROVE/ }))?.text).toBe(' ⚑ APPROVE 2  1 new')
  await ui.unmount()
})

test('a body markdown would hide parts of is drawn as written', () => {
  expect(['[docs](https://x.example)', '[a]: https://x.example', 'hi <!-- @x -->', '<img src=x>'].every(s => HIDDEN_BY_MARKDOWN.test(s))).toBe(true)
  expect(['## Nit\n\nUse `foo()` here.', 'a < b and [x] done', 'see https://x.example'].some(s => HIDDEN_BY_MARKDOWN.test(s))).toBe(false)
})

test('a review finding post names its kind; a group lists its other asks, then issues, suggestions, questions, and counts them', async ($, on) => {
  mock.clock(on)
  on('process.run', async () => ({ value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  on('fs.read', async () => ({ value: { base64: 'IyMgTml0CgpVc2UgYGZvbygpYCBoZXJlLhtbMzFtCg==' } }))
  const sha = 'fb45bdda1ae27282b4844fa4afa557cbcc9621cefc02ce030fa715a27e31006c'
  const post = (kind?: string) => $.tool.call({
    tool: 'mcp__session-orchestration__ask_approval', key: 'PROJ-1', question: `post${kind === undefined ? '' : ` ${kind}`} comment /tmp/c.md on app#2 (sha256 ${sha})`,
    options: ['Yes, post it', 'No, PROJ-1'], body_file: '/tmp/c.md', ...(kind === undefined ? {} : { kind }),
  })
  expect((await post()).deny).toBeUndefined() // a post that isn't a review finding: no kind, no badge
  expect((await post('nit')).deny).toMatch(/kind is one of/)
  await post('question')
  await post('issue')
  await post('suggestion')
  await post('question')
  const merge = (extra = {}) => $.tool.call({ tool: 'mcp__session-orchestration__ask_approval', key: 'PROJ-1', question: 'merge app#2', options: ['Yes, merge', 'No, PROJ-1'], ...extra })
  expect((await merge({ kind: 'issue' })).deny).toMatch(/goes with body_file/)
  await merge()

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  expect((await ui.find({ type: 'Button', key: 'askgrp-PROJ-1' }))?.text).toMatch(/^▾ PROJ-1 6 asks · 1 issue · 1 suggestion · 2 questions · 6 new · /)
  // As drawn: the kindless post and the merge in queue order, then issues, suggestions, questions.
  const rows = (await ui.findAll({ type: 'Button', text: /^▸ NEW / })).map(r => r.text.match(/^▸ NEW  (\w+)/)?.[1] ?? 'none')
  expect(rows).toEqual(['none', 'none', 'ISSUE', 'SUGGESTION', 'QUESTION', 'QUESTION'])
  const ids = (as: { id: string }[]) => as.map(a => a.id)
  const a = (id: string, kind?: 'issue' | 'suggestion' | 'question') => ({ id, key: 'K', question: 'q', options: [], at: 0, ...(kind ? { kind } : {}) })
  expect(ids(byKind([a('1', 'question'), a('2'), a('3', 'issue'), a('4', 'suggestion'), a('5', 'issue')]))).toEqual(['2', '3', '5', '4', '1'])
  expect(kindCounts([a('1', 'question'), a('2', 'question'), a('3', 'issue')]).map(c => c.text)).toEqual(['1 issue', '2 questions'])
  await ui.unmount()
})

test('cancel_approval removes asks by key, by id or by question, and a stale click on one submits nothing', async ($, on) => {
  mock.clock(on)
  const submitted: string[] = []
  const cancel = (key: string, extra = {}) => $.tool.call({ tool: 'mcp__session-orchestration__cancel_approval', key, ...extra })
  let late: unknown
  const toasts: string[] = []
  on('ui.toast', async (_, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  on('prompt.submit', async (_, e) => {
    // A cancel while this click's submit is pending, and the submit fails: the ask stays withdrawn.
    if (e.text.includes('race app#9')) {
      late = (await cancel('PROJ-3')).result
      throw new Error('not delivered')
    }
    if (e.text.includes('flaky app#8')) throw new Error('not delivered')
    submitted.push(e.text)
    return { text: e.text }
  })
  on('process.run', async () => ({ value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  const ask = (key: string, question: string) => $.tool.call({
    tool: 'mcp__session-orchestration__ask_approval', key, question, options: [`Yes, ${question}`, `No, ${key}`],
  })
  let cancelled: unknown
  on('ui.press', async (_, e, next) => {
    if (e.element === 'ask-6-0') cancelled = (await cancel('PROJ-2')).result
    return next(e)
  })

  expect((await ask('IVAN-1', 'create IVAN-1 a')).result).toMatch(/^Queued IVAN-1 \(id 1\) /)
  await ask('IVAN-1', 'create IVAN-1 b')
  await ask('IVAN-1', 'create IVAN-1 a+b')
  await ask('PROJ-2', 'merge app#3')
  expect((await cancel('IVAN-1', { question: 'create IVAN-1 b' })).result).toBe('Removed 1 ask for IVAN-1: (id 2) create IVAN-1 b.')
  expect((await cancel('IVAN-1', { id: 1 })).result).toBe('Removed 1 ask for IVAN-1: (id 1) create IVAN-1 a.')
  expect((await cancel('IVAN-1', { id: '1' })).result).toBe('No queued ask matched IVAN-1 id 1.')
  expect((await cancel('PROJ-2', { question: 'nope' })).result).toBe('No queued ask matched PROJ-2 "nope".')
  expect((await cancel(' ')).deny).toBeDefined()
  // A blank id or question is not given, but blanks alone don't widen to every ask; id wins over question, said.
  expect((await cancel('PROJ-2', { id: '', question: ' ' })).deny).toMatch(/key alone/)
  expect((await cancel('PROJ-2', { id: '', question: 'merge app#3' })).result).toBe('Removed 1 ask for PROJ-2: (id 4) merge app#3.')
  await ask('PROJ-2', 'merge app#3')
  expect((await cancel('PROJ-2', { id: '5', question: 'merge app#3 (as shown)' })).result)
    .toBe('Removed 1 ask for PROJ-2: (id 5) merge app#3. Its question isn\'t the one passed: check it was the ask you meant.')
  await ask('PROJ-2', 'merge app#3')

  // PROJ-2's ask, opened, shows its buttons. The cancel lands in the press chain, before the Button's own onPress
  // (from the drawing made before the cancel) runs: that stale click finds nothing to answer.
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'askgrp-PROJ-2' })
  expect(await ui.find({ type: 'Button', key: 'ask-6-0' })).toBeDefined()
  await ui.press({ key: 'ask-6-0' })
  expect(cancelled).toBe('Removed 1 ask for PROJ-2: (id 6) merge app#3.')
  expect(toasts).toEqual(['That ask is gone: withdrawn, answered, or expired after 24h.'])
  expect(await ui.find({ type: 'Button', key: 'ask-6-0' })).toBeUndefined()
  expect((await cancel('IVAN-1')).result).toBe('Removed 1 ask for IVAN-1: (id 3) create IVAN-1 a+b.')

  await ask('PROJ-3', 'race app#9')
  await expect(ui.press({ key: 'ask-7-0' })).rejects.toThrow()
  expect(late).toBe('No queued ask matched PROJ-3. (id 7) was clicked just before: its answer may still arrive.')
  expect(await ui.find({ type: 'Button', key: 'ask-7-0' })).toBeUndefined() // not put back

  // A failed submit with no cancel: the ask is answerable again, in its place.
  await ask('PROJ-4', 'flaky app#8')
  await expect(ui.press({ key: 'ask-8-0' })).rejects.toThrow()
  expect(await ui.find({ type: 'Button', key: 'ask-8-0' })).toBeDefined()
  expect(submitted).toEqual([])
  await ui.unmount()
})

test('a review finding ask unanswered for 24h comes back to the coordinator once, pane closed or not; an expired reminder comes back as dropped; other asks expire silently', async ($, on) => {
  const clock = mock.clock(on)
  const H = 3600_000
  let refuse = false
  let hold: Promise<void> | undefined
  const tries: string[] = []
  on('prompt.submit', async (_, e) => {
    tries.push(e.text)
    if (refuse) return { drop: 'refused by a hook' }
    await hold // a coordinator mid-turn: the submit waits for idle
    return { text: e.text }
  })
  on('process.run', async () => ({ value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  on('ui.panes', async () => ({ value: [] })) // the pane is closed: only session.start's sweep runs
  on('ui.open', async () => ({ value: { isPlaced: false, reason: 'closed' } }))
  on('session.start', async (_, e) => ({ cwd: e.cwd }))
  on('tool.register', async (_, e) => ({ value: { tool: e.name } }))
  on('command.register', async (_, e) => ({ value: { command: e.name } }))
  on('fs.read', async () => ({ value: { base64: 'IyMgTml0CgpVc2UgYGZvbygpYCBoZXJlLhtbMzFtCg==' } }))
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  const sha = 'fb45bdda1ae27282b4844fa4afa557cbcc9621cefc02ce030fa715a27e31006c'
  const post = (key: string, prefix = '') => $.tool.call({
    tool: 'mcp__session-orchestration__ask_approval', key, question: `${prefix}post issue comment /tmp/c.md on app#2 (sha256 ${sha})`,
    options: ['Yes, post it', `No, ${key}`], body_file: '/tmp/c.md', kind: 'issue',
  })
  const merge = (key: string) => $.tool.call({ tool: 'mcp__session-orchestration__ask_approval', key, question: 'merge app#3', options: ['Yes, merge', `No, ${key}`] })
  await post('PROJ-7')
  await merge('PROJ-8')
  await clock.advance(12 * H)
  await post('PROJ-9', 'Reminder: ')

  // 24h on, the hook refuses the prompt: PROJ-7 is put back, and a new ask queued meanwhile doesn't sweep it away.
  await clock.advance(12 * H - 60_000)
  expect(tries).toEqual([])
  refuse = true
  await clock.advance(60_000)
  expect(tries).toHaveLength(1)
  refuse = false
  await merge('PROJ-10')
  await clock.advance(60_000)
  expect(tries).toHaveLength(2)
  expect(tries[1]).toBe(`Approval pane: review finding asks expired unanswered after 24h (coordinator.md, Messaging). Re-ask each once, the same ask with its question starting "Reminder: ": PROJ-7 (id 1) post issue comment /tmp/c.md on app#2 (sha256 ${sha}).`)
  await clock.advance(120_000)
  expect(tries).toHaveLength(2) // announced once

  // The reminder expires while the coordinator is mid-turn: one prompt however many minutes pass.
  let release = () => {}
  hold = new Promise<void>(r => { release = r })
  await clock.advance(12 * H)
  await clock.advance(180_000)
  expect(tries).toHaveLength(3)
  expect(tries[2]).toBe(`Approval pane: review finding asks expired unanswered after 24h (coordinator.md, Messaging). These reminders expired too, so they are dropped: record each in its review file's header and tell its reviewer session: PROJ-9 (id 3) Reminder: post issue comment /tmp/c.md on app#2 (sha256 ${sha}).`)
  release()
  await clock.advance(120_000)
  expect(tries).toHaveLength(3)
  expect(tries.some(t => /PROJ-8|PROJ-10/.test(t))).toBe(false)
})

test('reload_plugins runs /reload-plugins once, when the turn ends', async ($, on) => {
  const ran: string[] = []
  on('command.run', { command: 'reload-plugins' }, async () => {
    ran.push('reload-plugins')
    return { text: '' }
  })
  on('turn.complete', async () => ({ text: '' }))
  const r = await $.tool.call({ tool: 'mcp__session-orchestration__reload_plugins' })
  expect(r.result).toMatch(/when this turn ends/)
  expect(ran).toEqual([])
  const end = { answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' } as const
  await $.turn.complete(end)
  await $.turn.complete({ ...end, turnId: 't2' })
  expect(ran).toEqual(['reload-plugins'])
})

test('a reload that finds the pane up starts its refresh again; one without the pane opens nothing', async ($, on) => {
  mock.clock(on)
  let up = false
  let opened = 0
  on('ui.panes', async () => ({ value: up ? [{ id: 'coordinator', title: 'Coordinator', isShown: true, isFocused: false, isPlaced: true }] : [] }))
  on('ui.open', async () => {
    opened++
    return { value: { isPlaced: true } }
  })
  on('process.run', async () => ({ value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  on('session.start', async (_, e) => ({ cwd: e.cwd }))
  on('tool.register', async (_, e) => ({ value: { tool: e.name } }))
  on('command.register', async (_, e) => ({ value: { command: e.name } }))
  const start = { cwd: '/work', surface: 'terminal', isInteractive: true } as const
  await $.session.start(start)
  expect(opened).toBe(0)
  up = true
  await $.session.start(start)
  expect(opened).toBe(1)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'refresh' }) // joins the sweep the open started
  await ui.unmount()
})

test('a failed /reload-plugins says so and names the command to run', async ($, on) => {
  on('command.run', { command: 'reload-plugins' }, async () => {
    throw new Error('busy')
  })
  on('turn.complete', async () => ({ text: 'done' }))
  await $.tool.call({ tool: 'mcp__session-orchestration__reload_plugins' })
  const r = await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
  expect(r.text).toMatch(/^done\n\nReloading plugins failed \(.*\)\. Run \/reload-plugins\.$/)
})

test('usage names: fixed words lib.sh usage accepts', () => {
  const names = [...Object.values(BUILTIN_KEYS), ...USAGE_EXTRA].map(usageName)
  expect(usageName('Attach in tab')).toBe('attach-in-tab')
  expect(names.every(n => /^[a-z0-9-]{1,40}$/.test(n))).toBe(true)
})

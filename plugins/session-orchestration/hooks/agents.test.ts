import { expect, mock, test } from 'claude-code/testing'

import { elsewhereOf, parseActivity, parseDiff, patchFiles } from './register'

const PANE = { plugin: 'session-orchestration', component: 'Pane', requestId: 'coordinator' } as const
const PROPS = { title: 'Coordinator', isFocused: false, bodyColumns: 160, placement: 'dock', scroll: { offset: 0, bodyRows: 60 }, view: {} } as const

const NOW = Date.UTC(2026, 9, 18, 12, 0) // ms
const S = (minAgo: number) => String(NOW / 1000 - minAgo * 60) // epoch seconds, minutes ago

const DIFF = `/repo/.claude/worktrees/x · vs origin/main
 src/a.ts | 2 +-
 img.png  | Bin 0 -> 12 bytes
 2 files changed, 1 insertion(+), 1 deletion(-)
?? notes.txt

diff --git a/src/a.ts b/src/a.ts
index 1111111..2222222 100644
--- a/src/a.ts
+++ b/src/a.ts
@@ -1,2 +1,2 @@
-old
+new
 same
@@ -9,1 +9,1 @@
-x
+y
diff --git a/img.png b/img.png
new file mode 100644
index 0000000..3333333
Binary files /dev/null and b/img.png differ
`

test('diff text, its patch budget, the 13-field activity and other projects', () => {
  const d = parseDiff(DIFF)
  expect(d.head).toBe('/repo/.claude/worktrees/x · vs origin/main')
  expect(d.stat).toEqual([' src/a.ts | 2 +-', ' img.png  | Bin 0 -> 12 bytes', ' 2 files changed, 1 insertion(+), 1 deletion(-)', '?? notes.txt'])
  expect(d.files.map(f => f.name)).toEqual(['src/a.ts', 'img.png'])
  expect(d.files[0]?.hunks).toBe('@@ -1,2 +1,2 @@\n-old\n+new\n same\n@@ -9,1 +9,1 @@\n-x\n+y')
  expect(d.files[1]?.hunks).toBe('') // binary: no hunks
  // Nothing committed or changed: the head alone.
  expect(parseDiff('/repo · vs HEAD\n\n')).toEqual({ head: '/repo · vs HEAD', stat: [], files: [] })

  // Over budget, a file is cut at a hunk's start; one with no room for its first hunk is named, not drawn.
  const big = { name: 'b.ts', hunks: '@@ -1 +1 @@\n-a\n+b\n@@ -5 +5 @@\n-c\n+d' }
  const cut = patchFiles([big, { name: 'c.ts', hunks: '@@ -1 +1 @@\n-e\n+f' }], 20)
  expect(cut.shown).toEqual([{ name: 'b.ts', hunks: '@@ -1 +1 @@\n-a\n+b', cut: true }])
  expect(cut.skipped).toEqual(['c.ts'])
  expect(patchFiles([big]).shown[0]?.cut).toBe(false)

  const acts = parseActivity([
    `aaaa1111-1\there\tworking\t${S(1)}\tEditing\t${S(2)}\tGo\t1000\t200000\tbusy\tbackground\t/p/here\tclaude`,
    `bbbb2222-2\tthere\tidle\t${S(9)}\t\t0\tDone\t0\t0\tidle\tinteractive\t/p/there\tCLAUDE_CONFIG_DIR=~/.claude-work claude`,
    `cccc3333-3\tnew here\tidle\t${S(1)}\t\t0\t\t0\t0\tidle\tbackground\t/p/here/.claude/worktrees/w\tclaude`,
    `dddd4444-4\tbusy there\tworking\t${S(1)}\tRunning\t${S(1)}\t\t0\t0\tbusy\tbackground\t/p/zz\tclaude`,
  ].join('\n'))
  expect(acts[1]).toMatchObject({ cwd: '/p/there', pre: 'CLAUDE_CONFIG_DIR=~/.claude-work claude', kind: 'interactive' })
  // The sweep saw aaaa; cccc started under the root since: both are this project's. Busy first.
  expect(elsewhereOf(acts, 'aaaa1111-1\there\tworking\tclaude', '/p/here').map(a => a.id)).toEqual(['dddd4444-4', 'bbbb2222-2'])
  // No sweep and no root yet: nothing is known to be elsewhere.
  expect(elsewhereOf(acts, '', undefined)).toEqual([])
})

const STATUS = `PROJ-4157  Code Review    app#76 OPEN no-human-approval  | no-wt | sess:"fix it" working | Race to settle`

test('a card peeks and diffs; all projects lists the others', async ($, on) => {
  mock.clock(on, { now: NOW })
  const calls: string[][] = []
  let diff = { stdout: DIFF, exitCode: 0 }
  const here = `1111aaaa-1\tfix it\tworking\t${S(1)}\tRunning the tests\t${S(5)}\tStarting.\t0\t0\tbusy\tbackground\t/p/here\tclaude`
  const there = `9999bbbb-2\tdocs pass\tidle\t${S(30)}\t\t0\tSent the report\t0\t0\tidle\tinteractive\t/p/other-repo\tCLAUDE_CONFIG_DIR=~/.claude-work claude`
  on('process.run', async (_, e) => {
    calls.push([...e.argv])
    const args = e.argv.slice(2)
    const out = (stdout: string, exitCode = 0) => ({ value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } })
    switch (args[0] ?? '') {
      case '': return out(STATUS)
      case '--activity': return out(args[1] === '--all-projects' ? `${here}\n${there}` : here)
      case '--agents': return out('1111aaaa-1\tfix it\tworking\tclaude')

      case '--peek': return out('**claude** · 11:55\n\nRan the tests: 3 failed.\n→ Bash: npm test  \n\n_Now: Running the tests_')
      case '--diff': return out(diff.stdout, diff.exitCode)
      default: return out('')
    }
  })
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal', props: PROPS })
  await ui.press({ key: 'refresh' })

  await ui.press({ key: 'task-PROJ-4157' })
  await ui.press({ key: 'act-p' })
  expect(calls).toContainEqual(expect.arrayContaining(['--peek', '1111aaaa-1']))
  expect(await ui.find({ type: 'Markdown', text: /Ran the tests: 3 failed/ })).toBeDefined()
  expect((await ui.find({ type: 'Button', key: 'act-p' }))?.text).toBe('Hide peek')

  // Diff replaces the peek: the task's worktree first, its session's folder next; the stat until ▸ Patch.
  await ui.press({ key: 'act-d' })
  expect(calls).toContainEqual(expect.arrayContaining(['--diff', 'PROJ-4157', '1111aaaa-1']))
  expect(await ui.find({ type: 'Markdown', text: /Ran the tests/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: '?? notes.txt' })).toBeDefined()
  expect(await ui.find({ type: 'Code' })).toBeUndefined()
  await ui.press({ key: 'patch-task-PROJ-4157' })
  const code = await ui.find({ type: 'Code' })
  expect(code?.props).toMatchObject({ format: 'diff', path: 'src/a.ts' })
  expect(await ui.find({ type: 'Text', text: /no text change/ })).toBeDefined() // the png

  expect(await ui.find({ type: 'Button', key: 'act-e' })).toBeUndefined() // no editor button

  // A --diff that found nothing shows its words, not an empty diff.
  diff = { stdout: 'no worktree or transcript cwd for PROJ-4157 1111aaaa-1', exitCode: 2 }
  await ui.press({ key: 'act-d' })
  await ui.press({ key: 'act-d' })
  expect(await ui.find({ type: 'Text', text: /^no worktree or transcript cwd/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'no change' })).toBeUndefined()

  // Closing the card closes its view.
  await ui.press({ key: 'task-PROJ-4157' })
  await ui.press({ key: 'task-PROJ-4157' })
  expect(await ui.find({ type: 'Code' })).toBeUndefined()

  // All projects: the other project's session gets a section of its own, attached through its account.
  expect(await ui.find({ type: 'Button', key: 'sec-Other projects' })).toBeUndefined()
  await ui.press({ key: 'allprojects' })
  expect((await ui.find({ type: 'Button', key: 'allprojects' }))?.text).toBe('all projects ●')
  expect((await ui.find({ type: 'Button', key: 'sec-Other projects' }))?.text).toMatch(/OTHER PROJECTS 1 /)
  expect((await ui.find({ type: 'Button', key: 'all-9999bbbb-2' }))?.text).toBe('docs pass other-repo Sent the report 30m')
  // This project's session still shows its activity on its task row.
  expect((await ui.find({ type: 'Button', key: 'task-PROJ-4157' }))?.text).toMatch(/^PROJ-4157 Running the tests · 5m/)
  await ui.press({ key: 'all-9999bbbb-2' })
  expect(await ui.find({ type: 'Text', text: 'CLAUDE_CONFIG_DIR=~/.claude-work claude attach 9999bbbb' })).toBeDefined()
  await ui.press({ key: 'act-p' })
  expect(calls).toContainEqual(expect.arrayContaining(['--peek', '9999bbbb-2']))
  await ui.unmount()
})

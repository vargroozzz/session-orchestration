import { expect, mock, test } from 'claude-code/testing'

import './register'

test('the pane\'s minute timer sends the watcher\'s outbox to each owner and reports what came of it', async ($, on) => {
  const clock = mock.clock(on)
  const done: string[] = []
  let outbox = '1\tid-a\tfix it\tapp#1 conflict @- (PROJ-1) → "fix it" id-a\tPR app#1: fix it\n'
    + '1\tid-b\tgone\tapp#2 all-merged (PROJ-2, In review) → "gone" id-b\tapp#2: deploy\n'
  on('process.run', async (_, e) => {
    const args = e.argv.slice(2)
    let stdout = ''
    if (args[0] === '--outbox') stdout = outbox
    if (args[0] === '--outbox-done') { done.push(String(e.init?.stdin)); outbox = '' }
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  const sent: string[] = []
  on('session.send', async (_, e) => {
    sent.push(`${e.to}: ${e.text}`)
    return e.to === 'id-a' ? { isDelivered: true } : { isDelivered: false, reason: 'no session by that name' }
  })
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  await $.tool.call({ tool: 'mcp__session-orchestration__open_pane' })
  for (let i = 0; i < 50 && !done.length; i++) await clock.advance(60_000)
  expect(sent).toEqual(['id-a: PR app#1: fix it', 'id-b: app#2: deploy'])
  expect(done).toEqual(['ok\tapp#1 conflict @- (PROJ-1) → "fix it" id-a\tsent\n'
    + 'failed\tapp#2 all-merged (PROJ-2, In review) → "gone" id-b\tno session by that name\n'])
  // An empty outbox sends nothing and reports nothing.
  await clock.advance(60_000)
  expect(done.length).toBe(1)
})

import { expect, mock, test } from 'claude-code/testing'

import { weeklyLine } from './register'

const ctx = { window: 200_000 }

test('the seven_day window becomes the usage line; none without one that resets', async () => {
  expect(weeklyLine([{ kind: 'five_hour', percentUsed: 50, resetsAt: '2026-11-04T12:00:00Z' },
    { kind: 'seven_day', percentUsed: 91.5, resetsAt: '2026-11-09T19:00:00.000Z' }])).toBe('91.5\t1794250800\n')
  expect(weeklyLine([{ kind: 'five_hour', percentUsed: 50, resetsAt: '2026-11-04T12:00:00Z' }])).toBeUndefined()
  expect(weeklyLine([{ kind: 'seven_day', percentUsed: 5 }])).toBeUndefined()
})

test('a measurement writes its account\'s reading when the windows moved', async ($, on) => {
  mock.env(on, { HOME: '/h', CLAUDE_CONFIG_DIR: '/h/.claude-work/' })
  const wrote: { path: string; text: string }[] = []
  on('fs.write', async (_, e) => (wrote.push({ path: e.path, text: e.text }), { value: undefined }))
  on('session.measure', async (_, e) => ({ changed: e.changed }))
  const week = { kind: 'seven_day', percentUsed: 40, resetsAt: '2026-11-09T19:00:00Z' }
  await $.session.measure({ context: ctx, rateLimits: [week], changed: ['context'] })
  expect(wrote).toEqual([])
  await $.session.measure({ context: ctx, rateLimits: [week], changed: ['rateLimits'] })
  expect(wrote).toEqual([{ path: '/h/.cache/session-status/usage/.claude-work', text: '40\t1794250800\n' }])
  // Only five_hour moved: the same 7-day line isn't written again.
  await $.session.measure({ context: ctx, rateLimits: [{ kind: 'five_hour', percentUsed: 9, resetsAt: '2026-11-04T12:00:00Z' }, week], changed: ['rateLimits'] })
  expect(wrote.length).toBe(1)
})

test('the default account is ~/.claude', async ($, on) => {
  mock.env(on, { HOME: '/h' })
  const wrote: string[] = []
  on('fs.write', async (_, e) => (wrote.push(e.path), { value: undefined }))
  on('session.measure', async (_, e) => ({ changed: e.changed }))
  await $.session.measure({ context: ctx, rateLimits: [{ kind: 'seven_day', percentUsed: 1, resetsAt: '2026-11-09T19:00:00Z' }], changed: ['rateLimits'] })
  expect(wrote).toEqual(['/h/.cache/session-status/usage/.claude'])
})

// The coordinator pane: the project's state (status command + adapter `pending`) and the approvals the
// coordinator queued, as buttons. A click submits the answer as a prompt from this plugin, so it reaches the
// coordinator as its next turn instead of blocking one the way the question box does. verify-approval.sh
// accepts that prompt (a user row with origin plugin session-orchestration) as the user's answer.
// Tasks are grouped by what they wait on, as Claude Code Projects' Overview groups threads. Pressing any other
// item opens it as a card with its actions: attach, links, refresh, dismiss, ask, and the fixes that apply.
// OTHER SESSIONS: live sessions that own no task. A working session, on a task row or there, says what it's doing
// and for how long (session-status --activity, refreshed every minute), and is flagged when it has gone quiet.
// ACTIONS: the project's own commands, from its .claude/coordinator-actions.json and its status `fix:` lines.
// A session's card also has Peek (its recent turns, session-status --peek), Diff (its worktree against its base,
// --diff; the patch one press further), and, with a terminal configured (config terminal, e.g. ghostty), Attach in
// tab / Logs in split (session-status --open; when it opens nothing, the command copied). The header's "all projects"
// adds OTHER PROJECTS: the live sessions of every other project, every account session-status asks. Its "yesterday" swaps the board
// for what was worked on since the last working day (session-status --yesterday), for the daily standup, written as
// a few spoken sentences by a small model (standup-summary), the raw list one key away.
import { atom, read, update } from 'claude-code'
import type { Color, EngineInterface, Register, RenderElement, RenderNode, UiPressArgument } from 'claude-code'

import type { ActionResult, Actions, Ask, AskBody, AskKind, Board, Handed, PaneAction, Peek } from '../types'

const PANE = 'coordinator'
const TTL_MS = 24 * 3600_000 // as long as verify-approval.sh accepts the answer
const asks = atom({ plugin: 'session-orchestration', key: 'asks' } as const, [])
const board = atom({ plugin: 'session-orchestration', key: 'board' } as const, null)
const seq = atom({ plugin: 'session-orchestration', key: 'seq' } as const, 0)
const refreshing = atom({ plugin: 'session-orchestration', key: 'refreshing' } as const, false)
const wrapped = atom({ plugin: 'session-orchestration', key: 'wrapped' } as const, [])
const selected = atom({ plugin: 'session-orchestration', key: 'selected' } as const, null)
const dismissed = atom({ plugin: 'session-orchestration', key: 'dismissed' } as const, [])
const rowsBusy = atom({ plugin: 'session-orchestration', key: 'rowsBusy' } as const, [])
const actions = atom({ plugin: 'session-orchestration', key: 'actions' } as const, null)
const actionResult = atom({ plugin: 'session-orchestration', key: 'actionResult' } as const, null)
const actionBusy = atom({ plugin: 'session-orchestration', key: 'actionBusy' } as const, null)
const activity = atom({ plugin: 'session-orchestration', key: 'activity' } as const, '')
const compacting = atom({ plugin: 'session-orchestration', key: 'compacting' } as const, [])
const naming = atom({ plugin: 'session-orchestration', key: 'naming' } as const, null)
const reloading = atom({ plugin: 'session-orchestration', key: 'reloading' } as const, false)
const asksOpen = atom({ plugin: 'session-orchestration', key: 'asksOpen' } as const, [])
const peek = atom({ plugin: 'session-orchestration', key: 'peek' } as const, null)
const allProjects = atom({ plugin: 'session-orchestration', key: 'allProjects' } as const, false)
const yesterdayTab = atom({ plugin: 'session-orchestration', key: 'yesterday' } as const, false)
const ydDay = atom({ plugin: 'session-orchestration', key: 'ydDay' } as const, null)
const ydText = atom({ plugin: 'session-orchestration', key: 'ydText' } as const, null)
const ydSum = atom({ plugin: 'session-orchestration', key: 'ydSum' } as const, null)
const ydList = atom({ plugin: 'session-orchestration', key: 'ydList' } as const, false)
const handed = atom({ plugin: 'session-orchestration', key: 'handed' } as const, [])
const handedResult = atom({ plugin: 'session-orchestration', key: 'handedResult' } as const, null)
const terminal = atom({ plugin: 'session-orchestration', key: 'terminal' } as const, 'plain')

const oneLine = (s: string) => s.replace(/\s+/g, ' ').trim()
// Text a session wrote, made safe to draw and kept whole: CRLF to LF, then every other control character (an
// escape sequence's ESC, C1) and bidi override shown as its code (`\x1b`, `\u202e`), never dropped, so the pane
// shows all the text a sha256 covers. Markdown and Text refuse any control but tab and newline.
export const clean = (s: string) => s.replace(/\r\n?/g, '\n').replace(/[\u0000-\u0008\u000b-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/g,
  c => (c.charCodeAt(0) < 0x100 ? `\\x${c.charCodeAt(0).toString(16).padStart(2, '0')}` : `\\u${c.charCodeAt(0).toString(16)}`))
// A 64-hex sha256 in a one-line summary, cut to its first 8.
export const shortShas = (s: string) => s.replace(/\b([0-9a-f]{8})[0-9a-f]{56}\b/g, '$1…')
// What an expanded ask draws of a body or details text; the rest is named, not drawn.
export const BODY_MAX = 20_000
// Markdown that a drawing would hide from the user approving it: a link's target, a reference definition, HTML
// (a comment, a tag). A body holding any is drawn as written.
export const HIDDEN_BY_MARKDOWN = /\]\(|^ {0,3}\[[^\]]+\]:|<!--|<\/?[a-z]/im
// A PR review finding's kind (optional, posts only), as its badge shows it and in the order a group lists them, after the asks that aren't
// review findings (a merge, a Jira comment), so those stay at the top.
export const KINDS: AskKind[] = ['issue', 'suggestion', 'question']
const isKind = (v: unknown): v is AskKind => KINDS.some(k => k === v)
const KIND_COLOR: Record<AskKind, Color> = { issue: 'error', suggestion: 'suggestion', question: 'merged' }
export const byKind = (as: Ask[]) => [...as].sort((a, b) => kindRank(a) - kindRank(b))
const kindRank = (a: Ask) => (a.kind ? KINDS.indexOf(a.kind) : -1)
const kindBadge = (a: Ask): Seg[] => (a.kind ? [seg(` ${a.kind.toUpperCase()} `, solid(KIND_COLOR[a.kind])), seg(' ')] : [])
// The group line's counts: `1 issue · 2 questions`.
export const kindCounts = (as: Ask[]) => KINDS.map(kind => ({ kind, n: as.filter(a => a.kind === kind).length }))
  .filter(c => c.n > 0).map(({ kind, n }) => ({ kind, text: `${n} ${kind}${n === 1 ? '' : 's'}` }))
// All the Markdown one drawing of the pane draws, over every open ask.
const MD_BUDGET = 60_000
// Which groups and asks the pane draws open: a press's choice (`asksOpen`), else open when alone (a group in
// the pane, an ask in its group).
const asksLayout = (list: Ask[], opens: string[]) => {
  const isOpen = (id: string, byDefault: boolean) => {
    const set = opens.find(x => x.startsWith(`${id}=`))
    return set ? set.endsWith('=1') : byDefault
  }
  const asksBy = list.reduce((m, a) => m.set(a.key, [...(m.get(a.key) ?? []), a]), new Map<string, Ask[]>())
  const groupOpen = (key: string) => isOpen(`group-${key}`, asksBy.size === 1)
  const askOpen = (a: Ask) => isOpen(`ask-${a.id}`, asksBy.get(a.key)?.length === 1)
  return { asksBy, groupOpen, askOpen, drawnOpen: new Set(list.filter(a => groupOpen(a.key) && askOpen(a)).map(a => a.id)) }
}
// After a press, an ask drawn open is seen and stays seen once closed. Drawing is pure, so one only opened by
// default (alone) is not marked: NEW again if a newcomer closes it unpressed.
const markSeen = async ($: EngineInterface, now: number) => {
  const { drawnOpen } = asksLayout(await liveAsks($, now), await read($, asksOpen))
  await update($, asks, l => (l.some(a => !a.seen && drawnOpen.has(a.id)) ? l.map((a): Ask => (drawnOpen.has(a.id) ? { ...a, seen: true } : a)) : l))
}
// Open/closed choices (`ask-ID=1`, `group-KEY=0`) for asks and keys still queued: a key whose asks are all gone
// starts over at its default when it's asked again. One being sent keeps its choices: a failed submit restores it.
const pruneOpen = async ($: EngineInterface, now: number) => {
  const kept = (await read($, asks)).filter(a => now - a.at < TTL_MS)
  await update($, asksOpen, l => l.filter(x => kept.some(a => x.startsWith(`ask-${a.id}=`) || x.startsWith(`group-${a.key}=`))))
}
// A comment body file as it is now: its sha256 (of the bytes, as `shasum -a 256` prints it) and its text.
export async function readBody($: EngineInterface, path: string): Promise<AskBody> {
  const { base64 } = await $.fs.read(path, { as: 'bytes' })
  const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0))
  const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))
  const text = clean(new TextDecoder().decode(bytes))
  return {
    path, sha256: [...hash].map(b => b.toString(16).padStart(2, '0')).join(''),
    text: text.slice(0, BODY_MAX), cut: Math.max(text.length - BODY_MAX, 0),
  }
}
// The prompt a click submits, and the Quote a relay carries. The clicked option comes first, so text in the
// question can't pose as the answer. Keep in sync with coordinator.md and SKILL.md.
export const answerText = (a: Ask, option: string) =>
  `Approval pane answer for ${a.key}: ${oneLine(option)}. Asked: ${oneLine(a.question)}`
// An item's Ask button. Never starts "Approval pane answer for ", so verify-approval.sh never takes it.
export const askText = (about: string) => `Coordinator pane: where does ${about} stand, and what's next? Answer briefly.`
// A card action (Resolve conflicts, Fix CI, Address comments): the user's instruction for the owning session,
// which the coordinator relays. Never starts "Approval pane answer for ". Keep in sync with coordinator.md.
export const fixText = (key: string, says: string, prs: string) =>
  `Coordinator pane action for ${key}: tell the session that owns it to ${says}${prs ? ` (${prs})` : ''}. Relay it per coordinator.md (Card actions).`

// A task row of session-status: `printf '%-9s %-14s %s%s | %s' KEY STATUS EXTRA LOCAL SESSION` then ` | TITLE`.
// `maybe`: no owner, the guess session-status prints beside `—` (`ID: N mentions`), else ''.
export type Sess = { name: string; state: string; maybe: string }
export type Task = { key: string; status: string; extra: string; wt: string; sess: Sess; title: string }
export type Status = { tasks: Task[]; sections: { title: string; items: string[] }[]; other: string[]; fixes: string[] }

// The key's column is padded to 9 then a space, so the rest (mid) starts with STATUS's own padding.
const ROW = /^(\S+)(.*?)\s*(wt dirty:(\S+) unpushed:(\S+)|no-wt) \| sess:(?:"([^"]*)" (\S+)|(\S+) closed (\d+h)|—(?: \(maybe ([^)]*)\))?)(?: \| (.*))?$/
export function parseTask(line: string): Task | undefined {
  const m = ROW.exec(line)
  if (!m) return
  const [, key = '', raw = '', , dirty, ahead, live, state = '', id, age, maybe = '', title] = m
  const mid = raw.slice(Math.max(9 - key.length, 0) + 1)
  // STATUS is padded to 14; a longer one runs to the next space.
  const end = mid.indexOf(' ', 14)
  const cut = mid.length <= 14 || mid[14] === ' ' ? 14 : end < 0 ? mid.length : end
  const status = mid.slice(0, cut).trim()
  const counts = [dirty && dirty !== '0' && `${dirty} dirty`, ahead && ahead !== '0' && `${ahead} unpushed`].filter(Boolean).join(' ')
  return {
    key,
    status: status === '-' ? '' : status, // '-': no adapter
    extra: oneLine(mid.slice(cut)).replace(/ ?\|$/, ''),
    wt: counts && `wt ${counts}`,
    sess: live !== undefined ? { name: live, state, maybe: '' }
      : id ? { name: id, state: `closed ${age}`, maybe: '' }
      : { name: '', state: 'none', maybe },
    title: title ?? '',
  }
}

// Task rows, then footer sections ("Waiting on you:", "Notices:", ...) of indented items; `fix:` lines at the
// start of a line (never an indented item: a notice is someone else's words); anything else (an adapter's
// failure message) stays as is.
export function parseStatus(text: string): Status {
  const out: Status = { tasks: [], sections: [], other: [], fixes: [] }
  let sec: Status['sections'][number] | undefined
  for (const line of text.split('\n')) {
    const t = parseTask(line)
    const head = !t && !line.startsWith('fix:') && /^(\S.*):$/.exec(line)
    if (t) out.tasks.push(t)
    else if (head) out.sections.push(sec = { title: head[1] ?? '', items: [] })
    else if (sec && /^\s+\S/.test(line)) sec.items.push(line.trim().replace(/^\* /, ''))
    else if (line.startsWith('fix:')) out.fixes.push(line)
    else if (line.trim()) out.other.push(line)
    if (!head && !/^\s/.test(line)) sec = undefined
  }
  return out
}

// The `- ` items of the pending text up to the first heading after them (a log there isn't pending), an
// indented line continuing one; undefined when it has none.
export function parsePending(text: string) {
  const items: { date?: string; text: string }[] = []
  let last: { date?: string; text: string } | undefined
  for (const line of text.split('\n')) {
    if (items.length > 0 && line.startsWith('#')) break
    const m = /^- (?:(\d{4}-\d\d-\d\d) )?(.*)$/.exec(line)
    if (m) items.push(last = { date: m[1], text: m[2] ?? '' })
    else if (last && /^\s+\S/.test(line)) last.text += ` ${line.trim()}`
    else last = undefined
  }
  return items.length ? items : undefined
}

const isRunning = (state: string) => state === 'working' || state === 'busy'
// The order rows show in: blocked on you, then a problem to act on (a solid chip), then running sessions, then
// by tracker status in first-seen order.
export function orderTasks(tasks: Task[], factsOf: (t: Task) => Fact[] = facts) {
  const rank = new Map(tasks.map(t => [t, t.sess.state === 'blocked' ? 'a' : factsOf(t).some(f => f.act) ? 'b' : isRunning(t.sess.state) ? 'c' : 'd']))
  const statuses = [...new Set(tasks.map(t => t.status))]
  return [...tasks].sort((a, b) => (rank.get(a) ?? '').localeCompare(rank.get(b) ?? '') || statuses.indexOf(a.status) - statuses.indexOf(b.status))
}

const stateColor = (state: string): Color =>
  state === 'blocked' ? 'warning' : isRunning(state) ? 'suggestion' : state === 'idle' ? 'success' : 'inactive'

// What a task waits on, in plain words, the most pressing first; the first leads its row as a chip.
// chipSaysIt: as the chip, no words needed. act: someone has to act, so the row sorts up; else the task waits
// on someone or something. onYou: the user has to act (a solid chip, counted in the header). fix: the card
// action that tells the owning session to fix it.
export type Fix = 'conflict' | 'ci' | 'comments'
export type Fact = { text: string; chip: string; color: Color; chipSaysIt?: true; act?: true; onYou?: true; fix?: Fix }
// The PRs EXTRA names: `repo#id STATE`.
export const prsOf = (t: Task) =>
  [...t.extra.matchAll(/(?:^|\s)([\w.-]+)#(\d+) (OPEN|MERGED)\b/g)].map(([, repo = '', id = '', state = '']) => ({ repo, id, state }))
// Reads the EXTRA words the adapter contract defines (session-status header: PR states, CONFLICT, CI-FAILED,
// +/! reviewers, no-human-approval, ↩ sent back, "PRs as of").
export function facts(t: Task): [Fact, ...Fact[]] {
  const x = t.extra
  const out: Fact[] = []
  const names = (re: RegExp) => [...x.matchAll(re)].map(m => m[1]).join(', ')
  if (t.sess.state === 'blocked') out.push({ text: 'session blocked on you', chip: 'needs you', color: 'warning', chipSaysIt: true, act: true, onYou: true })
  if (/(?<![\w-])conflicts?(?![\w-])/i.test(x)) out.push({ text: 'merge conflict', chip: '✗ conflict', color: 'error', chipSaysIt: true, act: true, fix: 'conflict' })
  if (/(?<![\w-])CI-FAILED(?![\w-])/.test(x)) out.push({ text: 'CI failed', chip: '✗ ci failed', color: 'error', chipSaysIt: true, act: true, fix: 'ci' })
  const asked = names(/(?:^|[\s,])!([A-Za-z][\w.-]*)/g)
  if (asked) out.push({ text: `changes asked by ${asked}`, chip: 'changes', color: 'error', act: true, fix: 'comments' })
  const back = /↩\S+ (\S+)→/.exec(x)
  if (back) out.push({ text: `sent back by ${back[1]}`, chip: 'sent back', color: 'warning', act: true })
  if (isRunning(t.sess.state)) out.push({ text: 'session working', chip: 'running', color: 'suggestion', chipSaysIt: true })
  if (/\bno-human-approval\b/.test(x)) out.push({ text: 'needs human review', chip: 'in review', color: 'ide', chipSaysIt: true })
  const approved = names(/(?:^|[\s,])\+([A-Za-z][\w.-]*)/g)
  if (approved) out.push({ text: `approved by ${approved}`, chip: 'approved', color: 'success' })
  const prs = prsOf(t).map(p => p.state)
  if (prs.length > 0 && !prs.includes('OPEN') && !/test|done|closed|resolved/i.test(t.status)) {
    out.push({ text: 'not yet Ready for Test', chip: 'merged', color: 'merged', act: true })
  }
  const ahead = /(\d+) unpushed/.exec(t.wt)
  if (ahead) out.push({ text: `${ahead[1]} unpushed commit${ahead[1] === '1' ? '' : 's'}`, chip: 'unpushed', color: 'warning', act: true })
  const stale = /PRs as of (\S+)\)/.exec(x)
  if (stale) out.push({ text: `PR info from ${stale[1]}`, chip: 'stale', color: 'inactive' })
  const [first, ...rest] = out
  return first ? [first, ...rest] : [{ text: '', chip: t.status || 'no status', color: 'inactive' }]
}

// The task groups, in the order they show, after WAITING ON YOU: Projects' Overview groups (its Ready for review,
// named In review here: it waits on reviewers, not on the user; Working, Landing, Idle) behind one for a problem
// someone has to act on. Resolved is a status footer.
export const GROUPS = ['Needs action', 'In review', 'Working', 'Landing', 'Idle'] as const
export type Group = (typeof GROUPS)[number]
// Landing: an open PR someone approved, no human review still due, nothing to fix: waiting for the merge decision.
export function groupOf(t: Task, all: Fact[] = facts(t)): Group {
  if (all.some(f => f.act)) return 'Needs action'
  if (isRunning(t.sess.state)) return 'Working'
  if (!prsOf(t).some(p => p.state === 'OPEN')) return 'Idle'
  return all.some(f => f.chip === 'approved') && !all.some(f => f.chip === 'in review') ? 'Landing' : 'In review'
}
// The chip each group's heading already says.
const IMPLIED: Partial<Record<Group, string>> = { 'In review': 'in review', Working: 'running', Landing: 'approved' }
// The card actions a task's facts call for, once each, in the order Projects' cards show them.
const FIXES = [
  { fix: 'conflict', hotkey: 'o', label: 'Resolve conflicts', says: 'resolve the merge conflict' },
  { fix: 'ci', hotkey: 'f', label: 'Fix CI', says: 'fix the failing CI build' },
  { fix: 'comments', hotkey: 'm', label: 'Address comments', says: 'address the review comments' },
] as const satisfies readonly { fix: Fix; hotkey: string; label: string; says: string }[]
export const fixesOf = (all: Fact[]) => FIXES.filter(f => all.some(x => x.fix === f.fix))

// Project actions. The pane's own hotkeys, which a project's can't take: refresh, the card actions, 1-9.
// ponytail: the card actions' letters below are the act(...) calls' in the render hook; keep the two in step.
export const BUILTIN_KEYS: Record<string, string> = {
  r: 'Refresh', ...Object.fromEntries(FIXES.map(f => [f.hotkey, f.label])), a: 'Attach', u: 'Refresh (row)',
  k: 'Ask', x: 'Dismiss', c: 'Copy command', z: 'Compact', p: 'Peek', d: 'Diff', w: 'All projects',
  t: 'Attach in tab', l: 'Logs in split', y: 'Yesterday', b: 'Earlier day', n: 'Later day', s: 'Summary or list',
}
const taken = (key: string) => /^\d$/.test(key) ? 'a 1-9 item key' : BUILTIN_KEYS[key]
export const ACTIONS_FILE = '.claude/coordinator-actions.json'
const FIELDS = ['label', 'hotkey', 'command', 'when']
// .claude/coordinator-actions.json: `[{ "label", "hotkey", "command", "when"? }]`. A bad entry becomes an error
// line and is left out; the rest load.
export function parseActions(text: string): { list: PaneAction[]; errors: string[] } {
  let data: unknown
  try {
    data = JSON.parse(text)
  } catch (err) {
    return { list: [], errors: [`${ACTIONS_FILE}: not JSON (${err instanceof Error ? err.message : String(err)})`] }
  }
  if (!Array.isArray(data)) return { list: [], errors: [`${ACTIONS_FILE}: not a list of actions`] }
  const list: PaneAction[] = []
  const errors: string[] = []
  const str = (v: unknown) => (typeof v === 'string' && v.trim() !== '' ? v : undefined)
  data.forEach((e: unknown, i) => {
    const o: Record<string, unknown> = typeof e === 'object' && e !== null && !Array.isArray(e) ? { ...e } : {}
    const label = str(o.label)
    const bad = (why: string) => errors.push(`${ACTIONS_FILE} #${i + 1}${label ? ` "${oneLine(label)}"` : ''}: ${why}`)
    const hotkey = o.hotkey
    const extra = Object.keys(o).filter(k => !FIELDS.includes(k))
    if (Object.keys(o).length === 0) return bad('not an object with label, hotkey, command')
    if (!label) return bad('label must be a non-empty string')
    if (typeof hotkey !== 'string' || !/^[a-z]$/.test(hotkey)) return bad('hotkey must be one lowercase letter')
    if (taken(hotkey)) return bad(`hotkey "${hotkey}" is the pane's own (${taken(hotkey)})`)
    if (list.some(a => a.label.toLowerCase() === oneLine(label).toLowerCase())) return bad('label is already used')
    const dup = list.find(a => a.hotkey === hotkey)
    if (dup) return bad(`hotkey "${hotkey}" is taken by "${dup.label}"`)
    const command = str(o.command)
    if (!command) return bad('command must be a non-empty string')
    if (o.when !== undefined && !str(o.when)) return bad('when must be a non-empty string')
    if (extra.length > 0) return bad(`unknown field ${extra.map(k => `"${k}"`).join(', ')}`)
    list.push({ label: oneLine(label), hotkey, command, ...(str(o.when) ? { when: str(o.when) } : {}) })
  })
  return { list, errors }
}
// A status line `fix: LABEL → COMMAND` (or `->`).
export function parseFix(line: string): PaneAction | string {
  const m = /^fix:\s*(.*?)\s+(?:→|->)\s+(.+)$/.exec(line)
  return m?.[1] && m[2]?.trim() ? { label: m[1], command: m[2].trim() } : `bad fix line (want "fix: LABEL → COMMAND"): ${line}`
}
// The actions the pane shows: the file's shown ones, then each fix line whose label the file doesn't define
// (`owned`: all its labels, a hidden one's too), given the first free letter of its label (else of the
// alphabet) as its hotkey.
// ponytail: a fix line's letter can change between sweeps as others come and go; pin it with a file action.
export function paneActions(file: PaneAction[], fixLines: string[], owned: string[] = file.map(a => a.label)) {
  const errors: string[] = []
  const out = [...file]
  for (const line of fixLines) {
    const f = parseFix(line)
    if (typeof f === 'string') errors.push(f)
    else if (![...owned, ...out.map(a => a.label)].some(l => l.toLowerCase() === f.label.toLowerCase())) {
      const free = (c: string) => /^[a-z]$/.test(c) && !taken(c) && !out.some(a => a.hotkey === c)
      out.push({ ...f, hotkey: [...f.label.toLowerCase(), ...'abcdefghijklmnopqrstuvwxyz'].find(free) })
    }
  }
  return { list: out, errors }
}

// A link from the adapter's `urls` text: its line `KIND URL`, the {placeholders} filled.
export function linkFor(urls: string, kind: 'ticket' | 'pr', vars: Record<string, string>) {
  const tpl = urls.split('\n').find(l => l.startsWith(`${kind} `))?.slice(kind.length + 1).trim()
  return tpl && tpl.replace(/\{(\w+)\}/g, (m, k: string) => (vars[k] === undefined ? m : encodeURIComponent(vars[k])))
}
// A notice line `SOURCE  text`: the source in a word; a failure or a line without a source column as such.
const SOURCE: Record<string, string> = { 'teams DM': 'DM', 'teams @': 'mention', 'teams ?': 'question', mail: 'mail' }
export function notice(line: string): { label: string; text: string; color?: Color } {
  if (line.startsWith('(failed) ')) return { label: 'failed', text: line.slice(9), color: 'error' }
  const n = /^(teams DM|teams @|teams \?|\S+) {2,}(.*)$/.exec(line) // a SOURCE key, or one word
  if (!n) return { label: 'note', text: line }
  const src = n[1] ?? ''
  return { label: SOURCE[src] ?? src, text: n[2] ?? '' }
}
// A leftover's cleanup command: after the first colon outside the quoted session name.
export const leftoverCommand = (text: string) => /—[^":]*(?:"[^"]*")?[^":]*: (.+)$/.exec(text)?.[1]
// A pending item: its task key, and whether its own words put it on the user.
export const pendingOf = (text: string) => ({
  key: /^[A-Z][A-Z0-9]+-\d+/.exec(text)?.[0],
  onYou: /\b(the user|on you|your call)\b/i.test(text),
})
// The 8-character ids of the sessions session-status --agents lists, a done one left out.
export const liveIds = (agents: string) =>
  new Set(agents.split('\n').map(l => l.split('\t')).filter(f => f[0] && f[2] !== 'done').map(f => (f[0] ?? '').slice(0, 8)))
// A pending item has a live session behind it when it names one (its 8-character id) or its task's row has a live
// owner. Without one, nothing else in the pane shows the decision: DECISIONS lists it.
export function liveBehind(text: string, st: Status | undefined, live: Set<string>) {
  if ([...text.matchAll(/\b[0-9a-f]{8}\b/g)].some(m => live.has(m[0]))) return true
  const key = pendingOf(text).key
  const s = key ? st?.tasks.find(t => t.key === key)?.sess : undefined
  return !!s && s.state !== 'none' && s.state !== 'done' && !s.state.startsWith('closed')
}
// A session waiting on you: `"name" (command prefix attach id)`.
const waitingOf = (text: string) => {
  // `— blocked: TOOL `input`` when hooks/blocked.sh recorded what it waits on.
  const w = /^"(.*?)" \((.*?attach (\S+))\)(?: — (blocked: .*))?$/.exec(text)
  return w && { name: w[1] ?? '', command: w[2] ?? '', id: w[3] ?? '', blocked: w[4] ?? '' }
}
// The command that attaches to a live session, from session-status --agents (id, name, state, prefix). A row
// names its session by name only: two sessions of that name and there is none, rather than the wrong one.
export const attachFor = (agents: string, name: string) => {
  const [a, ...more] = agents.split('\n').map(l => l.split('\t')).filter(f => f[1] === name)
  return a && more.length === 0 ? `${a[3] ?? 'claude'} attach ${(a[0] ?? '').slice(0, 8)}` : undefined
}

// A live session's activity, from session-status --activity: id, name, state, transcript written, doing, since
// (epoch seconds; 0 unknown), last text line, context tokens, context window, status (idle, busy, waiting), kind
// (background, interactive), cwd (where it started), command prefix (`claude`, `CLAUDE_CONFIG_DIR=… claude`),
// tab-separated.
export type Activity = {
  id: string; name: string; state: string; written: number; doing: string; since: number; last: string
  ctx: number; window: number; status: string; kind: string; cwd: string; pre: string
}
export function parseActivity(text: string) {
  const out: Activity[] = []
  for (const line of text.split('\n')) {
    const f = line.split('\t')
    if (f.length < 7 || !/^[0-9a-f-]{8,}$/.test(f[0] ?? '')) continue
    const [id = '', name = '', state = '', written, doing = '', since, last = '', ctx, window, status = '', kind = '', cwd = '', pre = ''] = f
    out.push({
      id, name, state, written: Number(written) || 0, doing, since: Number(since) || 0, last,
      ctx: Number(ctx) || 0, window: Number(window) || 0, status, kind, cwd, pre,
    })
  }
  return out
}
// A duration in a few characters: 5m, 1h20m, 3d.
export const dur = (ms: number) => {
  const m = Math.max(Math.floor(ms / 60_000), 0)
  return m < 60 ? `${m}m` : m < 1440 ? `${Math.floor(m / 60)}h${m % 60 ? `${m % 60}m` : ''}` : `${Math.floor(m / 1440)}d`
}
// How long a working session may write nothing before it's flagged.
export const QUIET_MS = 10 * 60_000
// A session's context fill, `ctx 62%` (the window as session-status reads it): dim, amber from 80%, red from 90%.
// Nothing while unknown.
export const CTX_WARN = 80
export function ctxOf(a: Activity | undefined): Seg[] {
  if (!a || a.ctx <= 0 || a.window <= 0) return []
  const pct = Math.round((a.ctx / a.window) * 100)
  return [[`ctx ${pct}%`, pct >= 90 ? { color: 'error', bold: true } : pct >= CTX_WARN ? { color: 'warning', bold: true } : { dimColor: true }], [' ']]
}
// Compact is offered only for a background session that is idle: never mid-turn, nor while it waits on a prompt.
export const canCompact = (a: Activity | undefined) => !!a && a.kind === 'background' && a.status === 'idle'
// What a working session is doing, as facts for its row: `Doing X · 5m` (since that activity started, as
// flightdeck's agent cards count from their task's start), and `no output for 12m` once its transcript has been
// quiet that long. Nothing for a session that isn't working.
export function progressOf(a: Activity | undefined, now: number): Fact[] {
  if (!a || !isRunning(a.state)) return []
  const out: Fact[] = []
  if (a.doing) out.push({ text: `${a.doing}${a.since > 0 ? ` · ${dur(now - a.since * 1000)}` : ''}`, chip: 'running', color: 'suggestion' })
  const quiet = a.written > 0 ? now - a.written * 1000 : 0
  if (quiet > QUIET_MS) out.push({ text: `no output for ${dur(quiet)}`, chip: 'quiet', color: 'warning' })
  return out
}
// An "Other sessions" item: `"NAME" STATE AGE[ · reviews KEY][ · superseded by ID][ — LAST] (PREFIX attach ID)`.
export const otherOf = (text: string) => {
  const m = /^"(.*)" (\S+) (\S+)(?: · reviews (\S+))?(?: · superseded by (\S+))?(?: — (.*))? \(([^()]*attach (\S+))\)$/.exec(text)
  return m && {
    name: m[1] ?? '', state: m[2] ?? '', age: m[3] ?? '', review: m[4], superseded: m[5], last: m[6] ?? '', command: m[7] ?? '', id: m[8] ?? '',
  }
}
export const OTHER = 'Other sessions'
export const OTHER_PROJECTS = 'Other projects'
// The all-projects reading's sessions of other projects: neither one the last sweep saw here (the root and its
// session-dirs) nor one started under the root since. Busy first, then waiting on someone, idle, the rest;
// within each by folder.
// Neither a sweep nor the root known yet: nothing is known to be elsewhere.
const under = (root: string | undefined, cwd: string) => !!root && (cwd === root || cwd.startsWith(`${root}/`))
export function elsewhereOf(acts: Activity[], agents: string, root: string | undefined) {
  if (!agents && !root) return []
  const here = new Set(agents.split('\n').map(l => l.split('\t')[0]))
  const rank = (a: Activity) => (isRunning(a.state) ? 0 : a.status === 'waiting' ? 1 : a.state === 'idle' || a.status === 'idle' ? 2 : 3)
  return acts.filter(a => !here.has(a.id) && !under(root, a.cwd)).sort((a, b) => rank(a) - rank(b) || a.cwd.localeCompare(b.cwd))
}
// session-status --yesterday's text: `Since: DAY WEEKDAY (HOW)`, the project's `Note: TEXT` lines (skipped: they're
// for the summary), an optional `Tracker lookup failed:` with its
// message indented, then per task `KEY<TAB>STATUS<TAB>TITLE` (a keyless session: `"NAME"`) and its events
// `  WEEKDAY HH:MM<TAB>TEXT`. A line of none of these (an error) lands in `other`.
export type YdTask = { key: string; status: string; title: string; events: { when: string; text: string }[] }
export function parseYesterday(text: string) {
  const out = { since: '', failed: [] as string[], tasks: [] as YdTask[], other: [] as string[] }
  let failing = false
  for (const line of text.split('\n')) {
    if (!line.trim()) continue
    // Not trimmed at the end: a row with no status and title (`KEY<TAB><TAB>`) keeps its tabs.
    const [first = '', ...rest] = line.replace(/^ +/, '').split('\t')
    const last = out.tasks.at(-1)
    if (line.startsWith('Since: ')) out.since = line.slice(7)
    else if (line.startsWith('Note: ')) continue // the project's notes for the summary, not for the list
    else if (line === 'Tracker lookup failed:') failing = true
    else if (line.startsWith('  ') && rest.length && last) last.events.push({ when: first, text: rest.join('\t') })
    else if (line.startsWith('  ') && failing) out.failed.push(line.trim())
    else if (rest.length || /^"[^"]*"$/.test(line)) {
      failing = false
      out.tasks.push({ key: first, status: rest[0] ?? '', title: rest.slice(1).join('\t'), events: [] })
    } else out.other.push(line)
  }
  return out
}
// The weekday before (-1) or after (1) DAY (YYYY-MM-DD), skipping Saturday and Sunday.
export function stepDay(day: string, dir: -1 | 1) {
  const d = new Date(`${day}T12:00:00Z`)
  do d.setUTCDate(d.getUTCDate() + dir)
  while (d.getUTCDay() === 0 || d.getUTCDay() === 6)
  return d.toISOString().slice(0, 10)
}
const localDay = (ms: number) => {
  const d = new Date(ms)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

// session-status --diff's text: its `DIR · vs BASE` line, the stat lines (with untracked `?? FILE`s), and each
// file's hunks from its first `@@`, which is what Code's diff format reads (a binary or mode-only change has none).
export function parseDiff(text: string) {
  const [head = '', ...rest] = text.split('\n')
  const body = rest.join('\n')
  const at = body.search(/^diff --git /m)
  const stat = (at < 0 ? body : body.slice(0, at)).split('\n').filter(l => l.trim())
  const files = at < 0 ? [] : body.slice(at).split(/^(?=diff --git )/m).map(chunk => {
    const h = chunk.search(/^@@/m)
    return { name: /^diff --git a\/.* b\/(.*)$/m.exec(chunk)?.[1] ?? '?', hunks: h < 0 ? '' : chunk.slice(h).trimEnd() }
  })
  return { head, stat, files }
}
// All the patch one Diff draws; a file past it is named, not drawn, and a long one is cut at a hunk's start.
export const PATCH_MAX = 40_000
// The stat lines one Diff draws.
export const STAT_MAX = 40
export function patchFiles(files: ReturnType<typeof parseDiff>['files'], max = PATCH_MAX) {
  let left = max
  const shown: { name: string; hunks: string; cut: boolean }[] = []
  const skipped: string[] = []
  for (const f of files) {
    const end = f.hunks.length <= left ? f.hunks.length : f.hunks.lastIndexOf('\n@@', left)
    if (!f.hunks || end <= 0) {
      if (f.hunks) skipped.push(f.name)
      else shown.push({ ...f, cut: false })
      continue
    }
    shown.push({ name: f.name, hunks: f.hunks.slice(0, end), cut: end < f.hunks.length })
    left -= end
  }
  return { shown, skipped }
}

const CHIP_W = 12
const LEAD_W = CHIP_W + 3 // a chip with its padding and a space: where an item's own text starts
const chipText = (label: string) => {
  const l = label.toUpperCase()
  return ` ${(l.length > CHIP_W ? `${l.slice(0, CHIP_W - 1)}…` : l).padEnd(CHIP_W)} `
}
// A run of a line's text and its style. A row is drawn from these so it can be cut to the pane's width.
type Style = { color?: Color; backgroundColor?: Color; bold?: true; dimColor?: true; underline?: true }
export type Seg = [string, Style?]
const seg = (text: string, style?: Style): Seg => [text, style]
// The runs cut to `width` columns, an ellipsis where they were cut.
// ponytail: a code point is a column; a wide glyph (CJK, emoji) overruns by one each. string-width if they show.
export function clip(segs: Seg[], width: number): Seg[] {
  const len = (t: string) => [...t].length
  if (segs.reduce((n, [t]) => n + len(t), 0) <= width) return segs
  const out: Seg[] = []
  let left = width - 1 // the ellipsis's column
  for (const [text, style] of segs) {
    if (left <= 0) break
    out.push([[...text].slice(0, left).join(''), style])
    left -= len(text)
  }
  const last = out.at(-1)
  return width > 0 && last ? [...out.slice(0, -1), [`${last[0].trimEnd()}…`, last[1]]] : []
}
// The text broken at spaces into lines of at most `width` columns; a longer word is broken across lines.
export function wrapText(text: string, width: number) {
  const w = Math.max(width, 1)
  const lines: string[] = []
  let line = ''
  for (const word of text.split(' ')) {
    if (line && [...line].length + 1 + [...word].length > w) {
      lines.push(line)
      line = ''
    }
    let cps = [...(line ? `${line} ${word}` : word)]
    for (; cps.length > w; cps = cps.slice(w)) lines.push(cps.slice(0, w).join(''))
    line = cps.join('')
  }
  return line ? [...lines, line] : lines
}
// Colour roles: a solid chip (the colour as background, the theme's inverse text on it, a ● so it reads
// without colour too) is on the user, once per thing the header counts; coloured bold words are a state; dim
// is detail. Theme keys only, so a light theme gets its own shades.
const solid = (color: Color): Style => ({ backgroundColor: color, color: 'inverseText', bold: true })
const solidChip = (label: string, color: Color = 'warning') => seg(` ● ${label.toUpperCase().padEnd(CHIP_W - 2)} `, solid(color))
const wordChip = (label: string, color: Color) => seg(chipText(label), { color, bold: true })
// The status footer of finished tasks' leftovers idle a week (session-status): collapsed until pressed.
export const RESOLVED = 'Resolved (idle a week)'
// The status footer of prompts unanswered for hours (session-status): answer or stop, not counted on you.
export const STALE = 'Stale prompts'
// Each section's accent; a footer section the status command adds later gets suggestion.
const ACCENT = {
  'Waiting on you': 'warning', Decisions: 'warning', [STALE]: 'inactive', 'Needs action': 'error', 'In review': 'ide', Working: 'suggestion', Landing: 'success',
  Idle: 'inactive', Notices: 'ide', Actions: 'claude', Pending: 'planMode', [RESOLVED]: 'inactive', [OTHER_PROJECTS]: 'inactive',
} as const satisfies Record<string, Color>
const accentOf = (title: string): Color => (ACCENT as Record<string, Color>)[title] ?? 'suggestion'
const sessLabel = (s: Sess) => (s.state === 'none' ? `no session${s.maybe && ` (maybe ${s.maybe})`}` : `${s.name} ${s.state}`)
const ago = (ms: number) => (ms < 60_000 ? 'just now' : ms < 3600_000 ? `${Math.floor(ms / 60_000)}m ago` : `${Math.floor(ms / 3600_000)}h ago`)
// The task key in a session's name (`pr review proj-4679`), as the tracker writes it; only a key the board has.
export const keyIn = (name: string, keys: Set<string>) =>
  [...name.matchAll(/\b[a-z][a-z0-9]+-\d+\b/gi)].map(m => m[0].toUpperCase()).find(k => keys.has(k))
const DAY = 86_400_000

// What needs the user, one per task where a key ties them: approvals, blocked tasks, sessions waiting on the
// user, pending items on the user. A waiting session is counted under the task whose row names it, a task key
// in its name, or itself.
export function onYouOf(list: Ask[], st: Status | undefined, pend: ReturnType<typeof parsePending>, hs: Handed[] = []) {
  const taskKeys = new Set(st?.tasks.map(t => t.key))
  const waitKey = (name: string) => st?.tasks.find(t => t.sess.name === name)?.key ?? keyIn(name, taskKeys)
  const waitSec = st?.sections.find(s => s.title === 'Waiting on you')
  const set = new Set(list.map(a => `ask ${a.id}`))
  for (const h of hs) set.add(h.key) // a handed-over command counts under its task
  for (const t of st?.tasks ?? []) if (t.sess.state === 'blocked') set.add(t.key)
  for (const i of waitSec?.items ?? []) {
    const w = waitingOf(i)
    if (w) set.add(waitKey(w.name) ?? `session ${w.name}`)
  }
  for (const p of pend ?? []) {
    const { key, onYou: mine } = pendingOf(p.text)
    if (mine) set.add(key ?? p.text)
  }
  return { set, waitSec, waitKey }
}
// The status line under the prompt: the header's count, so it shows while the pane is closed, waiting for a
// wider terminal, or scrolled. Only once the pane has been opened (a coordinator): a worker never sets it.
// ponytail: an ask past its TTL leaves the count at the next sweep or click, not on the hour.
// ponytail: synced by hand at each write of asks and board (this file); a wrapper once one is missed.
async function syncStatus($: EngineInterface) {
  if (!timer) return
  const b = await read($, board)
  const list = await liveAsks($, await $.clock.now())
  const hs = await read($, handed)
  // 4: nothing known yet (no sweep, no ask): clear a count set before rather than leave it standing.
  if (!b && list.length === 0 && hs.length === 0) return $.ui.status(undefined)
  const n = onYouOf(list, b ? parseStatus(b.status) : undefined, b ? parsePending(b.pending) : undefined, hs).set.size
  $.ui.status(n > 0 ? `◆ ${n} on you · /coordinator` : '◆ nothing on you')
}
// Runs a project action in the project root, keeps its outcome (the last line it printed) for the pane, then
// refreshes. One at a time: a press while one runs does nothing.
// ponytail: one action at a time; per-action busy if a project wants two running together.
async function runAction($: EngineInterface, a: PaneAction) {
  let free = false
  await update($, actionBusy, cur => ((free = cur === null) ? a.label : cur))
  if (!free) return
  let result: Omit<ActionResult, 'at'>
  try {
    const cwd = (await read($, actions))?.root
    if (!cwd) throw new Error('project root unknown (session-status --root)')
    const r = await $.process.run(['bash', '-c', a.command], { cwd, timeoutMs: 300_000 })
    const last = `${r.stdout}\n${r.stderr}`.split('\n').map(l => l.trim()).filter(Boolean).at(-1) ?? ''
    result = { label: a.label, ok: r.exitCode === 0, line: r.exitCode === 0 ? last : `exit ${r.exitCode}${last ? `: ${last}` : ''}` }
  } catch (err) {
    result = { label: a.label, ok: false, line: err instanceof Error ? err.message : String(err) }
  } finally {
    await update($, actionBusy, () => null)
  }
  const at = new Date(await $.clock.now()).toTimeString().slice(0, 5)
  await update($, actionResult, () => ({ ...result, at }))
  await inFlight // a sweep started before the action ran would show the state before it
  await refresh($)
}

// The asks still answerable: verify-approval.sh accepts an answer for TTL_MS; one being sent isn't.
// ponytail: a session that dies mid-submit leaves its ask `sending`, hidden until the TTL drops it.
const liveAsks = async ($: EngineInterface, now: number) => (await read($, asks)).filter(a => now - a.at < TTL_MS && !a.sending)
const unsent = ({ sending, ...a }: Ask): Ask => a
// Drops the asks `hit` matches, then the open choices and status count they leave; resolves to the ones dropped.
async function dropAsks($: EngineInterface, hit: (a: Ask) => boolean) {
  let dropped: Ask[] = []
  await update($, asks, l => {
    dropped = l.filter(hit)
    return dropped.length ? l.filter(a => !hit(a)) : l
  })
  if (dropped.length) {
    await pruneOpen($, await $.clock.now())
    await syncStatus($)
  }
  return dropped
}

// A review finding's ask (one with a kind) that expired unanswered comes back to the coordinator: a first ask to
// re-ask once as a reminder, an expired reminder (question starts REMINDER) to record as dropped. Never starts
// "Approval pane answer for ". Keep in sync with coordinator.md (Messaging).
export const REMINDER = 'Reminder: '
const isReminder = (a: Ask) => a.question.startsWith(REMINDER)
export const expiredText = (as: Ask[]) => {
  const list = (xs: Ask[]) => xs.map(a => `${a.key} (id ${a.id}) ${oneLine(a.question)}`).join('; ')
  const first = as.filter(a => !isReminder(a))
  const reminders = as.filter(isReminder)
  return [
    'Approval pane: review finding asks expired unanswered after 24h (coordinator.md, Messaging).',
    ...(first.length ? [`Re-ask each once, the same ask with its question starting "${REMINDER}": ${list(first)}.`] : []),
    ...(reminders.length ? [`These reminders expired too, so they are dropped: record each in its review file's header and tell its reviewer session: ${list(reminders)}.`] : []),
  ].join(' ')
}
// Claimed by removing them before the submit, so a tick while the coordinator is mid-turn (submit waits for idle)
// finds nothing to announce twice; put back if the prompt doesn't enter, for the next minute to retry.
// ponytail: retries silently each minute; add a toast if a refusing hook ever makes that a loop.
async function expireReviewAsks($: EngineInterface) {
  const now = await $.clock.now()
  const gone = await dropAsks($, a => !!a.kind && !a.sending && now - a.at >= TTL_MS)
  if (!gone.length) return
  const r = await $.prompt.submit({ text: expiredText(gone) }).catch((err: unknown) => ({ drop: String(err) }))
  if (r.drop !== undefined) {
    await update($, asks, l => [...l, ...gone])
    await syncStatus($)
  }
}

const ASK_SCHEMA = {
  type: 'object',
  properties: {
    key: { type: 'string', description: 'The task key, e.g. PROJ-123' },
    question: { type: 'string', description: 'The question, naming the task key and the action' },
    options: {
      type: 'array', minItems: 2, maxItems: 6, items: { type: 'string' },
      description: 'Button labels. Each stands alone: names the task key and the exact action, e.g. "Yes, merge PROJ-123 (PR #45)" / "No, don\'t merge PROJ-123"',
    },
    details: { type: 'string', description: 'Optional markdown the pane shows when the ask is expanded: what the user needs to decide (a diff summary, the reply being answered). Not part of the answer.' },
    target: { type: 'string', description: 'Optional: where the action lands, e.g. "app#282 src/a.ts:42" for an inline comment, "app#282 general", "PROJ-5195" for a Jira comment.' },
    kind: { type: 'string', enum: KINDS, description: 'Optional, with body_file only: a PR review finding\'s kind: issue (the code is wrong), suggestion (it works but could be better), question (scope or intent the author or PO decides). The pane shows it as a badge and sorts issues first.' },
    body_file: { type: 'string', description: 'Optional absolute path of a comment body file, prepared before asking. The pane reads it now and shows its text (as markdown) and sha256; the sha256 the question names must be this one.' },
  },
  required: ['key', 'question', 'options'],
}

const CANCEL_SCHEMA = {
  type: 'object',
  properties: {
    key: { type: 'string', description: 'The task key the asks were queued under' },
    id: { type: 'string', description: 'Optional: the ask id ask_approval returned; removes that ask only' },
    question: { type: 'string', description: 'Optional: the exact question of the ask to remove; removes that ask only' },
  },
  required: ['key'],
}

export const COMMAND_MAX = 2000 // a handed-over command's length
const HAND_SCHEMA = {
  type: 'object',
  properties: {
    key: { type: 'string', description: 'Your task key, e.g. PROJ-123 (no ticket: your 3-5 word task name joined by -)' },
    command: { type: 'string', maxLength: COMMAND_MAX, description: 'The command, one line, exactly as the user would type it after `!`, e.g. make release' },
    what: { type: 'string', maxLength: 200, description: 'One line on what it does and why you can\'t run it, e.g. "Pushes main and publishes the release"' },
  },
  required: ['key', 'command', 'what'],
}

// A leading letter or digit: `/rename -x` mustn't read as a flag.
const SESSION_NAME = '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
const NAME_SCHEMA = {
  type: 'object',
  properties: { name: { type: 'string', pattern: SESSION_NAME, maxLength: 64, description: 'The new name: <KEY>-<short-desc>, e.g. PROJ-1234-fix-settler' } },
  required: ['name'],
}

async function runStatus($: EngineInterface, args: string[]) {
  const script = `${$.plugin.root}/skills/orchestrating-sessions/session-status`
  try {
    // The plugin-feedback footer is the coordinator's to read, once a day: the pane's sweeps mustn't use it up.
    const r = await $.process.run(['bash', script, ...args], { timeoutMs: 180_000, env: { SESSION_STATUS_NO_FEEDBACK: '1' } })
    return r.exitCode === 0 || r.stdout ? r.stdout.trimEnd() : ''
  } catch (err) {
    return `failed: ${err instanceof Error ? err.message : String(err)}`
  }
}

// The project's file actions whose `when` exits 0 in the project root (each check capped at 10s), and what was
// wrong with the file. Read again each sweep, so an edit shows at the next one.
// ponytail: the root is asked once per module life; a pane of another project is another session.
let root: string | undefined
async function projectRoot($: EngineInterface) {
  if (!root) {
    const r = await runStatus($, ['--root'])
    if (r.startsWith('/') && !r.includes('\n')) root = r
  }
  return root
}
async function loadActions($: EngineInterface): Promise<Actions | null> {
  const root = await projectRoot($)
  if (!root) return null
  const path = `${root}/${ACTIONS_FILE}`
  let text: string
  try {
    if (!(await $.fs.exists(path))) return { root, shown: [], owned: [], errors: [] }
    text = String(await $.fs.read(path))
  } catch (err) {
    return { root, shown: [], owned: [], errors: [`${ACTIONS_FILE}: ${err instanceof Error ? err.message : String(err)}`] }
  }
  const { list, errors } = parseActions(text)
  const cwd = root
  const checks = await Promise.all(list.map(async a => {
    if (!a.when) return true
    try {
      return (await $.process.run(['bash', '-c', a.when], { cwd, timeoutMs: 10_000 })).exitCode === 0
    } catch (err) {
      errors.push(`"${a.label}" when: ${err instanceof Error ? err.message : String(err)}`)
      return false
    }
  }))
  return { root, shown: list.filter((_, i) => checks[i]), owned: list.map(a => a.label), errors }
}

// One sweep at a time: a Refresh press or a tick during one joins it.
let inFlight: Promise<void> | undefined
function refresh($: EngineInterface) {
  inFlight ??= (async () => {
    await update($, refreshing, () => true)
    const [status, pending, urls, acts, term] = await Promise.all([
      runStatus($, []), runStatus($, ['--pending']), runStatus($, ['--urls']), loadActions($),
      runStatus($, ['--config', 'terminal']), refreshActivity($),
    ])
    await update($, actions, () => acts)
    // A name only: a failed run's `failed: …` text means none.
    await update($, terminal, () => /^[A-Za-z0-9_-]+$/.test(term) ? term : 'plain')
    const agents = await runStatus($, ['--agents']) // what the sweep just saw
    const at = new Date(await $.clock.now()).toTimeString().slice(0, 5)
    await update($, board, (): Board => ({ status, pending, urls, agents, at }))
    await loadHanded($).catch(() => undefined) // again, now with the sessions this sweep saw
    await syncStatus($)
  })().finally(() => {
    inFlight = undefined
    void update($, refreshing, () => false)
  })
  return inFlight
}

// What live sessions are doing: cheap (no tracker calls), so every minute, between sweeps.
// One at a time, like a sweep: a tick during one joins it, so an older reading never lands after a newer one.
let activityInFlight: Promise<void> | undefined
function refreshActivity($: EngineInterface) {
  activityInFlight ??= (async () => {
    const text = await runStatus($, ['--activity', ...((await read($, allProjects)) ? ['--all-projects'] : [])])
    await update($, activity, () => text)
    await loadHanded($).catch(() => undefined) // an unreadable folder leaves the list as it was
  })().finally(() => {
    activityInFlight = undefined
  })
  return activityInFlight
}

// Handed-over commands: a session's `!` command for the user (hand_command), one file each in HANDED_DIR under
// $HOME, which every account and the pane share. The pane lists them under their task key; Run makes the Bash call
// in this (the coordinator's) session with the press as the user's consent, so it goes through this session's hooks,
// permission rules, classifier and dialog like any call the user asked for, and nothing a session wrote runs unseen
// or unpressed. Copy is the fallback where that refuses it.
export const HANDED_DIR = '.cache/session-status/commands'
export const HANDED_TTL = 3 * 86_400_000 // ponytail: a command older than 3 days is stale; its session can hand it again
// Unset, or no environment to read (a test that mocks none), reads as ''. $.env.get takes a literal name.
const accountOf = async ($: EngineInterface) => (await $.env.get('CLAUDE_CONFIG_DIR').catch(() => undefined)) ?? ''
const handedDir = async ($: EngineInterface) => `${(await $.env.get('HOME').catch(() => undefined)) ?? ''}/${HANDED_DIR}`
// What's wrong with a hand_command call, or undefined. One line, no control or bidi character: the pane shows it
// whole and Run runs exactly what it shows.
export function handedProblem(key: unknown, command: unknown, what: unknown): string | undefined {
  if (typeof key !== 'string' || !/^\S{1,64}$/.test(key)) return 'key is the task key (or a 3-5 word name joined by -), no spaces'
  if (typeof command !== 'string' || !command.trim()) return 'command is the command the user would run after `!`'
  if (typeof what !== 'string' || !what.trim()) return 'what says in one line what the command does'
  if ([key, command, what].some(x => clean(x) !== x || /[\t\n\u061c\u200b-\u200f\u2028\u2029\ufeff]/.test(x))) return 'key, command and what are one line each, with no control, bidi or zero-width characters'
  if (command.length > COMMAND_MAX) return `command is at most ${COMMAND_MAX} characters`
  if (what.length > 200) return 'what is at most 200 characters'
}
// A handed-over command's file, checked as hand_command checks its input (the file is anyone's to write).
export function parseHanded(text: string): Handed | undefined {
  let o: Record<string, unknown>
  try {
    o = JSON.parse(text)
  } catch {
    return
  }
  const { id, key, session, cwd, account, command, what, at } = o ?? {}
  if (typeof id !== 'string' || !/^[0-9a-f]{16}$/.test(id) || typeof session !== 'string' || typeof cwd !== 'string' ||
      typeof account !== 'string' || typeof at !== 'number' || handedProblem(key, command, what)) return
  return { id, key: String(key), session, cwd, account, command: String(command), what: String(what), at }
}
export const handedId = async (session: string, command: string) =>
  [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`${session}\n${command}`)))]
    .slice(0, 8).map(b => b.toString(16).padStart(2, '0')).join('')
// The press, in the user's words, as the Bash call's consent: what the permission path reads as their request. Only
// the press and the command it showed: the session's own words (key, what) would speak in the user's voice.
export const runConsent = (h: Handed) => `The user pressed "Run" in the coordinator pane on this exact command: ${h.command}`
// Tells the coordinator a Run's outcome, to pass on to the session that handed it over. Not asUser: it states a
// result, it approves nothing.
export const ranText = (h: Handed, ok: boolean, line: string) =>
  `Coordinator pane: the user ran the command session ${h.session.slice(0, 8)} handed over for ${h.key} (${h.what}); it ${ok ? 'succeeded' : 'failed'}${line ? `: ${line}` : ''}. Command: ${h.command}. Pass it on per coordinator.md (Handed-over commands).`

// Handed commands this pane removed, with when it handed them: a read that raced the removal can't bring one back,
// while the same command handed again later (a newer `at`) shows.
const droppedHanded = new Map<string, number>()
// Reads this pane's handed-over commands (each sweep and each minute), oldest first; one past HANDED_TTL is
// removed. A command being run, or whose last Run failed, keeps that. This pane's: its session is one the sweep
// lists (`agents`: a plugin session it runs works in another repo's worktree, which 0.36.0's folder-only filter
// hid), or its folder is under the root; with all projects on, every one. Before the first sweep, every one.
async function loadHanded($: EngineInterface) {
  if (!timer) return // a worker draws no pane
  const dir = await handedDir($)
  const now = await $.clock.now()
  const root = await projectRoot($)
  const b = await read($, board)
  const here = new Set((b?.agents ?? '').split('\n').map(l => l.split('\t')[0]))
  const all = (await read($, allProjects)) || !b
  const mine = (h: Handed) => all || here.has(h.session) || under(root, h.cwd)
  const files = (await $.fs.exists(dir)) ? (await $.fs.list(dir)).filter(f => f.kind === 'file' && f.name.endsWith('.json')) : []
  const read_ = await Promise.all(files.map(async f => {
    const h = parseHanded(String(await $.fs.read(`${dir}/${f.name}`).catch(() => '')))
    if (h && now - h.at > HANDED_TTL) {
      await $.process.run(['rm', '-f', `${dir}/${f.name}`]).catch(() => undefined)
      return
    }
    return h && f.name === `${h.id}.json` ? h : undefined
  }))
  const found = read_
    .filter((h): h is Handed => !!h && mine(h) && h.at > (droppedHanded.get(h.id) ?? -1))
    .sort((a, b) => a.at - b.at)
  await update($, handed, cur => found.map(h => {
    const was = cur.find(c => c.id === h.id && c.command === h.command)
    return { ...h, ...(was?.running ? { running: true as const } : {}), ...(was?.outcome ? { outcome: was.outcome } : {}) }
  }))
  if (!found.length) await update($, handedResult, () => null) // the last Run's line shows until the next read
  await syncStatus($)
}
async function dropHanded($: EngineInterface, h: Handed) {
  droppedHanded.set(h.id, h.at)
  await $.process.run(['rm', '-f', `${await handedDir($)}/${h.id}.json`])
  await update($, handed, l => l.filter(x => x.id !== h.id))
  await syncStatus($)
}
// Run: the Bash call in this session, with the press as consent. Succeeded: the file goes; refused or failed: it
// stays with the outcome, for another Run or Copy. One Run per command at a time.
async function runHanded($: EngineInterface, h: Handed) {
  let free = false
  await update($, handed, l => l.map((x): Handed => {
    if (x.id !== h.id || x.running) return x
    free = true
    return { ...x, running: true }
  }))
  if (!free) return
  let ok = false, line = ''
  try {
    const r = await $.tool.call({ tool: 'Bash', command: h.command, description: h.what, timeout: 600_000, consent: runConsent(h) })
    if (r.deny !== undefined) line = `refused: ${oneLine(r.deny)}`
    else {
      ok = !r.isError
      line = oneLine((r.text ?? '').split('\n').map(l => l.trim()).filter(Boolean).at(-1) ?? '')
    }
  } catch (err) {
    line = err instanceof Error ? err.message : String(err)
  }
  const at = new Date(await $.clock.now()).toTimeString().slice(0, 5)
  await update($, handedResult, () => ({ label: `${h.key}: ${h.what}`, ok, line, at }))
  if (ok) await dropHanded($, h)
  else await update($, handed, l => l.map(({ running, ...x }): Handed => (x.id === h.id ? { ...x, outcome: line || 'failed' } : { ...x, ...(running ? { running } : {}) })))
  await $.prompt.submit({ text: ranText(h, ok, line) })
}

// Makes an idle background session run /compact (session-status --compact: stop, then resume it with /compact),
// shows the outcome, and reads activity again.
// One per session at a time: a second press while it runs (the activity it was offered on is up to a minute old)
// would find the session stopped and resume it alongside the first, starting a copy.
async function nameCoordinator($: EngineInterface) {
  const r = await projectRoot($)
  if (!r) return 'No project root, so this session keeps its name.'
  const name = `${(r.split('/').pop() ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')}-coordinator`
  await update($, naming, () => name) // a command can't run inside the tool call: turn.complete runs it
  return `This session becomes "${name}" when this turn ends: put that name in briefs.`
}

// The bootstrap trigger (skill setting-up-coordination): a folder not set up for coordination says so in open_pane's
// result, so the coordinator proposes the setup without having to remember to check. Set up, it gives the config in
// effect and its warnings instead.
async function initCheck($: EngineInterface): Promise<{ setUp: boolean, text: string }> {
  try {
    const r = await $.process.run(['bash', `${$.plugin.root}/skills/orchestrating-sessions/session-status`, '--init', '--check'], { timeoutMs: 30_000 })
    const line = oneLine(r.stdout)
    if (r.exitCode === 1) return { setUp: false, text: ` Not set up for coordination (${line}): run session-status --init and propose the setup (skill setting-up-coordination).` }
    if (r.exitCode === 3) return { setUp: false, text: ` This folder is ${line}. Tell the user, and ask whether this folder gets a coordinator of its own; if they meant the parent's project, its coordinator runs from there (skill setting-up-coordination).` }
    // configured: the lines after the first are the config in effect and its warnings
    const rest = r.stdout.split('\n').slice(1).map(l => l.trim()).filter(Boolean).join('; ')
    return { setUp: true, text: rest && ` Coordination config: ${rest}.` }
  } catch {
    return { setUp: true, text: '' }
  }
}

async function runCompact($: EngineInterface, id: string, name: string) {
  let taken = false // checked and marked in one write: a second press before the redraw finds it busy
  await update($, compacting, l => ((taken = !l.includes(id)) ? [...l, id] : l))
  if (!taken) return $.ui.toast(`Compact "${name}" is already running`)
  try {
    const r = await $.process.run(['bash', `${$.plugin.root}/skills/orchestrating-sessions/session-status`, '--compact', id], { timeoutMs: 300_000 })
    $.ui.toast(r.exitCode === 0 ? oneLine(r.stdout) : `Compact "${name}": ${oneLine(r.stdout || r.stderr) || `exit ${r.exitCode}`}`)
  } catch (err) {
    $.ui.toast(`Compact "${name}" failed: ${err instanceof Error ? err.message : String(err)}`)
  } finally {
    await update($, compacting, l => l.filter(x => x !== id))
    // A fresh reading: one started before the stop and resume would still say idle and offer Compact again.
    await activityInFlight
    await refreshActivity($)
  }
}

// A card's Peek or Diff: a press opens it under that card (closing the other), a second press closes it. `args`:
// the session id for --peek; the task key and/or session id for --diff, the first that resolves.
async function togglePeek($: EngineInterface, row: string, kind: Peek['kind'], args: string[]) {
  let opening = false
  await update($, peek, p => ((opening = !(p?.row === row && p.kind === kind)) ? { row, kind, text: '', loading: true as const } : null))
  if (!opening) return
  const text = await runStatus($, [kind === 'peek' ? '--peek' : '--diff', ...args])
  // Still the one asked for: a press elsewhere meanwhile wins.
  await update($, peek, p => (p?.row === row && p.kind === kind ? { row, kind, text } : p))
}
// The Yesterday tab's reading for the picked day (null: the last working day), session-status --yesterday:
// slow (the tracker), so the last reading stays shown, marked loading, until the new one lands.
async function loadYesterday($: EngineInterface) {
  const day = await read($, ydDay)
  await update($, ydText, cur => ({ day, text: cur?.text ?? '', at: cur?.at ?? '', loading: true as const }))
  const text = await runStatus($, ['--yesterday', ...(day ? [day] : [])])
  const at = new Date(await $.clock.now()).toTimeString().slice(0, 5)
  // Still the day asked for: a step meanwhile started its own reading.
  if ((await read($, ydDay)) !== day) return
  await update($, ydText, () => ({ day, text, at }))
  await summarize($, text)
}
// The reading as a few spoken standup sentences (standup-summary: a small model, cached per day until the day's data
// changes). The list shows meanwhile and when it fails; the summary is drawn only beside the reading it was made of.
// Not while the list is chosen (s): a run is a paid model call; switching back starts one. While it runs, the same
// day's last summary stays up. Only the latest run lands (a refresh meanwhile starts its own).
let sumSeq = 0
async function summarize($: EngineInterface, of: string) {
  if (!of.startsWith('Since: ')) return update($, ydSum, () => null)
  if (await read($, ydList)) return
  const mine = ++sumSeq
  const dayOf = (t: string) => t.slice(0, t.indexOf(' ', 7))
  await update($, ydSum, s => ({ of, text: s && dayOf(s.of) === dayOf(of) ? s.text : '', loading: true as const }))
  let text = ''
  let failed: string | undefined
  try {
    const r = await $.process.run(['bash', `${$.plugin.root}/skills/orchestrating-sessions/standup-summary`], { stdin: of, timeoutMs: 120_000 })
    text = r.exitCode === 0 ? r.stdout.trim() : ''
    if (!text) failed = oneLine(r.stdout || r.stderr) || `exit ${r.exitCode}`
  } catch (err) {
    failed = err instanceof Error ? err.message : String(err)
  }
  if (mine === sumSeq) await update($, ydSum, () => ({ of, text, ...(failed ? { failed } : {}) }))
}
// A card's Attach in tab (a tab titled "<name> attach", reused once open) or Logs in split (`claude logs` beside
// the focused pane), as `session-status --open` arguments for the configured terminal. `command`: the card's
// `PREFIX attach ID`; the prefix picks the account, `cur` (this process's CLAUDE_CONFIG_DIR) for plain `claude`.
export function openArgs(view: 'attach' | 'logs', command: string, name: string, cwd: string, cur: string | undefined) {
  const m = /^(.*?) attach (\S+)$/.exec(command)
  if (!m) return undefined
  const [, pre = '', id = ''] = m
  const account = pre === 'claude' ? cur : /^CLAUDE_CONFIG_DIR=(\S+) claude$/.exec(pre)?.[1] // env -u …: the default
  return [
    '--open', view === 'attach' ? 'view' : 'split',
    ...(account ? ['--account', account] : []),
    ...(view === 'attach' ? [`${name} attach`] : []),
    cwd, '--', 'claude', view, id,
  ]
}
// When the terminal opens nothing (exit 2: Ghostty not running) it copies the command instead.
// The plugin is shared: a terminal is a convenience, never a dependency.
async function openInTerminal($: EngineInterface, p: UiPressArgument, term: string, view: 'attach' | 'logs', command: string, name: string, cwd: string) {
  const fallback = command.replace(/ attach (\S+)$/, ` ${view} $1`)
  const args = openArgs(view, command, name, cwd, await $.env.get('CLAUDE_CONFIG_DIR'))
  const r = args && await $.process.run(['bash', `${$.plugin.root}/skills/orchestrating-sessions/session-status`, ...args], { timeoutMs: 30_000 })
  if (r?.exitCode === 0) return $.ui.toast(`${view === 'attach' ? 'Attached' : 'Logs of'} "${name}" in ${term}${r.stdout.startsWith('reused') ? ' (its open tab)' : ''}`)
  if (r && r.exitCode !== 2) return $.ui.toast(`${term}: ${oneLine(r.stderr || r.stdout) || 'no output'} (exit ${r.exitCode})`)
  const c = await $.ui.copy({ text: fallback, surface: p.surface })
  // Its stderr's last line says why (a module's warnings come before it).
  const why = !r ? 'no session id in its command' : r.stderr.trim().split('\n').at(-1) || `${term} opened nothing`
  $.ui.toast(c.isCopied ? `${why}: copied ${fallback}` : `${why}, and couldn't copy (${c.reason}): ${fallback}`)
}

// ponytail: the timers (sweep 10 min, activity 1 min, ~1s each) run for the module's life once opened, a
// closed pane included; cancel both on ui.close if they cost too much.
let timer: { cancel: () => void } | undefined
async function open($: EngineInterface) {
  const opened = await $.ui.open({ id: PANE, title: 'Coordinator' })
  if (!timer) {
    timer = $.clock.every(600_000, () => void refresh($))
    $.clock.every(60_000, () => void refreshActivity($))
    void refresh($)
  }
  return opened
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await $.tool.register({
      name: 'open_pane',
      description: 'Coordinator only: opens the coordinator pane beside the conversation. The pane shows the queued approval asks as buttons, the output of the project\'s status command and the adapter\'s pending text, refreshed every 10 minutes and on its Refresh button. Call it once at the start of a coordinator session; a worker session never calls it. It shows only in an interactive terminal session with the plugin loaded, and waits until the terminal is about 144 columns wide (110 once the user has opened it themselves; the user\'s /coordinator command opens it at any width); it never shows in the agent view or a background session, so there, ask in plain text.',
    })
    await $.tool.register({
      name: 'ask_approval',
      description: 'Coordinator only: queue a reserved approval as buttons in the coordinator pane instead of the question box. Returns at once; the user\'s click arrives later as a prompt "Approval pane answer for <KEY>: <option>. Asked: <question>", which is the Quote for a relayed approval. Unanswered asks expire after 24h; an expired one with a kind (a review finding) comes back to you as a prompt: re-ask it once with the question starting "Reminder: "; an expired reminder is dropped (record it and tell the reviewer). Keep the question one line; put what the user should read in details (markdown), target, and for a comment post body_file (the body file, written first: the pane shows its text and sha256). Use it only for an action the project reserves for the user, one action per ask; ask anything else in plain text, or in the question box when the answer needs the user\'s own words (coordinator.md, Messaging).',
      inputSchema: ASK_SCHEMA,
    })
    await $.tool.register({
      name: 'cancel_approval',
      description: 'Coordinator only: remove asks queued with ask_approval from the coordinator pane, submitting no answer. Pass key alone to remove every ask for that key, or with id (as ask_approval returned it; it wins over question) or question (exact text) to remove one. To replace an ask, queue the new one, then cancel the old by id. Returns what it removed, or that nothing matched.',
      inputSchema: CANCEL_SCHEMA,
    })
    await $.tool.register({
      name: 'reload_plugins',
      description: 'Runs /reload-plugins in this session when the current turn ends, so a plugin just updated (`claude plugin update`) takes effect without the user typing it. It reloads only the session that calls it: to reload a worker, message it to call this tool. New tools register on the reload: load them with ToolSearch in the next turn.',
    })
    await $.tool.register({
      name: 'name_session',
      description: 'Task sessions only (never the coordinator, never a subagent): renames this session when the current turn ends (/rename), so it shows under that name in `claude agents`, ListAgents and the coordinator pane. Call it once, when you learn your task key and your first prompt didn\'t name it: name `<KEY>-<short-desc>`, e.g. PROJ-1234-fix-settler (a review session: `<KEY>-review-<short-desc>`). Letters, digits, . _ -, starting with a letter or digit, at most 64 characters.',
      inputSchema: NAME_SCHEMA,
    })
    await $.tool.register({
      name: 'hand_command',
      description: 'Any session: hand the user a command to run themselves (one you would otherwise give as `! <command>`: a classifier-refused CLI call, a release or deploy command, a settings or hook change). It shows in the coordinator pane under the task key with your session id and `what`, where the user runs it with one press (or copies it). Still put the `! <command>` line in your report: without a pane the user runs it by hand. The command is one line, run exactly as written in the coordinator\'s folder and account, so make it independent of your cwd (absolute paths). Don\'t wait on it: the coordinator tells you the outcome. Handing the same command again replaces it.',
      inputSchema: HAND_SCHEMA,
    })
    // immediate: it only opens or closes the pane, so it runs mid-turn, when a queued approval may be waiting.
    await $.command.register({ name: 'coordinator', description: 'Open the coordinator pane at any width (close: close it)', argumentHint: '[close]', immediate: true })
    // A reload (reload_plugins) keeps the pane up but starts this module over, its timers gone: start them again.
    if ((await $.ui.panes()).some(p => p.id === PANE)) await open($)
    // Apart from the pane's timers: a review ask's 24h runs out with the pane closed too. A session with no asks
    // reads an empty list each minute.
    $.clock.every(60_000, () => void expireReviewAsks($).catch(() => undefined)) // unclaimed or put back: next minute
    return started
  })

  // The person's command: the pane opens at any width, where open_pane's unasked one waits for 144 columns.
  on('command.run', { command: 'coordinator' }, async ($, e) => {
    const arg = e.args.trim().toLowerCase()
    if (arg === 'close') {
      await $.ui.close({ id: PANE })
      return { text: 'Coordinator pane closed.' }
    }
    if (arg) return { text: `Unknown argument "${e.args.trim()}". Usage: /coordinator [close]` }
    const opened = await open($)
    return { text: opened.isPlaced ? 'Coordinator pane open.' : `The pane isn't drawn: ${opened.reason}.` }
  })

  // open_pane is the coordinator's first call, so it also gives the session its stable name, `<project>-coordinator`
  // (the root folder's name), for briefs to name across restarts (workers still resolve it at send time).
  on('tool.call', { tool: 'mcp__session-orchestration__open_pane' }, async $ => {
    const { isPlaced } = await open($)
    root = undefined // a bootstrap may have just moved the root (an own adapter under a parent's)
    const init = await initCheck($)
    // Not set up yet: no name, which would be the parent's coordinator's or not the one the setup writes.
    const named = !init.setUp ? 'This session keeps its name until the folder is set up; open_pane names it then.' : await nameCoordinator($)
    return { result: `${isPlaced ? 'Coordinator pane open.' : 'The pane is waiting: this terminal is too narrow or draws no panes. Tell the user /coordinator opens it at any width.'} ${named}${init.text}` }
  })

  // Any session's own name, `<KEY>-<short-desc>` once it knows its task, through open_pane's /rename at turn end.
  on('tool.call', { tool: 'mcp__session-orchestration__name_session' }, async ($, e) => {
    const { name } = e
    // A subagent's call would rename its parent at the parent's turn end.
    if (e.agentId) return { deny: 'name_session renames the main session: a subagent never calls it.' }
    if (typeof name !== 'string' || !new RegExp(SESSION_NAME).test(name)) {
      return { deny: 'name_session needs name: 1-64 characters of A-Z a-z 0-9 . _ -, starting with a letter or digit, e.g. PROJ-1234-fix-settler.' }
    }
    // Workers message the coordinator by that name: a task session taking it would get their reports.
    if (name.endsWith('-coordinator')) return { deny: 'name_session: a "-coordinator" name is the coordinator\'s (open_pane gives it).' }
    await update($, naming, () => name)
    return { result: `This session becomes "${name}" when this turn ends.` }
  })

  // A session's `!` command for the user, into HANDED_DIR for the coordinator pane (any session, any account).
  on('tool.call', { tool: 'mcp__session-orchestration__hand_command' }, async ($, e) => {
    const { key, command, what } = e
    const bad = handedProblem(key, command, what)
    if (bad) return { deny: `hand_command: ${bad}.` }
    const session = await $.session.id()
    const h: Handed = {
      id: await handedId(session, String(command)), key: String(key), session, cwd: await $.session.cwd(),
      account: await accountOf($), command: String(command), what: String(what), at: await $.clock.now(),
    }
    await $.fs.write(`${await handedDir($)}/${h.id}.json`, JSON.stringify(h))
    return { result: `Handed to the user in the coordinator pane under ${h.key} (id ${h.id}). Also give them \`! ${h.command}\` in your report. Don't wait on it or run it yourself.` }
  })

  // The commands a tool call queued for the turn's end: /rename (open_pane, name_session), then /reload-plugins (reload_plugins).
  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId) return done
    const failed: string[] = []
    const run = async (command: string, args: string, what: string) => {
      try {
        await $.command.run({ command, args })
      } catch (err) {
        failed.push(`${what} failed (${err instanceof Error ? err.message : String(err)}). Run /${command}${args ? ` ${args}` : ''}.`)
      }
    }
    const name = await read($, naming)
    if (name) {
      await update($, naming, () => null)
      await run('rename', name, `Renaming this session to "${name}"`)
    }
    if (await read($, reloading)) {
      await update($, reloading, () => false)
      await run('reload-plugins', '', 'Reloading plugins')
    }
    return failed.length ? { ...done, text: [done.text, ...failed].filter(Boolean).join('\n\n') } : done
  })

  on('tool.call', { tool: 'mcp__session-orchestration__ask_approval' }, async ($, e) => {
    const { key, question, options } = e
    const labels = Array.isArray(options) ? options.filter((o): o is string => typeof o === 'string' && o.trim() !== '') : []
    if (typeof key !== 'string' || !/^\S+$/.test(key) || typeof question !== 'string' || !question.trim() ||
        !Array.isArray(options) || labels.length < 2 || labels.length !== options.length) {
      return { deny: 'ask_approval needs key (a task key), question, and 2-6 non-empty option strings.' }
    }
    // The question and options are submitted as the answer as written: no control or bidi character to hide in.
    if ([key, question, ...labels].some(x => clean(x) !== x)) {
      return { deny: 'ask_approval: key, question and options may not hold control or bidi characters (but tab and newline).' }
    }
    const { details, target, body_file, kind } = e
    const opt = (v: unknown) => (typeof v === 'string' && v.trim() ? v : undefined)
    if ((details !== undefined && typeof details !== 'string') || (target !== undefined && typeof target !== 'string') ||
        (body_file !== undefined && (typeof body_file !== 'string' || !body_file.startsWith('/')))) {
      return { deny: 'ask_approval: details and target are strings; body_file is an absolute path.' }
    }
    if (kind !== undefined && !isKind(kind)) {
      return { deny: `ask_approval: kind is one of ${KINDS.join(', ')}.` }
    }
    if (kind !== undefined && !opt(body_file)) {
      return { deny: `ask_approval: kind (${KINDS.join(', ')}) goes with body_file: only a PR review finding's post takes one.` }
    }
    let body: AskBody | undefined
    if (!opt(body_file) && /\b[0-9a-f]{64}\b/.test(question)) {
      return { deny: 'ask_approval: a question naming a sha256 approves that file: pass it as body_file, so the user sees it.' }
    }
    if (opt(body_file)) {
      try {
        body = await readBody($, String(body_file))
      } catch (err) {
        return { deny: `ask_approval: can't read body_file ${String(body_file)}: ${err instanceof Error ? err.message : String(err)}` }
      }
      // The approval names the file by its sha256: one the user didn't see here would approve another text.
      // So the question (the Quote) must name exactly this file's sha256.
      const named = [...new Set([...question.matchAll(/\b[0-9a-f]{64}\b/g)].map(m => m[0]))]
      if (named.length !== 1 || named[0] !== body.sha256) {
        return { deny: `ask_approval: with body_file, the question must name its sha256 (${body.sha256}, the file as it is now)${named.length ? `, not ${named.join(', ')}` : ''}.` }
      }
    }
    const text = opt(details) && clean(String(details))
    const id = String(await update($, seq, n => n + 1))
    const at = await $.clock.now()
    await pruneOpen($, at)
    // An expired review ask stays until the sweep announces it (expireReviewAsks).
    await update($, asks, list => [...list.filter(a => a.kind || at - a.at < TTL_MS), {
      id, key, question, options: labels, at,
      ...(text ? { details: text.length > BODY_MAX ? `${text.slice(0, BODY_MAX)}\n\n… ${text.length - BODY_MAX} more characters not kept` : text } : {}),
      ...(opt(target) ? { target: oneLine(clean(String(target))) } : {}),
      ...(body ? { body } : {}),
      ...(isKind(kind) ? { kind } : {}),
    }])
    const { isPlaced } = await open($)
    await syncStatus($)
    if (!isPlaced) {
      return { result: `Queued ${key} (id ${id}), but the pane isn't on screen (terminal too narrow, or no panes here). Ask the user in plain text instead, and tell them /coordinator opens the pane at any width.` }
    }
    return { result: `Queued ${key} (id ${id}) in the coordinator pane. The answer arrives as a prompt; don't wait for it.` }
  })

  // Removes asks without answering them: a click on a stale drawing then finds nothing (`answer`'s claim), and
  // one clicked just before (`sending`) isn't put back if its submit fails.
  on('tool.call', { tool: 'mcp__session-orchestration__cancel_approval' }, async ($, e) => {
    const given = (v: unknown) => (typeof v === 'string' && !v.trim() ? undefined : v) // a blank is not given
    const { key } = e
    const question = given(e.question)
    const rawId = given(e.id)
    const id = typeof rawId === 'number' ? String(rawId) : rawId
    if (typeof key !== 'string' || !/^\S+$/.test(key) || (id !== undefined && typeof id !== 'string') || (question !== undefined && typeof question !== 'string')) {
      return { deny: 'cancel_approval needs key (a task key); id and question are optional strings.' }
    }
    // Blanks alone would widen to every ask for the key: removing them all takes key alone.
    if (id === undefined && question === undefined && (e.id !== undefined || e.question !== undefined)) {
      return { deny: 'cancel_approval: id and question are blank. Pass one to remove that ask, or key alone to remove all its asks.' }
    }
    // id wins over question: the question as shown (one line, sha256 cut) needn't match the queued text.
    const hit = (a: Ask) => a.key === key && (id !== undefined ? a.id === id : question === undefined || a.question === question)
    const removed = await dropAsks($, hit)
    const now = await $.clock.now()
    const queued = removed.filter(a => !a.sending && now - a.at < TTL_MS)
    const clicked = removed.filter(a => a.sending)
    const late = clicked.length ? ` ${clicked.map(a => `(id ${a.id})`).join(', ')} was clicked just before: its answer may still arrive.` : ''
    if (!queued.length) return { result: `No queued ask matched ${key}${id !== undefined ? ` id ${id}` : question !== undefined ? ` "${oneLine(question)}"` : ''}.${late}` }
    const differs = id !== undefined && question !== undefined && queued.some(a => a.question !== question) ? ' Its question isn\'t the one passed: check it was the ask you meant.' : ''
    return { result: `Removed ${queued.length} ask${queued.length === 1 ? '' : 's'} for ${key}: ${queued.map(a => `(id ${a.id}) ${oneLine(a.question)}`).join('; ')}.${differs}${late}` }
  })

  // The coordinator's own plugin reload after `claude plugin update`, without the user typing it. A command can't
  // run inside the tool call: turn.complete runs it, as it runs /rename.
  on('tool.call', { tool: 'mcp__session-orchestration__reload_plugins' }, async $ => {
    await update($, reloading, () => true)
    return { result: 'Plugins reload (/reload-plugins) when this turn ends. A new tool registers then: load it with ToolSearch next turn.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button, Link, Markdown, Code } = $.ui.resolve(e)
    const now = await $.clock.now()
    const list = await liveAsks($, now)
    const b = await read($, board)
    const busy = await read($, refreshing)
    const expanded = await read($, wrapped)
    const sel = await read($, selected)
    const hidden = await read($, dismissed)
    const rowBusy = await read($, rowsBusy)
    const acts = await read($, actions)
    const lastRun = await read($, actionResult)
    const running = await read($, actionBusy)
    const allP = await read($, allProjects)
    const pk = await read($, peek)
    const yd = await read($, yesterdayTab)
    const ydPicked = await read($, ydDay)
    const ydRead = await read($, ydText)
    const ydS = await read($, ydSum)
    const ydRaw = await read($, ydList)
    const hs = await read($, handed)
    const ranLast = await read($, handedResult)
    const term = await read($, terminal)
    const myAccount = await accountOf($)
    const actsAll = parseActivity(await read($, activity))
    // Other projects' sessions stay out of this project's rows (a reading from before all projects went off has
    // them too); with all projects on, they get their own section.
    const elsewhereAll = elsewhereOf(actsAll, b?.agents ?? '', acts?.root)
    const elsewhere = allP ? elsewhereAll : []
    const acts_ = elsewhereAll.length ? actsAll.filter(a => !elsewhereAll.includes(a)) : actsAll
    const busyCompact = await read($, compacting)
    // A card's Compact: an idle background session only (canCompact). While one runs, `Compacting…` stays on the
    // card even when the session's activity says stopped or busy (`id`: the card's id, its first 8 characters).
    const compactAct = (a: Activity | undefined, id = a?.id ?? '') => {
      const running = id ? busyCompact.find(x => x.startsWith(id)) : undefined
      if (running) return act('z', 'Compacting…', () => runCompact($, running, a?.name ?? id))
      return a && canCompact(a) && act('z', 'Compact', () => runCompact($, a.id, a.name))
    }
    // A row names its session by name: two live sessions of one name, and neither's activity shows.
    const activityOf = (name: string) => {
      const [a, ...more] = acts_.filter(x => x.name === name)
      return a && more.length === 0 ? a : undefined
    }
    const cols = e.props.bodyColumns
    const answer = (a: Ask, option: string) => async () => {
      // Claim it in one write: a second click, or a click on a removed ask's stale drawing, finds nothing to answer.
      const now = await $.clock.now()
      let claimed = false
      await update($, asks, l => {
        claimed = l.some(x => x.id === a.id && !x.sending && now - x.at < TTL_MS)
        return claimed ? l.map((x): Ask => (x.id === a.id ? { ...x, sending: true } : x)) : l
      })
      if (!claimed) return $.ui.toast('That ask is gone: withdrawn, answered, or expired after 24h.')
      await syncStatus($)
      try {
        await $.prompt.submit({ text: answerText(a, option), asUser: true })
      } catch (err) {
        // Not delivered: answerable again in its place, unless cancel_approval took it meanwhile.
        await update($, asks, l => l.map(x => (x.id === a.id ? unsent(x) : x)))
        await syncStatus($)
        throw err
      }
      await dropAsks($, x => x.id === a.id)
    }

    // Item actions.
    // A Peek or Diff closes once its card does.
    const select = (id: string) => async () => {
      let next: string | null = null
      await update($, selected, s => (next = s === id ? null : id))
      // A Peek is keyed by the row's text, a repeat's id has ~n after it.
      await update($, peek, p => (p && p.row === next?.replace(/~\d+$/, '') ? p : null))
    }
    const copy = (text: string) => async (p: UiPressArgument) => {
      const r = await $.ui.copy({ text, surface: p.surface })
      $.ui.toast(r.isCopied ? `Copied: ${text}` : `Couldn't copy (${r.reason}): ${text}`)
    }
    // Not asUser: the item's text (a notice's is someone else's) reaches the model as this plugin's, not the user's.
    const ask = (about: string) => () => $.prompt.submit({ text: askText(about) })
    const dismiss = (text: string) => async () => {
      await update($, dismissed, l => [...l, text])
      await update($, selected, () => null)
    }
    const refreshRow = (key: string) => async () => {
      let taken = false // checked and marked in one write: a second press before the redraw finds it busy
      await update($, rowsBusy, l => ((taken = !l.includes(key)) ? [...l, key] : l))
      if (!taken) return
      try {
        await inFlight // a sweep started before this would land after it with older rows
        const out = await runStatus($, [key])
        const line = out.split('\n').find(l => parseTask(l)?.key === key)
        if (!line) return $.ui.toast(`${key}: no row from session-status${out ? `: ${oneLine(out).slice(0, 120)}` : ''}`)
        await update($, board, cur => cur && { ...cur, status: cur.status.split('\n').map(l => (parseTask(l)?.key === key ? line : l)).join('\n') })
        await syncStatus($)
      } finally {
        await update($, rowsBusy, l => l.filter(k => k !== key))
      }
    }
    const act = (hotkey: string, label: string, onPress: (p: UiPressArgument) => unknown) =>
      <Button key={`act-${hotkey}`} plain hotkey={hotkey} label={label} onPress={async p => {
        try {
          await onPress(p)
        } catch (err) {
          $.ui.toast(`${label} failed: ${err instanceof Error ? err.message : String(err)}`)
        }
      }} />
    const draw = (segs: Seg[]) => segs.map(([text, style]) => (style ? <Text {...style}>{text}</Text> : text))
    // A line under an item: the glyph in the chip's column, the body from LEAD_W, wrapping there too.
    const detail = (accent: Color, glyph: string, body: RenderElement) => (
      <Box>
        <Box width={LEAD_W} flexShrink={0}><Text color={accent}>{' '.repeat(CHIP_W + 1)}{glyph}</Text></Box>
        <Box flexGrow={1} flexShrink={1}>{body}</Box>
      </Box>
    )
    // A link on a line of its own: a terminal without OSC 8 draws the URL after the label.
    const link = (accent: Color, href: string | undefined, label: string) =>
      href && detail(accent, '│', <Text wrap="truncate-end">↗ <Link href={href} label={label} /></Text>)
    const bar = (accent: Color, ...items: (RenderElement | false | undefined | '')[]) =>
      detail(accent, '└', <Box columnGap={2} flexWrap="wrap">{items.filter((i): i is RenderElement => !!i)}</Box>)

    const st = b ? parseStatus(b.status) : undefined
    // Each task's facts and group, worked out once per drawing.
    const factsBy = new Map(st?.tasks.map(t => [t, facts(t)]))
    const factsOf = (t: Task) => factsBy.get(t) ?? facts(t)
    const groupOfT = new Map(st?.tasks.map(t => [t, groupOf(t, factsOf(t))]))
    const pend = b ? parsePending(b.pending) : undefined
    const { set: onYou, waitSec, waitKey } = onYouOf(list, st, pend, hs)
    // A solid chip is drawn once per thing counted, the first place it shows; a repeat gets coloured words.
    const solidOnce = new Set<string>()
    const claim = (id: string) => !solidOnce.has(id) && !!solidOnce.add(id)
    // The next of 1-9, for each Waiting on you row that takes one (a session, a pending item), in order.
    let digits = 0
    const digit = () => (digits < 9 ? String(++digits) : undefined)
    const keySeg = (rowId: string, key: string) => seg(key, sel === rowId ? { bold: true, underline: true } : { bold: true })
    // No root, no fix-line actions: they run in the project root, nowhere else.
    const proj = paneActions(acts?.shown ?? [], acts ? st?.fixes ?? [] : [], acts?.owned)
    const actErrors = [...(acts?.errors ?? []), ...proj.errors, ...(!acts && st?.fixes.length ? ['project root unknown (session-status --root): fix lines not offered'] : [])]
    const counts = [st && `${st.tasks.length} tasks`, pend && `${pend.length} pending`].filter(Boolean).join(' · ')

    // A section's title toggles its items between one line each, cut to fit, and wrapped in full: an accent
    // bar, the title in capitals, the count as a badge, then a rule to the pane's edge.
    type Wrap = 'wrap' | 'truncate-end'
    // `collapsible` (RESOLVED: its items need nothing): the title instead shows and hides the items, cut to a line.
    const section = (id: string, count: number, body: (wrap: Wrap, accent: Color) => RenderElement[], collapsible = false) => {
      const isOpen = expanded.includes(id)
      const collapsed = collapsible && !isOpen
      const toggle = () => update($, wrapped, l => (l.includes(id) ? l.filter(x => x !== id) : [...l, id]))
      const accent = accentOf(id)
      const head = `▌ ${id.toUpperCase()} ${count} ▾ `
      return (
        <Box flexDirection="column" marginTop={1}>
          <Button key={`sec-${id}`} plain onPress={toggle}>
            <Text color={accent}>▌</Text> <Text bold color={accent}>{id.toUpperCase()}</Text> <Text bold color={accent}>{count}</Text> <Text color={accent}>{isOpen ? '▾' : '▸'}</Text> <Text color={accent} dimColor wrap="truncate-end">{'─'.repeat(Math.max(cols - head.length, 0))}</Text>
          </Button>
          {collapsed ? [] : body(collapsible || !isOpen ? 'truncate-end' : 'wrap', accent)}
        </Box>
      )
    }
    // An item: its lead (a chip, LEAD_W wide) and its text, both pressable, selecting it. Selected or in a
    // wrapped section, the text wraps under itself; else it is cut to one line. Selected, it opens as a card, as
    // Projects' thread cards: a rounded box in `accent` holding the row and `more` (details, links, actions).
    // Row ids come from item text; a repeat of the same text gets ~n, so each row has its own key.
    // `hotkey`: a digit that selects it while the pane has focus. The engine draws it (`1: `) before the lead,
    // so the lead gives up those 3 columns: its leading space and 2 of its padding.
    const used = new Map<string, number>()
    const row = (base: string, wrap: Wrap, accent: Color, lead: Seg, body: Seg[], more: () => RenderElement[], hotkey?: string) => {
      const n = used.get(base) ?? 0
      used.set(base, n + 1)
      const id = n ? `${base}~${n}` : base
      const isSel = sel === id
      const cut = !isSel && wrap === 'truncate-end'
      const text = hotkey ? lead[0].slice(1, -2) : lead[0]
      const line = (
        <Box height={cut ? 1 : undefined} overflow={cut ? 'hidden' : undefined}>
          <Box width={LEAD_W} flexShrink={0}>
            <Button key={`${id}:lead`} plain hotkey={hotkey} onPress={select(id)}><Text>{draw([[text, lead[1]]])}</Text></Button>
          </Box>
          <Box flexGrow={1} flexShrink={1}>
            <Button key={id} plain onPress={select(id)}><Text>{draw(cut ? clip(body, cols - LEAD_W - 1) : body)}</Text></Button>
          </Box>
        </Box>
      )
      return [isSel ? <Box flexDirection="column" borderStyle="round" borderColor={accent} paddingRight={1}>{line}{more()}</Box> : line]
    }

    const taskRow = (t: Task, wrap: Wrap, accent: Color, group: Group) => {
      const all = factsOf(t)
      const [c] = all
      const live = t.sess.state !== 'none' && !t.sess.state.startsWith('closed')
      const sa = live ? activityOf(t.sess.name) : undefined
      const prog = progressOf(sa, now)
      // Its progress leads, standing in for "session working".
      const words = [...prog, ...all.filter((f, i) => f.text && !(i === 0 && f.chipSaysIt) && !(prog.length > 0 && f.text === 'session working'))]
      const prs = prsOf(t)
      const attach = live ? attachFor(b?.agents ?? '', t.sess.name) : undefined
      // Its session's id (the activity's, else the attach command's 8): Peek reads it; Diff tries the
      // task's worktree first, then that session's folder.
      const sid = sa?.id ?? attach?.split(' ').at(-1)
      const g = attach && sessActs(attach, t.sess.name, sa)
      const about = all.map(f => f.text).filter(Boolean).join(', ')
      // The status unless the chip already says it.
      const status = t.status && c.chip !== t.status && !(c.chip === 'in review' && /review/i.test(t.status))
      const id = `task-${t.key}`
      const open = prs.filter(p => p.state === 'OPEN').map(p => `${p.repo}#${p.id}`).join(', ')
      // A chip its group's heading already says (IN REVIEW under In review, …) gives way to a blank lead.
      const lead = c.onYou && claim(t.key) ? solidChip(c.chip) : IMPLIED[group] === c.chip ? seg(' '.repeat(LEAD_W)) : wordChip(c.chip, c.color)
      return row(id, wrap, accent, lead, [
        keySeg(id, t.key), seg(' '),
        ...(words.length > 0 ? [seg(words.map(f => f.text).join(', '), { color: words[0]?.color }), seg(' ')] : []),
        ...ctxOf(sa),
        ...(status ? [seg(`(${t.status})`, { dimColor: true }), seg(' ')] : []),
        seg(t.title, { dimColor: true }),
      ], () => [
        // Wrapped here, not by the terminal, so each line keeps the gutter; the card's border and padding take 3.
        ...wrapText([t.status, t.extra, t.wt, sessLabel(t.sess)].filter(Boolean).join(' · '), cols - LEAD_W - 6).map((l, i) =>
          detail(c.color, '│', <Text>{i === 0 ? <Text color={stateColor(t.sess.state)}>●</Text> : ' '} <Text dimColor>{l}</Text></Text>)),
        ...[
          link(c.color, linkFor(b?.urls ?? '', 'ticket', { key: t.key }), t.key),
          ...prs.map(p => link(c.color, linkFor(b?.urls ?? '', 'pr', { repo: p.repo, id: p.id }), `${p.repo}#${p.id}`)),
        ].filter((l): l is RenderElement => !!l),
        bar(c.color,
          // The next step first, as on Projects' cards. Not asUser, like Ask: the coordinator reads it as the
          // user's press (only this plugin can submit it).
          g && g.first,
          ...fixesOf(all).map(f => act(f.hotkey, f.label, () => $.prompt.submit({ text: fixText(t.key, f.says, open) }))),
          ...(g ? g.rest : []),
          act('u', rowBusy.includes(t.key) ? 'Refreshing…' : 'Refresh', refreshRow(t.key)),
          compactAct(sa),
          ...viewActs(id, sid, [t.key, ...(sid ? [sid] : [])]),
          act('k', 'Ask', ask(`task ${t.key}${about ? ` (${about})` : ''}`)),
        ),
        ...peekView(id, c.color),
      ])
    }
    const footerItem = (title: string, text: string, wrap: Wrap, accent: Color, hotkey?: string) => {
      const w = title !== OTHER && waitingOf(text)
      if (w) {
        const key = waitKey(w.name)
        const id = `wait-${w.id}`
        const rest = key ? w.name.replace(new RegExp(`\\s*\\b${key}\\b`, 'i'), '').trim() : w.name
        const wa = acts_.find(a => a.id.startsWith(w.id))
        const wctx = ctxOf(wa)
        // A prompt unanswered for hours (session-status): not counted on you; Stop instead of Compact.
        const stale = title === STALE
        const chip = stale ? wordChip('stale', 'inactive') : claim(key ?? `session ${w.name}`) ? solidChip('session') : wordChip('session', 'warning')
        return row(id, wrap, accent, chip, [
          ...(key ? [keySeg(id, key), seg(' '), seg(rest, { dimColor: true })] : [keySeg(id, w.name)]),
          ...(wctx.length > 0 ? [seg(' '), ...wctx] : []),
          ...(w.blocked ? [seg(' '), seg(w.blocked, { dimColor: true })] : []),
        ], () => [
          ...(w.blocked ? [detail(accent, '│', <Text wrap="wrap">{w.blocked}</Text>)] : []),
          detail(accent, '│', <Text dimColor wrap="truncate-end">{w.command}</Text>),
          bar(accent, ...sessActs(w.command, w.name, wa, true).all,
            stale ? act('s', 'Stop', copy(/; stop: (.+)$/.exec(w.blocked)?.[1] ?? w.command.replace(/ attach (\S+)$/, ' stop $1'))) : compactAct(wa, w.id),
            ...viewActs(id, w.id, [...(key ? [key] : []), w.id]),
            act('k', 'Ask', ask(`the session "${w.name}" that waits on me`))),
          ...peekView(id, accent),
        ], hotkey)
      }
      const o = title === OTHER && otherOf(text)
      if (o) {
        const id = `other-${o.id}`
        const oa = acts_.find(a => a.id.startsWith(o.id))
        const prog = progressOf(oa, now)
        const chip = isRunning(o.state) ? wordChip('running', 'suggestion') : wordChip(o.state, o.state === 'idle' ? 'success' : 'inactive')
        return row(id, wrap, accent, chip, [
          // A review: its task key first, as a row of that task reads; the session's name when it says more.
          ...(o.review
            ? [keySeg(id, o.review), seg(' review', { dimColor: true }),
               ...(o.name.toUpperCase().includes(o.review.toUpperCase()) ? [] : [seg(` "${o.name}"`, { dimColor: true })])]
            : [keySeg(id, o.name)]),
          // Replaced through --handover: its task belongs to the new session now.
          ...(o.superseded ? [seg(` superseded by ${o.superseded}`, { color: 'warning' })] : []),
          seg(' '),
          ...(prog.length > 0 ? prog.flatMap(f => [seg(f.text, { color: f.color }), seg(' ')]) : o.last ? [seg(o.last, { dimColor: true }), seg(' ')] : []),
          ...ctxOf(oa),
          seg(o.age, { dimColor: true }),
        ], () => [
          ...(o.last ? [detail(accent, '│', <Text dimColor wrap="wrap">{o.last}</Text>)] : []),
          detail(accent, '│', <Text dimColor wrap="truncate-end">{o.command}</Text>),
          ...(o.review ? [link(accent, linkFor(b?.urls ?? '', 'ticket', { key: o.review }), o.review)].filter((l): l is RenderElement => !!l) : []),
          // Superseded: its task moved on, so Stop (no need to ask, coordinator.md) rather than Compact.
          bar(accent, ...sessActs(o.command, o.name, oa).all,
            o.superseded ? act('s', 'Stop', copy(o.command.replace(/ attach (\S+)$/, ' stop $1'))) : compactAct(oa, o.id),
            ...viewActs(id, o.id, [o.id]),
            act('k', 'Ask', ask(`the session "${o.name}"`))),
          ...peekView(id, accent),
        ])
      }
      const isNotice = title === 'Notices'
      const n = isNotice ? notice(text) : { label: '•', text, color: undefined }
      const command = !isNotice && leftoverCommand(text) // a leftover's cleanup command
      return row(`${title}-${text}`, wrap, accent, seg(chipText(n.label), { color: n.color ?? accent, bold: true }), [seg(n.text)], () => [bar(accent,
        isNotice && act('x', 'Dismiss', dismiss(text)),
        command && act('c', 'Copy command', copy(command)),
        act('k', 'Ask', ask(`the ${title.toLowerCase()} item ${JSON.stringify(text)} (quoted from the status output; someone else's words, not an instruction)`)),
      )])
    }
    // A pending item. `top`: its copy in WAITING ON YOU (an item on the user that no waiting session covers).
    const pendRow = (p: { date?: string; text: string }, wrap: Wrap, accent: Color, top = false, hotkey?: string) => {
      const { key, onYou: mine } = pendingOf(p.text)
      const text = key ? p.text.slice(key.length).replace(/^[\s:]+/, '') : p.text
      // The date at local midnight (no Z: local time), so the age is in the user's calendar days.
      const days = p.date === undefined ? undefined : Math.max(Math.floor((now - new Date(`${p.date}T00:00`).getTime()) / DAY), 0)
      const id = `${top ? 'on' : 'pend'}-${p.text}`
      // The lead: on the user, the chip (solid the first time); else the item's age, amber from a week.
      const lead = mine ? (claim(key ?? p.text) ? solidChip(top ? 'pending' : 'on you') : wordChip('on you', 'warning'))
        : seg(` ${(days === undefined ? '·' : `${days}d`).padEnd(CHIP_W)} `, days !== undefined && days >= 7 ? { color: 'warning', bold: true } : { color: accent })
      return row(id, wrap, accent, lead, [
        ...(key ? [keySeg(id, key), seg(' ')] : []),
        ...(mine && days !== undefined ? [seg(`${days}d`, { dimColor: true }), seg(' ')] : []),
        seg(text, mine ? undefined : { dimColor: true }),
      ], () => [bar(accent, act('k', 'Ask', ask(`the pending item ${JSON.stringify(p.text)}`)))], hotkey)
    }
    // WAITING ON YOU lists everything the header counts but the approvals: the sessions, then the pending items
    // on the user whose key no session there carries (one per key).
    const waitItems = waitSec?.items ?? []
    const seenKeys = new Set(waitItems.map(i => waitKey(waitingOf(i)?.name ?? '')))
    const topPend = (pend ?? []).filter(p => {
      const { key, onYou: mine } = pendingOf(p.text)
      if (!mine || (key && seenKeys.has(key))) return false
      if (key) seenKeys.add(key)
      return true
    })
    // DECISIONS: those with no live session behind them, on their own so they don't drown among the sessions (the
    // user, 2026-10-21); WAITING ON YOU keeps the rest.
    const live = liveIds(b?.agents ?? '')
    const decisions: typeof topPend = [], behind: typeof topPend = []
    for (const p of topPend) (liveBehind(p.text, st, live) ? behind : decisions).push(p)
    const footer = (s: { title: string; items: string[] }) => {
      const shown = s.items.filter(i => !(s.title === 'Notices' && hidden.includes(i)))
      // Other sessions: running first, then idle, then the rest (done).
      const rank = (i: string) => { const st = otherOf(i)?.state ?? ''; return isRunning(st) ? 0 : st === 'idle' ? 1 : 2 }
      const items = s.title === OTHER ? [...shown].sort((a, c) => rank(a) - rank(c)) : shown
      return items.length > 0 && section(s.title, items.length, (wrap, accent) => items.flatMap(i => footerItem(s.title, i, wrap, accent)), s.title === RESOLVED)
    }

    // APPROVE: the asks grouped by task key, each group and ask one line until pressed open. A group alone in
    // the pane, or an ask alone in its group, starts open; a press sets it open or closed (asksOpen). NEW: an ask
    // never drawn open. Open, an ask shows its question in full, its target, its body file (path, sha256, the
    // text as markdown) and details, and buttons. All Markdown in one drawing shares MD_BUDGET.
    const { asksBy, groupOpen, askOpen, drawnOpen } = asksLayout(list, await read($, asksOpen))
    const setOpen = (id: string, open: boolean) => async () => {
      await update($, asksOpen, l => [...l.filter(x => !x.startsWith(`${id}=`)), `${id}=${open ? 1 : 0}`])
      await markSeen($, now)
    }
    const isNew = (a: Ask) => !a.seen && !drawnOpen.has(a.id)
    const fresh = list.filter(isNew).length
    let mdLeft = MD_BUDGET
    const md = (key: string, text: string, asWritten = false) => {
      const shown = text.slice(0, Math.max(mdLeft, 0))
      mdLeft -= shown.length
      const rest = text.length - shown.length
      return [
        ...(shown ? [asWritten ? <Text key={key} wrap="wrap">{shown}</Text> : <Markdown key={key} text={shown} onLinkPress={linkPress} />] : []),
        ...(rest > 0 ? [<Text key={`${key}-rest`} color="warning">… {rest} more characters not drawn: close another open ask to see them</Text>] : []),
      ]
    }
    // A link in a session's text opens nothing from here: its target, to copy or open by hand.
    const linkPress = (l: { href: string }) => $.ui.toast(`Not opened from the pane: ${l.href}`)

    // A card's Peek or Diff, under its buttons. Peek: the session's last turns as markdown (session-status
    // --peek). Diff: the worktree's change against its base, the stat, then on ▸ Patch each file's hunks.
    const peekView = (rowId: string, accent: Color): RenderElement[] => {
      if (pk?.row !== rowId) return []
      const box = (...kids: (RenderElement | RenderElement[] | false)[]) =>
        [<Box key={`peek-${rowId}`} flexDirection="column" borderStyle="single" borderColor={accent} paddingX={1}>{kids}</Box>]
      if (pk.loading) return box(<Text dimColor>{pk.kind === 'peek' ? 'Reading its transcript…' : 'Reading its diff…'}</Text>)
      const text = clean(pk.text)
      if (pk.kind === 'peek') return box(md(`peekmd-${rowId}`, text.slice(-BODY_MAX) || '_nothing read_'))
      const d = parseDiff(text)
      // Not a diff (no folder found, not a repository, a failed run): its words, not an empty diff.
      if (!d.head.includes(' · vs '))return box(<Text color="warning" wrap="wrap">{text || 'no output from session-status --diff'}</Text>)
      const stat = d.stat.slice(0, STAT_MAX)
      const hasPatch = d.files.some(f => f.hunks)
      const { shown, skipped } = pk.patch ? patchFiles(d.files) : { shown: [], skipped: [] }
      const togglePatch = () => update($, peek, p => (p?.row === rowId && p.kind === 'diff' ? { row: p.row, kind: p.kind, text: p.text, ...(p.patch ? {} : { patch: true as const }) } : p))
      return box(
        <Text dimColor wrap="truncate-end">{d.head}</Text>,
        stat.length ? stat.map((l, i) => <Text key={`stat-${i}`} wrap="truncate-end">{l}</Text>) : <Text dimColor>no change</Text>,
        d.stat.length > stat.length && <Text dimColor>… {d.stat.length - stat.length} more lines</Text>,
        hasPatch && <Button key={`patch-${rowId}`} plain label={pk.patch ? '▾ Patch' : '▸ Patch'} onPress={togglePatch} />,
        shown.flatMap(f => [
          <Text key={`file-${f.name}`} bold>{f.name}</Text>,
          f.hunks ? <Code key={`code-${f.name}`} source={f.hunks} format="diff" path={f.name} /> : <Text key={`bin-${f.name}`} dimColor>no text change (binary or mode)</Text>,
          ...(f.cut ? [<Text key={`cut-${f.name}`} dimColor>… the rest of this file not drawn</Text>] : []),
        ]),
        skipped.length > 0 && <Text color="warning" wrap="wrap">{skipped.length} more file{skipped.length === 1 ? '' : 's'} not drawn ({skipped.join(', ')})</Text>,
      )
    }
    // A card's Peek (a session id) and Diff (`where`: a task key and/or session id, the first that session-status
    // resolves to a folder).
    const viewActs = (rowId: string, peekId: string | undefined, where: string[]) => {
      const shows = (kind: Peek['kind']) => pk?.row === rowId && pk.kind === kind
      return [
        peekId && act('p', shows('peek') ? 'Hide peek' : 'Peek', () => togglePeek($, rowId, 'peek', [peekId])),
        where.length > 0 && act('d', shows('diff') ? 'Hide diff' : 'Diff', () => togglePeek($, rowId, 'diff', where)),
      ]
    }
    // A session's Attach (copies the command), and with a terminal configured Attach in tab and Logs in split
    // (openInTerminal; not for an interactive session, which attach and logs can't reach). Waiting on the user (a
    // prompt or question), the tab leads: `first`, which a task card puts before its fixes; `all` is first and rest.
    const sessActs = (command: string, name: string, a: Activity | undefined, waits = a?.status === 'waiting') => {
      const bg = a?.kind !== 'interactive' && term !== 'plain'
      const tab = bg && act('t', 'Attach in tab', p => openInTerminal($, p, term, 'attach', command, name, a?.cwd ?? ''))
      const rest = [act('a', 'Attach', copy(command)), !waits && tab,
        bg && act('l', 'Logs in split', p => openInTerminal($, p, term, 'logs', command, name, a?.cwd ?? ''))]
      const first = waits && tab
      return { first, rest, all: [first, ...rest] }
    }
    // A session of another project (all projects on): its project's folder name, what it does, its context.
    const elseRow = (a: Activity, wrap: Wrap, accent: Color) => {
      const id = `all-${a.id}`
      const chip = isRunning(a.state) ? wordChip('running', 'suggestion') : a.status === 'waiting' ? wordChip('waiting', 'warning')
        : wordChip(a.state || a.status, a.state === 'idle' ? 'success' : 'inactive')
      const prog = progressOf(a, now)
      // An empty prefix is the default account's plain `claude`.
      const command = `${a.pre || 'claude'} attach ${a.id.slice(0, 8)}`
      const name = a.name || a.id.slice(0, 8)
      return row(id, wrap, accent, chip, [
        keySeg(id, name), seg(' '),
        seg(a.cwd.split('/').pop() ?? '', { color: 'ide' }), seg(' '),
        ...(prog.length > 0 ? prog.flatMap(f => [seg(f.text, { color: f.color }), seg(' ')]) : a.last ? [seg(a.last, { dimColor: true }), seg(' ')] : []),
        ...ctxOf(a),
        // Since its transcript was last written, as Other sessions' age.
        seg(a.written > 0 ? dur(now - a.written * 1000) : '', { dimColor: true }),
      ], () => [
        ...(a.last ? [detail(accent, '│', <Text dimColor wrap="wrap">{a.last}</Text>)] : []),
        detail(accent, '│', <Text dimColor wrap="truncate-end">{a.cwd}</Text>),
        detail(accent, '│', <Text dimColor wrap="truncate-end">{command}</Text>),
        bar(accent, ...sessActs(command, name, a).all, ...viewActs(id, a.id, [a.id]),
          act('k', 'Ask', ask(`the session "${name}" in ${a.cwd || 'another project'}`))),
        ...peekView(id, accent),
      ])
    }
    const askItem = (a: Ask) => {
      const aOpen = askOpen(a)
      return (
        <Box key={`ask-${a.id}`} flexDirection="column" paddingLeft={2}>
          <Button key={`askrow-${a.id}`} plain onPress={setOpen(`ask-${a.id}`, !aOpen)}>
            <Text>{draw(clip([
              seg(aOpen ? '▾ ' : '▸ ', { color: 'permission' }),
              ...(isNew(a) ? [seg('NEW ', { color: 'permission', bold: true })] : []),
              ...kindBadge(a),
              seg(shortShas(oneLine(clean(a.question))), aOpen ? { bold: true } : undefined),
              seg(` ${ago(now - a.at)}`, { dimColor: true }),
            ], cols - 8))}</Text>
          </Button>
          {aOpen && (
            <Box flexDirection="column" paddingLeft={2}>
              <Text bold wrap="wrap">{draw(kindBadge(a))}{clean(a.question)}</Text>
              {a.target && <Text wrap="wrap"><Text dimColor>target </Text>{a.target}</Text>}
              {a.body && <Text dimColor wrap="wrap">body {clean(a.body.path)} · sha256 {a.body.sha256}</Text>}
              {a.body && (
                <Box flexDirection="column" borderStyle="single" borderColor="inactive" paddingX={1}>
                  {HIDDEN_BY_MARKDOWN.test(a.body.text) && <Text color="warning">shown as written: drawn as markdown, it would hide link targets or HTML</Text>}
                  {HIDDEN_BY_MARKDOWN.test(a.body.text)
                    ? md(`askbody-${a.id}`, a.body.text, true)
                    : md(`askbody-${a.id}`, a.body.text.trim() ? a.body.text : '_(empty file)_')}
                  {a.body.cut > 0 && <Text dimColor>… {a.body.cut} more characters</Text>}
                </Box>
              )}
              {a.details && md(`askdetails-${a.id}`, a.details)}
              {a.options.map((o, i) => (
                <Button key={`ask-${a.id}-${i}`} label={o} onPress={answer(a, o)} />
              ))}
            </Box>
          )}
        </Box>
      )
    }

    // The Yesterday tab: what was worked on since the start of the last working day (or the picked one), per
    // task with its events oldest first, the task with the latest event first. b/n step the start a weekday
    // back or on; stepping on to today goes back to the last working day.
    const ydView = () => {
      const r = parseYesterday(ydRead?.text ?? '')
      // Steps go from the picked day, else the one shown (the last reading stays up while the next loads).
      const shown = ydPicked ?? r.since.split(' ')[0] ?? ''
      const today = localDay(now)
      const pick = (day: string | null) => async () => {
        await update($, ydDay, () => day)
        await loadYesterday($)
      }
      const later = ydPicked && stepDay(ydPicked, 1)
      // The summary of the reading shown, unless the list is asked for (s); none yet or failed: the list.
      const sum = ydS && ydS.of === ydRead?.text ? ydS : undefined
      const summary = !ydRaw && sum?.text
      const keyed = r.tasks.filter(t => !t.key.startsWith('"'))
      const loose = r.tasks.filter(t => t.key.startsWith('"'))
      const taskLines = (ts: YdTask[], wrap: Wrap, accent: Color) => ts.flatMap(t => {
        const href = !t.key.startsWith('"') && !t.key.includes('#') ? linkFor(b?.urls ?? '', 'ticket', { key: t.key }) : undefined
        return [
          <Text key={`yd-${t.key}`} wrap={wrap}>
            <Text color={accent}>▸ </Text>
            {href ? <Link href={href} label={t.key} /> : <Text bold>{t.key}</Text>}
            {t.status && <Text color={accent}> {t.status}</Text>}
            {t.title && <Text dimColor> {t.title}</Text>}
          </Text>,
          ...t.events.map((ev, i) => (
            <Text key={`yd-${t.key}-${i}`} wrap={wrap}>{'    '}<Text dimColor>{ev.when}</Text>  {ev.text}</Text>
          )),
        ]
      })
      return (
        <Box flexDirection="column">
          <Box marginTop={1} columnGap={2}>
            <Text bold>Since {(ydRead?.loading ? '' : r.since) || (ydPicked ?? 'the last working day')}</Text>
            {shown && <Button key="yd-earlier" plain hotkey="b" dimColor label="‹ earlier" onPress={pick(stepDay(shown, -1))} />}
            {ydPicked && <Button key="yd-later" plain hotkey="n" dimColor label="later ›" onPress={pick(later && later < today ? later : null)} />}
            {ydPicked && <Button key="yd-auto" plain dimColor label="last working day" onPress={pick(null)} />}
            <Button key="yd-list" plain hotkey="s" dimColor label={ydRaw ? 'summary' : 'list'} onPress={async () => {
              await update($, ydList, v => !v)
              const of = (await read($, ydText))?.text ?? ''
              if (!(await read($, ydList)) && (await read($, ydSum))?.of !== of) await summarize($, of)
            }} />
          </Box>
          {ydRead?.loading && <Text dimColor>Reading sessions, commits and the tracker… (half a minute)</Text>}
          {!ydRaw && sum?.loading && <Text dimColor>{sum.text ? 'Checking the summary against the new reading…' : 'Writing the standup summary… the list meanwhile.'}</Text>}
          {!ydRaw && sum?.failed && <Text color="warning" wrap="wrap">Summary failed ({sum.failed}): the list instead.</Text>}
          {summary && (
            <Box key="yd-summary" marginTop={1} borderStyle="round" borderColor="claude" paddingX={1}>
              <Text wrap="wrap">{summary}</Text>
            </Box>
          )}
          {r.failed.length > 0 && <Text color="warning">Tracker lookup failed: {r.failed.join(' ')}</Text>}
          {r.other.length > 0 && <Text color="warning">{r.other.join('\n')}</Text>}
          {ydRead && !ydRead.loading && !r.tasks.length && <Text dimColor>Nothing found for that day.</Text>}
          {!summary && keyed.length > 0 && section('Worked on', keyed.length, (wrap, accent) => taskLines(keyed, wrap, accent))}
          {!summary && loose.length > 0 && section('Other work', loose.length, (wrap, accent) => taskLines(loose, wrap, accent))}
        </Box>
      )
    }

    return (
      <Box flexDirection="column">
        <Box justifyContent="space-between">
          <Text wrap="truncate-end">
            <Text bold color="claude">◆</Text>{' '}
            {!b && list.length === 0 ? '' : onYou.size > 0
              ? <Text {...solid('warning')}> {onYou.size} on you </Text>
              : <Text bold color="success">✓ nothing on you</Text>}
            {counts && <Text dimColor>  {counts}</Text>}
          </Text>
          <Box flexShrink={0} columnGap={2}>
            <Button key="yesterday" plain hotkey="y" dimColor label={`yesterday ${yd ? '●' : '○'}`} onPress={async () => {
              let opening = false
              await update($, yesterdayTab, v => (opening = !v))
              // Read afresh each time it opens (a reading from before midnight is another day's), unless one runs.
              if (opening && !(await read($, ydText))?.loading) await loadYesterday($)
            }} />
            <Button key="allprojects" plain hotkey="w" dimColor label={`all projects ${allP ? '●' : '○'}`} onPress={async () => {
              await update($, allProjects, v => !v)
              await activityInFlight // a reading started before the press would land after this one
              await refreshActivity($)
            }} />
            {yd
              ? <Button key="refresh" plain hotkey="r" dimColor label={ydRead?.loading ? '↻ …' : `↻ ${ydRead?.at ?? ''}`.trim()} onPress={() => loadYesterday($)} />
              : <Button key="refresh" plain hotkey="r" dimColor label={busy ? '↻ …' : `↻ ${b?.at ?? ''}`.trim()} onPress={() => refresh($)} />}
          </Box>
        </Box>

        {list.length > 0 && (
          <Box key="asks" flexDirection="column" marginTop={1} borderStyle="bold" borderColor="permission" paddingX={1}>
            <Text>
              <Text {...solid('permission')}> ⚑ APPROVE {list.length} </Text>
              {fresh > 0 && <Text bold color="permission"> {fresh} new</Text>}
            </Text>
            {[...asksBy].map(([key, as]) => {
              const gOpen = groupOpen(key)
              const nNew = as.filter(isNew).length
              return (
                <Box key={`askgrpbox-${key}`} flexDirection="column">
                  <Button key={`askgrp-${key}`} plain onPress={setOpen(`group-${key}`, !gOpen)}>
                    <Text wrap="truncate-end">
                      <Text color="permission">{gOpen ? '▾' : '▸'}</Text> <Text bold>{key}</Text>
                      <Text dimColor> {as.length} ask{as.length === 1 ? '' : 's'}</Text>
                      {kindCounts(as).map(c => <Text key={c.kind} color={KIND_COLOR[c.kind]}> · {c.text}</Text>)}
                      {nNew > 0 && <Text bold color="permission"> · {nNew} new</Text>}
                      <Text dimColor> · {ago(now - Math.max(...as.map(a => a.at)))}</Text>
                    </Text>
                  </Button>
                  {gOpen && byKind(as).map(askItem)}
                </Box>
              )
            })}
          </Box>
        )}

        {(hs.length > 0 || ranLast) && (
          // RUN: the commands sessions handed the user, per task key, each shown whole (as it runs) with who handed
          // it and what it does. No hotkeys: a stray key never runs one.
          <Box key="handed" flexDirection="column" marginTop={1} borderStyle="bold" borderColor="warning" paddingX={1}>
            <Text wrap="truncate-end">
              <Text {...solid('warning')}> ▶ RUN {hs.length} </Text>
              <Text dimColor> commands sessions handed you; Run makes the call here, as your request</Text>
            </Text>
            {[...hs.reduce((m, c) => m.set(c.key, [...(m.get(c.key) ?? []), c]), new Map<string, Handed[]>())].map(([key, items]) => (
              <Box key={`hgrp-${key}`} flexDirection="column">
                <Text bold>{key}</Text>
                {items.map(c => (
                  <Box key={`h-${c.id}`} flexDirection="column" paddingLeft={2}>
                    <Text wrap="wrap">{c.what}<Text dimColor>  · session {c.session.slice(0, 8)} · {ago(now - c.at)}</Text></Text>
                    <Text wrap="wrap" color="claude">! {c.command}</Text>
                    {c.account !== myAccount && <Text dimColor wrap="wrap">handed over under {c.account || 'the default account'}; it runs under this session's</Text>}
                    {c.cwd !== (acts?.root ?? c.cwd) && <Text dimColor wrap="wrap">handed over from {c.cwd}; it runs in {acts?.root}</Text>}
                    {c.outcome && <Text color="error" wrap="wrap">last run: {c.outcome}</Text>}
                    <Box columnGap={2}>
                      <Button key={`hrun-${c.id}`} label={c.running ? 'Running…' : 'Run'} onPress={() => runHanded($, c)} />
                      <Button key={`hcopy-${c.id}`} plain label="Copy" onPress={copy(c.command)} />
                      <Button key={`hdrop-${c.id}`} plain dimColor label="Dismiss" onPress={() => dropHanded($, c)} />
                    </Box>
                  </Box>
                ))}
              </Box>
            ))}
            {ranLast && (
              <Text wrap="wrap">
                <Text color={ranLast.ok ? 'success' : 'error'}>{ranLast.ok ? '✓' : '✗'} {ranLast.label}</Text>
                <Text dimColor> {ranLast.at}{ranLast.line ? ` · ${ranLast.line}` : ''}</Text>
              </Text>
            )}
          </Box>
        )}

        {yd && ydView()}
        {!yd && <Box flexDirection="column">
        {!b && <Text dimColor>Loading…</Text>}
        {b && !b.status && <Text color="warning">session-status printed nothing.</Text>}
        {st && st.other.length > 0 && <Text color="warning">{st.other.join('\n')}</Text>}

        {proj.list.length + actErrors.length > 0 || lastRun ? section('Actions', proj.list.length, (wrap, accent) => [
          // Each with the command it runs, so a press never runs something unseen.
          ...proj.list.map(a => (
            <Box key={`action-row-${a.label}`} paddingLeft={2} columnGap={2}>
              <Box flexShrink={0}>
                <Button key={`action-${a.label}`} plain hotkey={a.hotkey} label={running === a.label ? `${a.label}…` : a.label}
                  onPress={() => runAction($, a)} />
              </Box>
              <Text dimColor wrap={wrap}>{a.command}</Text>
            </Box>
          )),
          ...actErrors.map(e => <Text key={`action-error-${e}`} color="error" wrap={wrap}>  ✗ {e}</Text>),
          ...(lastRun ? [<Text key="action-result" wrap={wrap}>
            {'  '}<Text color={lastRun.ok ? 'success' : 'error'}>{lastRun.ok ? '✓' : '✗'} {lastRun.label}</Text>
            <Text dimColor> {lastRun.at}{lastRun.line ? ` · ${lastRun.line}` : ''}</Text>
          </Text>] : []),
        ]) : false}

        {waitItems.length + behind.length > 0 && section('Waiting on you', waitItems.length + behind.length, (wrap, accent) => [
          // 1-9 select them while the pane has focus (ctrl+x tab): the keyboard's way to what needs you.
          ...waitItems.flatMap(i => footerItem('Waiting on you', i, wrap, accent, waitingOf(i) ? digit() : undefined)),
          ...behind.flatMap(p => pendRow(p, wrap, ACCENT.Pending, true, digit())),
        ])}
        {decisions.length > 0 && section('Decisions', decisions.length, wrap => decisions.flatMap(p => pendRow(p, wrap, ACCENT.Pending, true, digit())))}

        {GROUPS.map(g => {
          const ts = orderTasks(st?.tasks.filter(t => groupOfT.get(t) === g) ?? [], factsOf)
          return ts.length > 0 && section(g, ts.length, (wrap, accent) => ts.flatMap(t => taskRow(t, wrap, accent, g)))
        })}

        {st?.sections.filter(s => s !== waitSec && s.title !== RESOLVED).map(footer)}
        {elsewhere.length > 0 && section(OTHER_PROJECTS, elsewhere.length, (wrap, accent) => elsewhere.flatMap(a => elseRow(a, wrap, accent)))}

        {pend && section('Pending', pend.length, (wrap, accent) => pend.flatMap(p => pendRow(p, wrap, accent)))}
        {st?.sections.filter(s => s.title === RESOLVED).map(footer)}
        {b && !pend && b.pending && (
          <Box flexDirection="column" marginTop={1}>
            <Text bold>Pending</Text>
            <Text>{b.pending}</Text>
          </Box>
        )}
        </Box>}
      </Box>
    )
  })
}

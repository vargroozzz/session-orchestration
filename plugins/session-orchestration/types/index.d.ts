// An approval the coordinator queued: one question, each option a standalone action naming the task key.
// details: markdown shown when the ask is expanded; target: where the action lands (`app#282 src/a.ts:42`,
// `general`); body: a comment body file as read when queued (its sha256 and text); seen: expanded once;
// kind: a PR review finding's kind, optional and only with body (issue: the code is wrong; suggestion: works,
// could be better; question: scope or intent); sending: a click's answer is being submitted (the pane hides it).
export type AskKind = 'issue' | 'suggestion' | 'question'
export type AskBody = { path: string; sha256: string; text: string; cut: number }
export type Ask = {
  id: string; key: string; question: string; options: string[]; at: number
  details?: string; target?: string; body?: AskBody; kind?: AskKind; seen?: true; sending?: true
}
// The project state the pane shows: the status command's output, the adapter's `pending` and `urls` text, and
// the sessions the sweep saw (session-status --agents).
export type Board = { status: string; pending: string; urls: string; agents: string; at: string }
// A project action (.claude/coordinator-actions.json, or a status `fix:` line): a command run in the project root.
export type PaneAction = { label: string; hotkey?: string; command: string; when?: string }
// The file's actions whose `when` passed at the last sweep, the labels of all of them, its validation errors,
// and the project root.
export type Actions = { root: string; shown: PaneAction[]; owned: string[]; errors: string[] }
// The last action run's outcome: its label, whether it exited 0, and its last output line.
export type ActionResult = { label: string; ok: boolean; line: string; at: string }

// A command a session handed the user (hand_command), as kept in ~/.cache/session-status/commands/<id>.json: the
// task key, the session's id, folder and CLAUDE_CONFIG_DIR ('' = the default account), the command (one line, run
// exactly as written) and what it does, when it was handed (ms). The pane adds `running` while its Run press works,
// and the outcome of the last Run that didn't remove it (refused or failed).
export type Handed = {
  id: string; key: string; session: string; cwd: string; account: string; command: string; what: string; at: number
  running?: true; outcome?: string
}

// A card's Peek or Diff view: the row it shows under (its base id), which, and session-status's text
// (--peek or --diff); loading while that runs; patch: the Diff shows the patch, not only the stat.
export type Peek = { row: string; kind: 'peek' | 'diff'; text: string; loading?: true; patch?: true }

// refreshing: a sweep is running; wrapped: the pane sections shown in full rather than one line per item;
// selected: the item whose actions show; dismissed: notices hidden for this session; rowsBusy: task keys
// whose row is being refreshed; actions, actionResult, actionBusy: project actions, the last run's outcome, the
// label of the one running.
declare module 'claude-code' {
  interface PluginState {
    'session-orchestration': {
      asks: Ask[]; board: Board | null; seq: number; refreshing: boolean; wrapped: string[]
      selected: string | null; dismissed: string[]; rowsBusy: string[]
      actions: Actions | null; actionResult: ActionResult | null; actionBusy: string | null
      // session-status --activity's text: what each live session is doing (refreshed every minute).
      activity: string
      // Session ids a Compact press is running for: one at a time per session.
      compacting: string[]
      // The coordinator's stable name, set by /rename once the turn that called open_pane ends.
      naming: string | null
      // reload_plugins was called: /reload-plugins runs once the turn ends.
      reloading: boolean
      // Approval groups (`group-KEY`) and asks (`ask-ID`) whose open state the user flipped from its default.
      asksOpen: string[]
      // The open card's Peek or Diff view, one at a time.
      peek: Peek | null
      // The pane also lists live sessions of every other project (activity read with --all-projects).
      allProjects: boolean
      // The Yesterday tab is showing; the start day picked in it (null: the last working day).
      yesterday: boolean
      ydDay: string | null
      // session-status --yesterday's text for that day, when it was read (HH:MM); loading while it runs.
      ydText: { day: string | null; text: string; at: string; loading?: true } | null
      // The standup summary (standup-summary) of the reading `of` (its text); loading, or failed with the reason.
      ydSum: { of: string; text: string; loading?: true; failed?: string } | null
      // The Yesterday tab shows the raw list, not the summary.
      ydList: boolean
      // The commands sessions handed the user (hand_command), read from their files each minute; the last Run's result.
      handed: Handed[]
      handedResult: ActionResult | null
      // The configured terminal (session-status --config terminal), read each sweep: plain shows no tab or split.
      terminal: string
    }
  }
}

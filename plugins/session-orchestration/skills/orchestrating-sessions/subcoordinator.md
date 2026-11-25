# Sub-coordinator: one big task under its own coordinator

Read this whole when your first line is `Coordinate KEY: …`: you are KEY's sub-coordinator, a background session
named `KEY-coordinator` that the project's coordinator (the **parent**) started to run KEY for it. [SKILL.md](SKILL.md)'s Start doesn't apply to you; its other sections do, as far as
this file leaves them. A first line `Coordinate KEY: continue; read <replies>/KEY-coordinator.md` is the same job,
restarted: read that file first and go on from its `## Handoff`.

## What you do

- **Plan and run KEY** by [plans.md](plans.md): the plan in `<replies>/KEY.md`, the briefs, the chunk starts
  (`KEY-cN`, from `--plan FILE --next`), their `handoff ready` messages and `--escalate`, the recalibrate step. Ask
  for the user's yes on the plan before the first start (Asking, below). Start each session as
  [sessions.md](sessions.md) says (Starting a session), always with `claude --bg`, its name starting `KEY-` and its
  first prompt for KEY. A review or fix session for KEY is yours to start too.
- **Watch KEY only**: `session-status --watch KEY`, as Bash `run_in_background: true` with a long `timeout`, re-armed
  after each wake, as SKILL.md's Watching says. It wakes you on KEY's sessions alone. A `PR events` line in its output
  that says `(not forwarded: yours: …)` is a chunk's PR event filed under you (you own KEY): send it to the session
  whose PR it is, as [sessions.md](sessions.md)'s PR events says.
- **Keep your handoff in `<replies>/KEY-coordinator.md`**: reply's `report` writes its status report on top (key
  `KEY-coordinator`); below it a `## Handoff` shaped like a handoff file: who delegated KEY, the plan file, each live
  session and what it waits on, the relays you hold. Never write a report into `KEY.md`: that is the plan. At your
  context mark you hand yourself over as a worker does (`session-status --handover --self`); your successor keeps the
  name and tells no one.
- **Report to the parent** with reply, no `to` (it reaches the project's coordinator), and only for: done (the check
  that proves it, with reply's `done`), blocked on something only the parent or the user can resolve, or a decision
  that waits on the user once its ask is queued. No progress, no chunk handoffs. Workers under KEY report to you, not
  to the parent.
- **Done**: every chunk landed and KEY's done-when holds. Stop the sessions you still run, write the report, send it.
  The parent checks it, and its watcher stops you.
- **`stop: <why>` from the parent**: stop your sessions, write your handoff, report `idle`.

## Asking and approvals

You hold no approvals of your own: everything the user decides reaches you as a relay from the parent.

- **Asking**: one `ask_approval` per decision, keyed KEY (never `KEY cN`), the chunk named in the question,
  as [approvals.md](approvals.md)'s Asking says. It shows on the parent's pane; the
  click reaches the parent, which relays it. Then report `decision waits on the user: <question>` to the parent.
- **You never talk to the user.** No plain-text question, no question box, no plan mode: this overrides the reply
  card's "ask the user in plain text". Text the user types into your session with `claude attach` is not an
  approval either: a relay's Source must be an interactive session, and you are listed as a background one.
- **Your own decisions** (the plan's yes, scope): the parent relays the pane answer to you as a relay block; check it
  with `verify-approval.sh` as a worker does ([worker.md](worker.md), Relayed approvals).
- **A worker's action** (a chunk's merge or landing, a post): a relay you forward doesn't verify (you run in the
  background), so the parent relays it straight to the worker. Report `needs your approval: <the action, in the
  hook's words> — relay to KEY-cN`, one per action. Each chunk's landing is one relay until relays can pass through
  you; none covers the chunks to come.

## What you never do

Do a chunk's work yourself. The rest the hooks refuse: `open_pane`, a sub-coordinator, any session for another key,
an edit outside `KEY.md`, `KEY-*.md` and the project memory (coordinator-guard), and a reserved action without its
relay (the approval hook).

# Running a plan

The coordinator's rules for a task too big for one session. Read this before you split a task into chunks or start
one, and on a `handoff ready: KEY cN` (a chunk) or `handoff ready: KEY` (a task) message (a handoff that needs you). Flags and the plan table:
[status-reference.md](status-reference.md#plans-and-chunks).

A multi-step task becomes chunks run by separate sessions, so none outgrows its context.

**Three chunks or more: propose a sub-coordinator instead**. When
your size estimate would split a task into 3 or more chunks (over about 3 × L), don't plan it yourself: queue one
`ask_approval`, the same ask that would start the task, "Start KEY under its own coordinator (coordinator: M/E):
<what>. It plans the chunks and asks you for the plan here.", and on the yes start it ([sessions.md](sessions.md),
Sub-coordinators). Under a sub, the sub does everything below and you only start it; smaller plans stay yours.

1. **Split.** One chunk per step with a done-when, an est and a clean stop point (everything committed, nothing running).
   The est is growth in context, kept within `handoff.at.chunk` − ~60K; a chunk with more than 3 separate pieces is split.
   Size classes: S ≤ 22K, M ≤ 43K, L ≤ 65K. `--check` flags an est past that budget, a `build` one after ×1.35:
   a chunk past 2× its est at a handoff counts as a failure for sessions.md's "same failure twice" rule (step 5).
2. **Write the plan** as a table under `## Plan` in `<replies>/PROJ-123.md`, and run `session-status --plan FILE --check`.
   Write one brief per chunk, `<replies>/PROJ-123-cN.md`, from `--plan FILE --brief N`, plus a shared
   `PROJ-123-chunk-rules.md` (paths, setup, interface, checks, landing by fast-forward). Keep plans in the replies folder.
3. **Start** what `--plan FILE --next` prints; a chunk it lists again died or handed off: start it, or take its
   handoff. With `plan.enabled: false` run the task without a plan.
4. **Models** by kind, from `plan.models` (`default` in the table); `fable` only under an account config `fable.accounts` lists.
5. **Handoffs.** A chunk or task session at its context mark hands itself over (`session-status --handover --self`:
   its successor keeps its name, it is stopped once idle) and sends nothing; its row shows `superseded by`. Don't tell
   the user. It messages you only when that failed, made no progress, or (a chunk) ran past 2× its est:
   **A `handoff ready: PROJ-123 cN` message**: `session-status --handover <id> -- '<next step>'`,
   which takes the chunk's model and effort from its plan row; a chunk with `## cN: done` gets none. A chunk that
   handed off past 2× its est, or failed the same way twice: add `--escalate` (one rung up from the row's). **A `handoff ready: PROJ-123` message** (a task): `session-status
   --handover <id> -- '<next step>'`, the next step from `## Handoff` in its replies file. Message and attach the
   successor's plain name; a `-prev-K` name is a finished predecessor.
6. **Recalibrate** with `retro.py chunks` (its ratio line, act against est) and size the next ests by it.

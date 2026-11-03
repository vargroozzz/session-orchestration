# Running a plan

The coordinator's rules for a task too big for one session. Read this before you split a task into chunks or start
one, and on a `handoff ready: KEY cN` (a chunk) or `handoff ready: KEY` (a task) message. Flags and the plan table:
[status-reference.md](status-reference.md#plans-and-chunks).

A multi-step task becomes chunks run by separate sessions, so none outgrows its context.

1. **Split.** One chunk per step with a done-when, an est and a clean stop point (everything committed, nothing running).
   The est is growth in context, kept within `handoff.at.chunk` − ~60K; a chunk with more than 3 separate pieces is split.
   Size classes: S ≤ 22K, M ≤ 43K, L ≤ 65K. Multiply a `build` chunk's first guess by 1.35 (measured: build chunks
   grew 1.35× their est, n=8); other kinds stay at 1.0 until `rnd.py chunks` has enough samples to say otherwise.
2. **Write the plan** as a table under `## Plan` in `<replies>/PROJ-123.md`, and run `session-status --plan FILE --check`.
   Write one brief per chunk, `<replies>/PROJ-123-cN.md`, from `--plan FILE --brief N`, plus a shared
   `PROJ-123-chunk-rules.md` (paths, setup, interface, checks, landing by fast-forward). Keep plans in the replies folder.
3. **Start** what `--plan FILE --next` prints; a chunk it lists again died or handed off: start it, or take its
   handoff. With `plan.enabled: false` run the task without a plan. **While the planner is evaluated**, odd task
   starts get a plan and even ones run as before, with `plan: off` in the brief (`rnd.py trial` compares the two).
4. **Models** by kind, from `plan.models` (`default` in the table); never `fable`.
5. **A `handoff ready: PROJ-123 cN` message**: `session-status --handover <id> --model M --effort E -- '<next step>'`
   (none for a chunk with `## cN: done`). **A `handoff ready: PROJ-123` message** (a task): `session-status
   --handover <id> -- '<next step>'`, the next step from `## Handoff` in its replies file. Message and attach the
   successor's plain name; a `-prev-K` name is a finished predecessor.
6. **Recalibrate** with `rnd.py chunks` (its ratio line, act against est) and size the next ests by it.

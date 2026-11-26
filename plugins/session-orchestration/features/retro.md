# Feature: retro

> **Start**: nothing to do: a retro run reports to you when it ends.
> **Read when**: a retro run's report arrives; the user approves some of its proposals; the user asks about the
> retro's schedule, scope or model; the newest retro report is over 8 days old.

Off by default. On when `features.retro` is `true` in the person's `.claude/coordination.local.json` (or the
person-wide `~/.config/session-orchestration/config.json`). It's a person key, like the whole `retro` block: a
committed file never starts a token-spending scheduled run for anyone, so the repo file can't set either. `/retro` by
hand works with the feature off.

A retro run (the `retro` skill) measures how this setup's sessions turn tokens into finished work and ranks at most 5
changes. It only measures and proposes; the user approves.

## Settings

`session-status --config KEY` prints each one in effect.

| Key | Values | Default |
|-----|--------|---------|
| `retro.scope` | `project` (this project's sessions) \| `plugin` (every project and account, what the plugin can change) \| `both` (one run each) | `project` |
| `retro.schedule` | `<day> HH:MM`, local time, day `mon`…`sun` (e.g. `mon 12:00`) | unset: by hand only |
| `retro.account` | the Claude config dir a scheduled run starts under (`~` expanded) | the current account |
| `retro.sections` | JSON list of section names: `units`, `context`, `waste`, `spend`, `feedback`, `coordinator`, `memory`, `protocol`, `features`, `sizing` | unset: every section of the scope |
| `retro.groups` | JSON object, `{"project"\|"plugin": {GROUP: [section names]}}`: a scope's section groups (`retro.py sections --groups SCOPE`); a section no group lists is the writer's; the group name `writer` is taken | unset: the default groups in `retro.py`'s `GROUPS` |
| `plan.models.retro` | `model/effort` a retro run starts on (`session-status --kind retro NAME`) | `fable/xhigh` under an account `fable.accounts` lists, else `opus/xhigh` |
| `plan.models.research` | `model/effort` for a research task (`--kind research`): a question answered from sources outside the project | `opus/high` |
| `plan.advisor.<kind>` | `fable` \| `opus` \| `sonnet`: the advisor trial's arm for that kind (`--kind` adds `--advisor A` where it pairs); `kinds` reports it as its own row (`build+fable`) | unset: off |

## Your part

- **A report arrives** (the retro's `reply`: its path and top proposals): pass it to the user as it is, with the
  report's path. Don't act on a proposal before the user approves it.
- **The user approves proposals**: start one fresh followups session for them, as
  [memory-rules.md](../skills/orchestrating-sessions/memory-rules.md) says. Never resume the retro session for it.
  A proposal the retro filed as a plugin feedback case is the plugin coordinator's, not yours.
- **The schedule**: `retro.schedule` takes effect once the plugin's `skills/retro/retro-run --install ROOT` loaded
  its LaunchAgent (macOS; setup proposes it, and the retro skill's Scheduling has Linux). It starts one session per
  section group of each scope when a run is due, a time missed in sleep or while off included, and a writer once
  they all end; only the writer reports. `retro-run --status ROOT` shows the agent, each scope's next due time and
  each open run (no report yet). A run whose groups all ended without a writer (`writer not started`): `retro-run
  --join DIR` with the DIR that line names (the scope's next `retro-run` call does it too).
- **An overdue run**: `--init --check` (and `retro-run --status ROOT`) prints `retro overdue (SCOPE): newest report N
  days old`. Tell the user once, with `retro-run --status ROOT`'s lines (an agent not loaded is the usual cause), and
  on their yes start it with `retro-run ROOT --now` from the plugin's `skills/retro/`. Its `started "NAME" (ID8)` line is the
  start (one per group): don't start it again while `claude agents` doesn't list it yet. Rerun only a scope whose line says `didn't start` (`--scope S`).

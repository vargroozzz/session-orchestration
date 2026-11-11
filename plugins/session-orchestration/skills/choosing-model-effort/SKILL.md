---
name: choosing-model-effort
description: Size a piece of work into a plan.models kind (scan, mechanical, build, design, review, release) and get the model and effort to run it on. Use before starting a session for a task (claude --bg), before proposing sessions so each line shows its kind, before choosing a subagent's model in a coordinated project, and in an R&D run comparing cost per kind.
---

# Choosing a model and effort

Each kind maps to a model and effort through config `plan.models.<kind>` (defaults: `scan` haiku/low, `mechanical`
and `release` sonnet/medium, `build` opus/medium, `design` and `review` opus/xhigh). Size the work into a kind, then
take that kind's values. Never `fable` unless the user names it.

## Size the work

Size by what the hardest step needs, not by the task's label. A "fix" can be `mechanical` and a "doc change" can be
`design`.

| Kind | The work | E.g. |
|---|---|---|
| `scan` | Reads and reports and changes nothing | A status check, a search, a summary of a log |
| `mechanical` | Changes whose every edit is known before you start | A one-file doc fix, a rename, a scrub tweak, a config value, a fix the case already spells out |
| `build` | Code that needs judgement: a cause to find, tests to write, or several files to keep consistent | A bug whose cause isn't known, a small feature in an existing pattern |
| `design` | Choices to make before code: a new interface, a new feature, a plan to split | A new command or skill, a change in how parts fit together |
| `review` | Judging someone else's change | A PR review, a diff audit |
| `release` | Landing and releasing work that is already done | Running the release steps, checking the installed version |

- Between two kinds, take the one the hardest step needs. Too small costs a retry, and a retry costs more than the
  difference.
- A batch takes the kind of its largest item. When one item is far larger than the rest, split it into its own task.
- Say why in a few words where the kind is shown ("mechanical: one-file doc fix"), so the user can amend it.

## Use it

- **A session (`claude --bg`)**: run `session-status --kind <kind> <session-name>` as its own call (`<session-name>` is
  the `-n` value: letters, digits, `.`, `_`, `-`, at most 80) and paste the `--model M --effort E` it prints onto the
  start line. Exit 2 means a wrong kind or name: fix it, and don't start without the flags. It logs the start for rnd,
  so run it once per task: a handover or fresh restart of the same task reuses the flags. `session-status` is in this
  plugin's `skills/orchestrating-sessions/` (`../orchestrating-sessions/session-status` from this skill's folder) and
  isn't on a task session's PATH: run it by that path.
- **A proposal line** (the coordinator's propose-first list): name the kind and the reason on each line.
- **A subagent (Agent tool)**: pass the model of the kind's `plan.models` value (`session-status --config
  plan.models.<kind>` prints it) as `model` when it is an alias the tool takes (`sonnet`, `opus`, `haiku`). A full
  model id: pass its family's alias. Set `effort` only when the user, a CLAUDE.md or a skill asks for that effort.
  Nothing is logged.
- **An R&D run**: the usage log's start lines (`{"k":"start","what":KIND,"model":…,"effort":…,"sess":…}`) carry
  `sess`, the first 12 hex characters of the session name's sha256. Hash each session's name the same way to join a
  start to that session's cost and outcome (the hash only keeps the name out of clear text: someone who can guess a
  name can confirm it), and compare them per kind.

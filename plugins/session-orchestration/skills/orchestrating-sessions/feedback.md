# Plugin feedback

Friction gets filed as a **case** by the session that hits it, which then carries on with its own work. File one the
moment you tell the user (or the coordinator) about it, not afterwards and not only when asked:
- you worked around the plugin (a manual chain where a step should exist, a stop and resume, a fallback);
- you took an extra round trip (to the user, a session, a tool) the plugin should have saved;
- you misreported because of its output or a file it keeps (a stale line passed on as current);
- the user had to step in (press, run or say something the flow should have covered);
- a script failed on a case it should handle, a doc contradicts itself, or a step is missing.

Plugin cases are per person, from every project, in `${XDG_STATE_HOME:-~/.local/state}/session-orchestration/feedback/`.
Nothing leaves the machine until the person approves the exact batch. Friction whose cause is the project (its
hosts, sign-ins, docs, scripts) is a **project case** (below).

`feedback` is next to `session-status`; `feedback` alone prints its usage.

## Capture (any session)

```
feedback add bugfixes 'session-status exits 1 when the adapter prints nothing' \
  --where skills/orchestrating-sessions/session-status:206 --found 'coordinating; a status sweep' \
  --evidence '`done` printed an empty line; status printed "failed" and dropped the board' \
  --suggested 'treat empty output as "none done"'
```

- Category: `bugfixes`, `features` or `refactorings`.
- Write in the plugin's terms only. `--where` is a path inside the plugin; `--found` is your role and step
  (coordinating, a task session, the R&D run), never the task or project; `--evidence` is at most 3 lines and names
  no ticket, path, person or project.
- Exit 3 lists open cases that look the same. If one is, `feedback seen FILE` adds today to its `seen:` line (that
  count ranks it); otherwise rerun with `--new`.
- Don't fix the plugin from a task session. The fix goes upstream as below.

A case file:

```markdown
# session-status exits 1 when the adapter prints nothing
- where: skills/orchestrating-sessions/session-status:206
- found while: coordinating; a status sweep
- plugin: 0.45.0
- evidence: `done` printed an empty line; status printed "failed" and dropped the board
suggested: treat empty output as "none done"
- seen: 2026-10-25, 2026-10-27
- status: open
```

`status` is `open`, `sent <url>`, `fixed <what changed>` or `dropped` (`feedback mark FILE …`).

## Project cases

`feedback add --project …` writes the same case to this project's store: config `feedback.project_dir` (relative to
the project root; keep it out of git), else `${XDG_STATE_HOME:-~/.local/state}/session-orchestration/feedback-projects/<root, encoded>`,
which worktree-isolated sessions can write. Its line is `- project: <root>` instead of `- plugin:`. Write it in the
project's own terms: it is never scrubbed or sent. `--where` is the project file at fault, or the step's name.
`feedback list`, `count` and `footer` show both scopes; `--plugin` or `--project` picks one. The project store is
project-memory's `cases` (its `project-memory` skill), which a project without a coordinator uses directly.

The R&D run groups the open project cases into patterns and proposes one project fix per pattern (a doc, script or
setting); its followups session applies the approved ones and marks each case `fixed`. The apply flow below never
takes them.

## Offering it

- **The coordinator.** The status sweep's footer shows `plugin feedback: N open (M seen ≥2×) — apply?` at most
  once a day, then `· project feedback: K open …, for the next R&D run` when the project has some. Pass it on to the
  user with the other footer items; on a yes to the apply, start an apply session (below).
- **The R&D run** ends its report with the open plugin cases, most seen first (`feedback list --plugin`), and offers
  the apply; the project's cases are proposals in that report ([rnd](../rnd/SKILL.md), step 7).

Never apply without the user's yes for that batch.

## Applying (an apply session)

1. `feedback mode` names the mode; `feedback list --plugin` the open cases (never the project's); `feedback repo` the upstream repo (REPO below)
   and `feedback label` an issue's label (LABEL). Write both into the `gh` commands as text: an approval hook can't
   check a `gh` command built with `$(…)`. Pick the batch: one case each, or related ones together.
2. Search upstream first: `gh search issues --repo REPO --state open '<title words>'` and the same for
   `gh search prs`. A case already filed: mark it `sent <that url>`, and add a comment there only on the user's yes.
   When `gh repo view REPO` fails (the repo isn't public yet, or you have no access), only `pr` works: skip the
   search and send nothing by `fork-pr` or `issue`.
3. `feedback scrub FILE…`. Its deny list comes from every project root a case was added in or your sessions ran in (their names, remotes,
   key patterns, adapter hosts and config strings) plus your home, user and git identity; the plugin's own repo URL,
   name and state paths never count. Any hit keeps that case local: show the user the line, and reword the case (in
   plugin terms) or drop it (`feedback mark FILE dropped`). Never send a case with a hit.
4. Send, by mode:

| Mode | When it's the default | What the session does |
|---|---|---|
| `pr` | `feedback.repo_dir` is set (you can push to the plugin repo) | A worktree in `feedback.repo_dir`, one branch and PR per case (related ones together), the repo's own release checks (its `CLAUDE.md`), the PR body linking the case's title |
| `fork-pr` | `gh auth status` succeeds | The same in a fork: `gh repo fork REPO --clone`, then a PR from the fork |
| `issue` | neither | One issue per case: `gh issue create -R REPO --label LABEL --title '<case title>' --body-file <case file>`; without `gh`, print the scrubbed case for the user to file |
| `local` | set `feedback.mode` to `local` | Nothing is sent; the cases stay files |

   Each outgoing `gh pr create` or `gh issue create` goes to the user as one approval: name every body file with its
   sha256 (`shasum -a 256 FILE`), and pass the command to `hand_command` (or ask in plain text when mods are off).
   Run nothing outward-facing before that yes.
5. `feedback mark FILE sent <url>` for each case sent.

Config (person keys): `feedback.mode` (`auto` default, or `pr`, `fork-pr`, `issue`, `local`), `feedback.repo_dir`
(a clone of the plugin repo you can push to). They hold for you in every project, so set them once in
`${XDG_CONFIG_HOME:-~/.config}/session-orchestration/config.json`; a project's `.claude/coordination.local.json`
outranks that file. `feedback.project_dir` (Project cases) is per project: set it in that project's
`.claude/coordination.local.json`, since an absolute path set for every project would put all their cases in one store.

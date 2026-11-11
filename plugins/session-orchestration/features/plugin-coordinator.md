# Feature: plugin coordinator

> **Start**: run `feedback list --plugin` (next to `session-status`). Triage the open cases, group them into batches,
> and propose one apply session per batch (below).
> **Read when**: the watcher prints a `Feedback (feedback list --plugin)` line; the user gives you plugin feedback or
> asks about a case; an apply session or a release reports.

On when config `feedback.repo_dir` names this project's root. That is a person key, set once in
`${XDG_CONFIG_HOME:-~/.config}/session-orchestration/config.json`. The coordinator of that clone of the plugin repo
then owns the plugin. Every session's `feedback add`, from every project and account, lands in the per-person case
store ([feedback.md](../skills/orchestrating-sessions/feedback.md)), and that store is your queue. Other
coordinators file plugin feedback there. They never start an apply session, and their footer shows the count only
while you aren't running.

**Setting it up.** Once:
1. Set `feedback.repo_dir` to a clone of the plugin repo that you can push to.
2. Run `claude 'Act as a coordinator'` in that clone. Setup runs the first time. When `CLAUDE.md` is tracked, setup
   writes its section to `CLAUDE.local.md`.

`feedback coordinator` prints this coordinator's name (`<folder>-coordinator`) while it runs, under any account, and
names the account when it isn't the caller's. `feedback coordinator --start` opens it in a terminal tab, named
already. Other coordinators use both.

**Triage.** For each open case:
- A duplicate of another open case: `feedback seen` the one you keep (its count ranks it). Mark the other one
  `dropped`.
- A case the code no longer matches (already fixed, or the file is gone): tell the user. Mark it `fixed <what>` or
  `dropped` only on their word.

**Batches.** Put cases that change the same file or step into one batch. Every other case is a batch of its own,
most seen first. Propose the batches the way your mode says to start sessions ([SKILL.md](../skills/orchestrating-sessions/SKILL.md),
Starting a session): one line per apply session, with its session name, its cases' titles, the done-when, and its
kind with the reason, sized per batch with the `choosing-model-effort` skill (a one-file doc fix is `mechanical`, a new
feature `design`), never one kind for all.

**Apply sessions.** Start one per batch the user names, from this root. Run `session-status --kind <its kind> <name>`
first (`<name>`: a task name the project's key pattern matches, of letters, digits, `.`, `_` and `-`, at most 80), then `claude --bg -n <name>` as SKILL.md says, with this
brief, which starts with the name so the status shows its owner: `Work on <name>: Apply plugin feedback: <case file paths>. Follow feedback.md,
Applying, for these cases only, and this repo's CLAUDE.md release checks. Why: <what the cases say goes wrong>. Done
when: the change is implemented with the repo's checks passing, a PR is open, and each case is marked sent <url>.`
Because they work in your project, relayed approvals verify for them ([approvals.md](../skills/orchestrating-sessions/approvals.md)).
Their `gh pr create` reaches you as an ask like any other.

**Releases.** A batch's PR lands the way the repo's `CLAUDE.md` says. Where that is a release command, an approval to
land the PR is an approval to run it, not a GitHub merge. The release is a session's task, or the command it hands the
user. Once the release is on the repo's main (check it yourself, and take the version from it):
1. Mark each of its cases `fixed <version>` (`feedback mark FILE fixed …`).
2. Call `reload_plugins`.
3. Tell the user that other running coordinators keep the old version until they call `reload_plugins` themselves.

**New cases while you run.** The watcher prints each new open case under `Feedback (feedback list --plugin)`.
Triage it, then add it to a batch you've proposed or propose a new one. When another coordinator messages you a
case's path because the user wants it applied now, propose that case's batch at once, ahead of the rest.

**When you aren't running.** Nothing is lost: cases wait in the store, and your next Start lists all of them. In
other coordinators, the once-a-day footer reads `plugin feedback: N open (M seen ≥2×), for the plugin coordinator,
which isn't running — start it? (feedback coordinator --start)`. On the user's yes, that coordinator runs the
command.

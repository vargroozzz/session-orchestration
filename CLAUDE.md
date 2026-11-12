# session-orchestration

## Releasing a plugin change

1. `version` lives only in `plugins/<plugin>/.claude-plugin/plugin.json`, and a branch leaves it alone: the release
   workflow (`.github/workflows/release.yml`, running `.github/release.sh`) numbers each plugin from main's version
   when the change lands, one push at a time, so two branches never claim the same number. Commit as
   `<plugin>: <what changed, in plain words>`; the release commit becomes `<plugin> <version>: <that text>`: the next
   minor, or the next patch when every commit of the change carries a `Release: patch` trailer
   (`git commit --trailer 'Release: patch'`). Docs on the branch say "from the release after <feature>", never a
   version that doesn't exist yet. A branch that bumped `version` in its last commit keeps that number.
2. Before committing: `claude plugin test plugins/<plugin>`, `tsc -p plugins/<plugin>` (needs the
   engine's generated `.claude-plugin/types/`, untracked), `claude plugin validate plugins/<plugin>` and
   `./scrub-check.sh` (no personal or company names: examples use `PROJ-123`, paths `/home/u/…`).
3. Land it through a PR: push the branch, open the PR and, once the task is approved, `gh pr merge <N> --auto --rebase`.
   `main` takes only rebase merges of a branch that is up to date with it and green in CI; nothing pushes `main` by
   hand. Each landing adds a release commit, which puts every other open PR behind `main`. Until yours shows merged,
   after each `gh pr checks <N> --watch` check `gh pr view <N> --json state,mergeStateStatus`; on `BEHIND` (or a
   conflict) run `git fetch origin && git rebase origin/main && git push --force-with-lease`. Auto-merge stays on and
   merges once CI is green again. No merge queue: GitHub offers it only to organization repos.
4. Install it: `claude plugin update <plugin>@session-orchestration` once the marketplace source has the release
   commit, then check `installed_plugins.json` lists `<plugin>` at the new version. A command you can't run
   yourself goes to the user as one line, through session-orchestration's `hand_command` too.
5. Reload. Running sessions pick up a new tool or hook after `/reload-plugins`: the coordinator calls
   session-orchestration's `reload_plugins` tool, which runs it in its own session when the turn ends (from
   0.27.1; a worker reloads the same way when messaged to). Restart a session where the new tool doesn't show.

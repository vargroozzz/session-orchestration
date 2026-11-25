# Landing a plugin change

CLAUDE.md "Releasing a plugin change" steps 3-5. Read it before you push a branch, and before you install or reload
a release.

3. Land it through a PR: push the branch, open the PR and, once the task is approved, `gh pr merge <N> -R OWNER/REPO --auto --rebase`
   (`mergeStateStatus` already `CLEAN`: `gh pr merge <N> -R OWNER/REPO --rebase`, no `--auto`, which gh refuses there;
   a refused merge leaves the relay usable while the PR stays open with no auto-merge).
   The steps below are one command on the same relay:
   `session-status --land OWNER/REPO#N`, alone, in the background (worker.md "Posting and merging"); it ends with
   `merged and green: SHA` or what failed. The steps stay for a run lost midway and for landing by hand.
   In a coordinated session, approved means the coordinator's relay naming that PR (`merge OWNER/REPO#N`): send the
   done report first (`reply` with `done: pr` and `key`), then merge once the relay arrives. An approval in the start
   brief is the coordinator's to relay, not the session's to act on, and the approval hook refuses the merge before
   the relay; none comes: ask for it as worker.md's "Posting and merging" says.
   `main` takes only rebase merges of a branch green in CI; nothing pushes `main` by hand. A branch need not be up to
   date with `main`: each landing adds a release commit, so `BEHIND` is normal and GitHub rebases the branch as it
   merges. Until yours shows merged, after each `gh pr checks <N> -R OWNER/REPO --watch` check
   `gh pr view <N> -R OWNER/REPO --json state,mergeStateStatus` (they may share the merge's command, and a wait loop may
   test them: `[ "$(gh pr view …)" = MERGED ]`); `BEHIND` needs nothing, only a conflict (`DIRTY`) does:
   `git fetch origin && git rebase origin/main`, then `git push --force-with-lease --force-if-includes origin <branch>` alone (the approval
   hook lets a session force-push its own open PR's branch in that one form; worker.md, "A PR event on your PR"). Auto-merge stays on and merges once CI
   is green. No merge queue: GitHub offers it only to organization repos.
   Since no PR is tested on top of the others, `test.yml` runs again on each push to `main`. Once yours is merged, watch
   the run on its landing commit (`gh pr view <N> -R OWNER/REPO --json mergeCommit` names it;
   `gh run list -R OWNER/REPO -w test -c <sha>` finds the run, listed a few seconds after the merge;
   `gh run watch <id> -R OWNER/REPO --exit-status --interval 60` waits; the default 3 s polls spend the account's API
   limit, and the watch then exits 1 on HTTP 403, which reads as red). A job cancelled for want of a runner ("not
   acquired by Runner of type hosted") is re-run with `gh run rerun <id> --failed`, not reported as a red main. Red, with the run on the commit before yours green: your
   change broke `main` together with one that landed before it. Tell the coordinator, then fix it forward in a new PR
   through these same steps (`Release: patch`), or revert your commit that way when the fix isn't quick. Red before
   yours too: tell the coordinator; the fix is the session's whose landing turned it red first.
4. Install it: the project's coordinator runs the install once per release commit (until the user says otherwise):
   `claude plugin update <plugin>@session-orchestration` once the marketplace source has the release commit, then it
   checks `installed_plugins.json` lists `<plugin>` at the new version. A worker's done report says "released", with
   no command handed to the user.
5. Reload. Running sessions pick up a new tool or hook after `/reload-plugins`: the coordinator calls
   session-orchestration's `reload_plugins` tool, which runs it in its own session when the turn ends (from
   0.27.1; a worker reloads the same way when messaged to). Restart a session where the new tool doesn't show.

## On the maintainer's machine

A machine with `~/bin/plugin-release` is the maintainer's; elsewhere skip this section. There the repo (`OWNER/REPO`) is
`vargroozzz/session-orchestration`, and the main checkout is the `session-orchestration` marketplace source, so the
installed plugin only changes once that checkout has the release commit.

- Step 3 runs each `gh` command alone in its own call: no wait loop or `$(…)` around it, which the approval hook
  refuses here; repeat `gh pr checks <N> -R OWNER/REPO --watch --interval 60` and the `gh pr view` instead.
- Step 4's install is `~/bin/plugin-release` (no argument), on this machine only: it fast-forwards the main checkout once
  the release commit is on origin/main, updates every changed plugin in both accounts (`~/.claude` and
  `~/.claude-work`) and prints the installed versions. Since 2026-11-18, until the user says otherwise, the coordinator
  runs it itself, once per release commit on origin/main, checks the versions it prints and reloads. A worker never
  hands `! plugin-release`: its done report says "released".

# session-orchestration

## Releasing a plugin change

1. `version` lives only in `plugins/<plugin>/.claude-plugin/plugin.json`. Bump it to main's next when
   releasing, or `claude plugin update` sees nothing new; a release script named in `CLAUDE.local.md`
   may number it for you when it lands (then leave it alone, so two branches never claim the same
   number). Commit as `<plugin>: <what changed, in plain words>`;
   the release commit becomes `<plugin> <version>: <that text>`. Docs on the branch say "from the
   release after <feature>", never a version that doesn't exist yet. `--patch` for a fix-only release.
   Before releasing more work from a branch that already released, rebase it onto main.
2. Before committing: `claude plugin test plugins/<plugin>`, `tsc -p plugins/<plugin>` (needs the
   engine's generated `.claude-plugin/types/`, untracked), `claude plugin validate plugins/<plugin>` and
   `./scrub-check.sh` (no personal or company names: examples use `PROJ-123`, paths `/home/u/…`).
3. Push to `main`.
4. Install it: `claude plugin update <plugin>@session-orchestration` once the marketplace source has the commit,
   then check `installed_plugins.json` lists `<plugin>` at the new version. A command you can't run
   yourself goes to the user as one line, through session-orchestration's `hand_command` too.
5. Reload. Running sessions pick up a new tool or hook after `/reload-plugins`: the coordinator calls
   session-orchestration's `reload_plugins` tool, which runs it in its own session when the turn ends (from
   0.27.1; a worker reloads the same way when messaged to). Restart a session where the new tool doesn't show.

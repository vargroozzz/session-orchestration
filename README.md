# session-orchestration

A Claude Code plugin marketplace with two plugins:

- **session-orchestration**: run several Claude Code sessions in parallel with one coordinator session keeping track
  of them ([README](plugins/session-orchestration/README.md)). Installing it installs project-memory too.
- **project-memory**: what one session learns, the next one knows, with or without a coordinator: project memory, a
  `/graduate` pass into the docs, project friction cases, deferred tasks, and guards for background sessions
  ([README](plugins/project-memory/README.md)).

```
claude plugin marketplace add vargroozzz/session-orchestration
claude plugin install session-orchestration@session-orchestration   # or project-memory@session-orchestration alone
```

## Contributing

`CLAUDE.md` has the release steps. Checks, all run by CI (`.github/workflows/test.yml`):

- every `*.test.sh` prints `ok`;
- `claude plugin test plugins/<plugin>` (the hooks module's `*.test.ts`; only a plugin with a hooks module, so not
  project-memory) and `claude plugin validate plugins/<plugin>` pass; neither needs a signed-in account;
- `tsc -p plugins/<plugin>` passes (a plugin with a `tsconfig.json`). Its types (`.claude-plugin/types/`, untracked) are written by Claude Code itself
  each time a session loads the plugin from a folder you own: add the marketplace from your clone
  (`claude plugin marketplace add ./`) and install the plugin from it; the next session writes them. CI can't, so
  it skips this one;
- `./scrub-check.sh` prints `ok`: no personal or company names in the tree. Its deny pattern isn't in the repo: put
  your own in `~/.config/scrub-deny` (one ERE line) or `SCRUB_DENY`; known hits go in `scrub-allow.txt`.

License: MIT (`LICENSE`).

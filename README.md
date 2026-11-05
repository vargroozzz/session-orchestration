# session-orchestration

A Claude Code plugin marketplace with one plugin, **session-orchestration**: run several Claude Code sessions in
parallel with one coordinator session keeping track of them. See
[its README](plugins/session-orchestration/README.md) for what it does, requirements, install and setup.

## Contributing

`CLAUDE.md` has the release steps. Checks, all run by CI (`.github/workflows/test.yml`):

- every `*.test.sh` prints `ok`;
- `claude plugin test plugins/<plugin>` (the hooks module's `*.test.ts`) and `claude plugin validate
  plugins/<plugin>` pass; neither needs a signed-in account;
- `tsc -p plugins/<plugin>` passes. Its types (`.claude-plugin/types/`, untracked) are written by Claude Code itself
  each time a session loads the plugin from a folder you own: add the marketplace from your clone
  (`claude plugin marketplace add ./`) and install the plugin from it; the next session writes them. CI can't, so
  it skips this one;
- `./scrub-check.sh` prints `ok`: no personal or company names in the tree. Its deny pattern isn't in the repo: put
  your own in `~/.config/scrub-deny` (one ERE line) or `SCRUB_DENY`; known hits go in `scrub-allow.txt`.

License: MIT (`LICENSE`).

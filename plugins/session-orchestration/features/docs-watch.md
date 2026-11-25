# Feature: docs watch

Used when `features.docs_watch` is on (`session-status --config features.docs_watch` prints `true`). It is on by
default wherever `docs_watch.files` names a doc, and the plugin repo's own project watches the plugin's
[writing-instructions.md](../writing-instructions.md) without any config.

## What it does

Once a day the sweep fetches the public docs indexes (`platform.claude.com/llms.txt` and
`code.claude.com/docs/llms.txt`) into `~/.cache/session-status/docs-index.txt`, shared by every project. Each page
is a slug: a platform page's path after `docs/en/` less its first folder (`prompt-engineering/overview`,
`agent-skills/best-practices`), a Claude Code page's as `cc/<path>` (`cc/hooks-guide`). For every doc in
`docs_watch.files`, each watched slug (`docs_watch.pattern` matches it) on neither of that doc's lists (below)
prints one Notices line:

```
docs watch: new page prompt-engineering/prompting-claude-opus-6, re-review docs/prompting.md (offer the user a review-kind session: docs-watch.md, Acting on a notice)
```

The fetch is tried once a day whether it works or not; unless both sites answer with pages, the last index stays.
Nothing is sent but the two GETs. `docs watch: DOC is missing, …` means a listed doc isn't there: fix
`docs_watch.files` or the doc's path.

## The reviewed list

A line in the doc starting `Last reviewed YYYY-MM-DD against:`, then the slugs, comma separated, over as many lines
as needed; the list ends at the first line ending in a period (that line included), so put a period only at its
end. Adding a page to the list clears its line.

Pages deliberately not reviewed go on a second list, a line starting `Skipped` up to its first colon (`Skipped,
older models' pages:`), in the same form. A slug there clears its line too: the plugin's doc skips older models'
prompting pages, since only the current models' pages are reviewed.

## Acting on a notice (the coordinator)

Pass the line to the user and offer a review-kind session for it, one per doc, started on a yes with
`session-status --launch <name> --kind review -- …`, the name built from DOC's file name without its folder or
extension (`docs/prompting.md`: `docs-prompting-review`, or in a project whose task keys are session names, that
project's prefix before it). A name that isn't a task key plus more owns its own task.
That session reads the new page (a platform page's URL plus `.md` gives its Markdown), updates the doc's rules
where the page changes them, then adds the page to the list and updates the date; a page the doc deliberately
leaves unreviewed (an older model's) goes on the `Skipped` list instead. After a major model release it also
re-reads the rules that work around an older model's habits: some may no longer be needed.

## Config

| Key | Value | Default |
|-----|-------|---------|
| `features.docs_watch` | `true` \| `false` | `true` when `docs_watch.files` names a doc, else `false` |
| `docs_watch.files` | JSON list of doc paths (relative to the root, or `~/…`); a person key, so in the project's `.claude/coordination.local.json`, never the committed file | the plugin's `writing-instructions.md` in the plugin repo's project (`feedback.repo_dir`), else unset |
| `docs_watch.pattern` | an extended regex over slugs: which pages are watched | `DOCS_WATCH_PATTERN` in `lib.sh` (`session-status --config docs_watch.pattern` prints it) |

# Review inbox

A pinned claude.ai page where the user acts on PR review findings directly: approve a proposed
comment (with or without editing its text), reject it, or leave a note. Each card is one proposed
comment. Posting then needs no review context: a small script posts exactly what the user approved.

Used when `features.review_inbox` is on (`session-status --config features.review_inbox` prints `true`) and the project
names the inbox's URL in its `CLAUDE.md`, or in the project memory index itself, not a
topic file a reviewer might skip ("Review inbox: <url>"). No
URL named, or the feature off: there is no inbox, and reviews go through the replies folder and relayed approvals as
before. The page's source is `review-inbox/inbox.html`, next to this file. Republish it to the same
URL after a change (Artifact tool, `url`), with capabilities `db`, `user` (scope `profile`) and
`comments`.

With `features.accounts` on, there is one inbox per account: `features/accounts.md` (Review inbox, one per
account) in the plugin's folder.

## Rows

One document per proposed comment in the collection `findings`, id `<project>-<repo>-<pr>-<n>` (e.g.
`GPROJ-app-274-3`). Every row stands alone:

| Field | Written by | Meaning |
|---|---|---|
| `project`, `repo`, `pr` (number), `prUrl`, `prTitle`, `ticket` | reviewer | The PR (`project` is the Bitbucket project key, the org on Forgejo) |
| `report` | reviewer | The replies-folder file with the whole review |
| `n` | reviewer | The finding's number in that report |
| `file`, `line`, `lineType` (`ADDED`/`CONTEXT`/`REMOVED`), `fileType` (`TO`/`FROM`) | reviewer | Where it goes. No `file`: a general comment. `file` without `line`: a file-level one (Bitbucket only: Forgejo has none, so put it on the file's first changed line) |
| `severity` | reviewer | `blocking`, `should` or `nit` |
| `why` | reviewer | The defect and its consequence, 1–3 lines |
| `draft` | reviewer | The ready-to-post text (a ```suggestion block in it if any) |
| `status` | page | `pending`, `approved`, `rejected` or `noted` |
| `final`, `note` | page | The text to post (the user's edit of `draft`), the user's note |
| `decidedBy`, `deciderIsOwner`, `decidedAt` | page | The viewer's id, whether they own the inbox, when |
| `decisionHash` | page | sha256 over the decision and what it covers (see `verify-row.sh`) |
| `sentAt` | page | When the page told Claude about the decision |
| `commentId`, `postedAt` | poster | The posted comment |
| `answer`, `answeredNote` | note session | The reply to a note, and the note it answers |

**Only the page writes `status`, `final`, `note` and the decision fields**, from the user's click.
A session never writes them, except a note session resetting a row to `pending` (below).

## Reviewer sessions

After writing the replies-folder report (still the record), add one row per finding with
`ArtifactData` `batch`, all entries `op: "set"` with no `if_version` (creates only, so an existing
row is never overwritten), `status: "pending"`, `createdAt`. Number on from the highest `n` the
PR already has (query `project`, `repo` and `pr` first). Don't post anything. Send the status report naming the
report file and "N findings in the review inbox", then you're done: posting doesn't need you, so the
coordinator can stop you.

## What a decision means

A row the user approved on the page **is the user's own approval to post that row's `final` text
there, once**. It goes through no relay, and `verify-approval.sh` doesn't apply. Check it instead
with `verify-row.sh` (`post-approved.sh` runs it for each row): `verified` means the row says it was
approved by the inbox owner, at most 72h ago (`MAX_AGE_H`), and nothing the decision covers (text,
PR, file, line, note) changed since the click. It approves posting that one comment, nothing else:
not a PR approval, not a merge, not another comment.

Its limit: sessions write the inbox as the user, so the store can't tell a click from a session's
write. The hash catches an edit after the decision, not a decision a session forged. So the rule
above is the guard.

## Posting

A fresh session, started for the job (`claude --bg 'Post the approved review-inbox rows for <project>
<repo> #<pr>: <inbox url>. Per the session-orchestration skill, review-inbox.md (Posting).'`):

1. `ArtifactData` `query` on `findings`, `where` `[["status","==","approved"],["project","==","<project>"],["repo","==","<repo>"],["pr","==",<pr>]]`,
   with a **new, empty** `out_dir` each run: `/tmp/review-inbox-<your session id's first 8>-<unix
   time>` (`~/.claude` is refused as an out_dir; an old file would post a row the user has since
   withdrawn). Note each row's `version` from the result.
2. `bash <this skill's folder>/review-inbox/post-approved.sh <that out_dir>`. Per row it prints
   `posted <id> <commentId>`, `skipped <id>: <reason>` or `failed <id>: <error>`. It posts only
   comments, adds the AI disclosure marker when `~/.claude/ai-disclosure.on` exists, and keeps a
   ledger (`review-inbox-posted.tsv` in the account's `CLAUDE_CONFIG_DIR`, one line per row id) so no row is posted twice: not
   by a re-run, nor after the user undoes and re-approves a row already posted. One run at a time
   (a lock next to the ledger).
3. For each `posted` line, `ArtifactData` `update` that row with `commentId` and `postedAt`,
   `if_version` from step 1. A `failed` row stays in the ledger as `unknown`, since the CLI may have
   failed after the host took the comment: report it. To retry, the PR must have no such comment;
   then delete that row's ledger line. If the update fails on the version (the user pressed Undo
   meanwhile), re-read the row and still write `commentId`: the comment is out.
4. Report: posted N, skipped/failed with the reasons, as the status report.

Never post a row the script skipped, and never post by hand what the script would refuse. A direct
`bitbucketdc-cli` or `forgejo-cli pr comment create` stays gated by the plugin's `approved-action.sh` hook, which
wants a relayed approval: the script is the inbox's only way to post.

**Known gap.** Auto mode may deny the post in a background session (it publishes under the user's
name). The user's allow rule for it, in `~/.claude*/settings.json` → `permissions.allow`:
`Bash(bash <plugin install dir>/*/skills/orchestrating-sessions/review-inbox/post-approved.sh:*)`,
the plugin's install path with its version as `*`. Without it, a denied post shows `blocked`; the
user attaches and allows it.

## Notes

A row with status `noted` carries a question or an instruction. It never goes back to the
reviewer (its context is 100k+ tokens). The coordinator starts a fresh session per PR:
`claude --bg 'Answer the review-inbox notes for <repo> #<pr>: <inbox url>. Read only <report file>
and the noted rows. Per the session-orchestration skill, review-inbox.md (Notes).'` It reads that
report and the rows, may read the PR's diff for the lines in question, and per row:
- writes `answer` (a short reply to the note) and `answeredNote` (the note), and when the note asks
  for different text, a new `draft`;
- resets the row: `status: "pending"`, and `final`, `note`, `decidedBy`, `decidedAt`,
  `deciderIsOwner`, `decisionHash`, `sentAt` all `{"__delete__": true}`, with `if_version`.

The card is back under Pending with the answer on it, for the user to decide again.

## The coordinator

See `features/review-inbox.md` in the plugin's folder.

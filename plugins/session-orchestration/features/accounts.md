# Feature: accounts

On when `features.accounts` is `true` in `.claude/coordination.local.json` (a person key: the repo file can't set
it). Setup turns it on when it finds a second Claude account sharing this one's transcripts, and `session-status
--init --check` warns when one appears while it is off. Off, everything asks only the current account.

**What it changes.** Each `CLAUDE_CONFIG_DIR` is a separate account with its own background daemon and `claude
agents` list. With the feature on, `session-status` (status, `--activity`, `--all-projects`, the pane) asks every
account whose `projects/` is the same directory as yours (`~/.claude` and every `~/.claude-*`), and prefixes the
commands that reach another account's session with its `CLAUDE_CONFIG_DIR` (`env -u CLAUDE_CONFIG_DIR claude` for
`~/.claude`). `verify-approval.sh` looks the coordinator up in each of those accounts' `claude agents`, so a relayed
approval verifies from a worker under another account. The list comes from `features/accounts.sh`.

## Coordinating across accounts

`claude --bg` and `--resume` run from your Bash tool inherit your `CLAUDE_CONFIG_DIR`, so workers you start or
resume run under your account; don't set or unset it. That is what lets them `SendMessage` you. If `claude --bg`
fails with "Workspace not trusted", ask the user to run `claude` there once under your account's
`CLAUDE_CONFIG_DIR` (if it isn't the default) and accept the trust prompt; don't start the worker under another
account to get around it.

`claude agents`, `attach`, `logs`, `stop`, `ListAgents` and `SendMessage` only see sessions of your own account. A
session running under another account is invisible to them, so the duplicate check before a `--resume` can't
catch it, and one stopped there isn't found here either (`claude logs` says `No job matching`). If `--resume`
finds its transcript, it continues the same conversation under your account: before resuming a closed session,
ask the user to confirm it isn't still running under another account.

**Keep every task session under your own account** unless the user names the other one: you can't message a
session under another account.
- **Moving a session to your account:** stop it under the account it runs in (prefix the command with that
  account's `CLAUDE_CONFIG_DIR`, as `session-status` prints it), then `claude --bg --resume <full id> "<note>"`
  here. An approval for it still goes by SendMessage after the move, never in the resume prompt. (2026-10-05.)
- **Follow-ups** (`session-status --send-when-idle`): a live session in another account that is idle is stopped,
  waited on until its process ends, and resumed with the text under the same id. If it waits on a prompt, the
  helper exits 3 and names the attach command instead: a stop would drop the prompt. The context-size rule for
  resumes applies (read its `ctx` first).
- **Waking or stopping** a session under another account (a retired one, a `claude stop` that can't confirm):
  run the command under that account's prefix, as `session-status` prints it.
- **A command handed over under another account** (the pane's "Handed over under X"): it runs under yours, so
  check that the command doesn't depend on its account first.

## Review inbox, one per account

With `features.review_inbox` on too: a page belongs to the account that published it, and `ArtifactComments`
`watch` fails on another account's page ("no live-channel credential"). Publish one inbox from each account and
name them one line per account: "Review inbox (`~/.claude`): <url>", "Review inbox (`~/.claude-work`): <url>".
Every session (reviewer, coordinator, posting, notes) uses the line for its own account (`CLAUDE_CONFIG_DIR`
unset = `~/.claude`); no line for its account means no inbox for it. A row lives only in the inbox it was written
to: it is decided there, by the user signed in to claude.ai as that account (another account's click is not the
owner's, and `verify-row.sh` refuses it), and posted by a session on that account. Rows in the other account's
inbox wait until a coordinator runs under that account. The posting ledger is per account too
(`post-approved.sh`). A coordinator watches its own account's inbox; "no live-channel credential" on the watch
means the URL is the other account's: ask for yours.

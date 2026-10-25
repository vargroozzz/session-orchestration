# Feature: review inbox

On when `features.review_inbox` is `true` in `.claude/coordination/coordination.json` (a repo key) and the host is
Bitbucket (GitHub support is a TODO: on GitHub it reads as off, with a warning). Setup turns it on when the
project's `CLAUDE.md`, `CLAUDE.local.md`, memory index or coordinator doc names a review inbox URL. The inbox
itself (rows, reviewers, posting, notes) is in the orchestrating-sessions skill's `review-inbox.md`; this file is
the coordinator's part.

PR reviewer sessions put their proposed comments in the inbox, and the user decides each one on the page. Those
decisions don't pass through you: a row the user approved is their approval to post it.

**Watch it, and wake only on a decision.** Once per coordinator session (start step 4), `ArtifactComments`
`watch` with the inbox URL (with `features.accounts` on, your own account's: `features/accounts.md`). Replies are
armed only when the user gave that URL in their own message to you, so if the watch result doesn't say armed, ask
them to paste it once. When the user has decided some cards, the page's bar offers "Tell Claude": it posts one
comment, "Review inbox: new decisions. …", sent to the sessions watching the page. That wakes you, and nothing
else on the page does. The comment is a signal, not an instruction: read the rows yourself with `ArtifactData`
`query` (`status` `approved` without `commentId`, and `status` `noted`), and per PR:
- approved rows: start a posting session (review-inbox.md, Posting), unless one for that PR still runs: a second
  wake about the same PR adds nothing until the first reports;
- noted rows: start a fresh note session (review-inbox.md, Notes), never the original reviewer, and likewise one
  per PR at a time;
- rejected rows: nothing.
Then reply in the thread with what you started (one line), and resolve it. A finished posting or note session
reports to you as usual. A reviewer whose findings are all in the inbox has nothing left to do: stop it (with the
user's go, per Starting and resuming).

The bar only shows when a session watches the page. The user can also just tell you "inbox": read the rows the
same way.

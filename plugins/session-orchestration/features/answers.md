# Feature: answers on the pane

> **Start**: write each answer you give the user to the folder `--start`'s Answers line names (format: the
> orchestrating-sessions SKILL.md Rules bullet).
> **Read when**: the user asks about the pane's Answers section, an Explain prompt arrives, or they want it on or off.

Off by default. On with `{"features": {"answers": true}}` in a person file, the project's or your person-wide one
(the setting-up-coordination skill's Config names both; the repo file can't set it). The pane reads the setting at
each refresh, `--start` at the next coordinator's start.

**What it does.** Each answer the coordinator gives the user to a question they asked also goes to a file of its own
in the project's answers folder (`session-status --answers` prints the folder, making it when missing). The
coordinator pane's **Answers** section, under Decisions, lists the unread ones, newest first, 50 at most: a row is the
answer's age and its question; pressed, a card shows the answer as markdown, the file's path and two buttons:
- **Mark as read** (`e`): `session-status --answers --read NAME` moves the file to the folder's `archive/` (a name
  taken there gets `-<epoch>` added before `.md`), and the row goes.
- **Explain** (`k`): a prompt asking the coordinator to rewrite that file in place with a fuller answer; the card
  shows the new text within a minute of the rewrite.

A successor coordinator's `--start` shows only how many are unread, never their text: they are the user's to read on
the pane, not the next coordinator's context. The section's slug for `pane.sections` is `answers`.

**Where it lives.** `${XDG_STATE_HOME:-~/.local/state}/session-orchestration/projects/<root, encoded>/answers/`, the
person's state folder: personal, never in git, and not shared with anyone else who works in the project, with or
without this plugin. Nothing moves when it's turned on or off; the folder is made on first use.

**What it never does.**
- It holds no status summaries and no replies to sessions: only answers to questions the user asked.
- It sends nothing off the machine.
- It deletes nothing: Mark as read moves the file to `archive/`, which keeps every answer.

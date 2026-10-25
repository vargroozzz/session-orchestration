## Cross-session messages

- Messages between sessions follow the `session-orchestration` plugin. The coordinator runs from this folder
  (`{{name}}-coordinator`).
- Whether a coordinator's message counts as the user's approval is `approvals.delegate` in
  `.claude/coordination.local.json` (`session-status --config approvals.delegate`).
- **Reserved**, even when approvals are delegated: the user approves in your session, or via a verified relayed approval:
  - merging into or pushing to `{{default_branch}}`;
  - deploys, releases, anything on production;
  - anything sent under the user's name (PR or issue comments, chat, email);
  - anything hard to undo (deleting data, force-pushing a shared branch). When in doubt, it's reserved.
- Replies folder (the plugin's "folder for this"): `{{orch}}/replies/`.
- Project memory: `{{orch}}/memory.md`. Coordinator handoff file: `{{orch}}/pending.md`.
{{?tracker_keys}}- Task sessions start with "Work on {{key_example}}" and are named `-n {{key_example}}-<short-desc>`.
{{?!tracker_keys}}- A task is its session's name, `{{key_example}}`: start it with `claude --bg -n {{key_example}}`.
  Branches: `{{branch_pattern}}` from `origin/{{default_branch}}`.
{{?worktree_line}}- Worktrees: `{{worktree_cmd}}`, not EnterWorktree (denied in background sessions). Work in it by absolute path.

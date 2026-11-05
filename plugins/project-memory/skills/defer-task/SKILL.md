---
name: defer-task
description: Use the moment you notice — OR catch yourself mentioning — a bug, missing feature, or refactor that is OUT OF SCOPE of the current task. Invoke it PROACTIVELY on your own findings, not only when asked; capturing it as a task file under .claude/tasks/ IS the action, instead of fixing it now or offering to "file a ticket later". Fires on "latent bug", "out of scope", "while I'm here I noticed", "worth a follow-up", "leave that for now".
---

# Defer Out-of-Scope Task

When you spot something worth fixing that is NOT part of the current task, do not fix it now (scope creep) and do not just mention it (it gets forgotten). Capture it, then continue what you were doing.

## Steps

1. **Categorize**: `features` (new capability), `bugfixes` (something broken), or `refactorings` (works but messy). If none fit, use `bugfixes`.

2. **Dedup**: List `.claude/tasks/<category>/`. If a file already covers the same thing, skip — don't create a duplicate.

3. **Write** `.claude/tasks/<category>/YYYY-MM-DD-<short-slug>.md`:

   ```markdown
   # <one-line title>
   - where: path/to/file.ext:LINE
   - found while: <the task you were actually doing>
   suggested: <one-line fix idea, or "investigate">
   ```

   Use today's date. Slug is 2-5 kebab-case words. Fill `where` with a real `file:line` when you have one.

4. **One line to the user**, e.g. `Noted "<title>" as a deferred bugfix.` Then **return to the original task** — do not start working the deferred item.

## Rules

- Capture is cheap, derailing is not. Never expand the current task to "just fix it too" unless the user asks.
- If the finding IS in scope, this skill does not apply — just fix it.
- One finding = one file. Multiple unrelated findings = multiple files.
- The [graduate](../graduate/SKILL.md) pass resolves these files later (ticket it, fix it or drop it, on the user's yes) and deletes them.

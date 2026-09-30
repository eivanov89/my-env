---
name: cursor-review
description: Run an independent read-only Cursor review of current Git changes or a specified commit when the user asks for a Cursor or external code review. Do not use for ordinary code reviews unless the user requests the external reviewer.
---

# Cursor review

Use this skill only when the user requests an independent Cursor review. By default it reviews tracked changes relative to HEAD and nonignored untracked files in the current Git repository. When the user specifies a commit, it reviews that commit against its first parent (or the empty tree for a root commit), without working-tree changes.

1. Accept the user's requested Cursor model family (`opus`, `sonnet`, or `grok`) and effort (`high` or `medium`), defaulting to `opus high` when omitted. Run `/home/eivanov89/repos/my-env/bin/get_cursor_latest FAMILY EFFORT` to select its current model ID; it queries the current Cursor model list and excludes fast variants. If selection fails, report the error rather than substituting a different model.
2. Tell the user the selected model ID. From the repository being reviewed, run `/home/eivanov89/repos/my-env/bin/cursor-review MODEL_ID` for working-tree changes, or `/home/eivanov89/repos/my-env/bin/cursor-review MODEL_ID COMMIT` when a commit was specified. Let the command finish and retain its exit status. If it fails or says its review is incomplete, report that limitation clearly.
3. Check each substantive finding against the actual diff and surrounding code. Report confirmed findings with severity and file/line, distinguish Cursor's findings from your own analysis, and omit claims you cannot substantiate. If Cursor reports no substantive findings and you find none, say so.

The wrapper runs Cursor in Ask mode with its sandbox enabled. Do not add flags that grant write access, and do not ask Cursor to make fixes. Run this workflow on request; do not invoke it automatically after ordinary code edits.

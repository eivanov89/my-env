---
name: cursor-review
description: Run an independent read-only Cursor review of current Git changes when the user asks for a Cursor or external code review. Do not use for ordinary code reviews unless the user requests the external reviewer.
---

# Cursor review

Use this skill only when the user requests an independent Cursor review. It reviews tracked changes relative to HEAD and nonignored untracked files in the current Git repository.

1. Resolve the requested model family (`opus`, `sonnet`, or `grok`) and effort (`high` or `medium`). Default to `opus high`. Run `/home/eivanov89/repos/my-env/bin/get_cursor_latest` with those arguments; it queries the current Cursor model list, excludes fast variants, and returns one model ID. If selection fails, report the error rather than substituting a different model.
2. Tell the user the selected model ID. Run `/home/eivanov89/repos/my-env/bin/cursor-review MODEL_ID` from the repository being reviewed. Let the command finish and retain its exit status. If it fails or says its review is incomplete, report that limitation clearly.
3. Check each substantive finding against the actual diff and surrounding code. Report confirmed findings with severity and file/line, distinguish Cursor's findings from your own analysis, and omit claims you cannot substantiate. If Cursor reports no substantive findings and you find none, say so.

The wrapper runs Cursor in Ask mode with its sandbox enabled. Do not add flags that grant write access, and do not ask Cursor to make fixes. Run this workflow on request; do not invoke it automatically after ordinary code edits.

---
name: external-review-loop
description: Run bounded review-and-fix loops with a same-model or self=X subagent, followed by an optional external reviewer or reviewer skill. Use when the user requests an iterative review loop; do not invoke automatically after ordinary edits or for a one-shot review.
---

# External review loop

The main agent owns fixes and validation. Reviewers are independent and read-only. Run self-review first, then the external reviewer named in the prompt. Stop on exhaustion and obtain one fresh analysis instead of extending the loop.

## Resolve the request

- Use the main agent's model for self-review unless the prompt specifies `self=X`, where `X` selects the reviewer model. Preserve any explicit effort setting. Do not silently substitute a model if the requested selection is unavailable.
- Allow at most **three self-review attempts**. The external stage also defaults to **three attempts**, but a user-specified attempt count applies only to the external stage. Accept a positive integer; clarify an invalid or ambiguous count before running that stage.
- An attempt is one reviewer invocation, including the initial review and any failed or incomplete invocation. Keep separate counters for the two stages. Fixes, tests, and the final recovery analysis are not review attempts.
- Use the external reviewer, command, or skill specified by the user. If none is specified, run self-review only and report the external stage as omitted. Do not choose an external service on the user's behalf.
- Use the established task requirements and review scope. Otherwise review tracked changes relative to `HEAD` plus nonignored untracked files in the current repository. Establish the baseline once; subsequent attempts must review the updated changes, including fixes, against that baseline. Never keep reviewing an immutable original commit while claiming its fixes were reviewed. If the selected reviewer cannot cover the updated scope, report that limitation.
- Before starting, briefly state the scope, selected reviewers, and attempt budgets. If a required model, tool, or skill is unavailable, report the blocker rather than replacing it or pretending the review occurred. Preserve any completed stage's results.

## Give reviewers clear, independent context

Start a new read-only subagent for every self-review attempt, with no inherited conversation history. With the collaboration tools, use `spawn_agent` with `fork_turns="none"`; omit a model override to inherit the main model, or set it to the requested `self=X` model. If independent subagents are unavailable, report that limitation instead of performing an in-context review under the same label.

Provide a compact review brief containing:

- The user's objective, acceptance criteria, and relevant constraints.
- The repository/workspace location, baseline, current scope, and how to inspect the complete current changes, including untracked files.
- Relevant architecture or invariant references and factual validation results, including checks not run.
- Instructions to inspect surrounding code, report substantive correctness or maintainability issues with severity, file/line, evidence, impact, and a suggested remedy, and explicitly state whether the review was complete.

Ask for an explicit statement when there are no substantive findings. Do not seed the reviewer with the main agent's preferred conclusion or paste the implementation conversation. Reviewers must not edit files, invoke this loop recursively, or delegate fixes. The main agent must not change the review target while a reviewer is inspecting it.

For an external reviewer, read and follow its skill when supplied, retaining its model selection, read-only restrictions, execution requirements, and result checks. For example, a request naming `$cursor-review` uses that skill to obtain each review; this skill owns the enclosing retry loop. Use the same review scope and brief wherever the external interface supports them. Do not invent unsupported arguments or grant the reviewer write access.

## Run each stage

1. Increment the stage's counter and invoke its reviewer on the current changes. Retain the returned findings, completion status, and execution errors.
2. Check every substantive finding against the actual code and requirements. Record which findings are confirmed, resolved, or rejected, with brief reasons. Unsupported findings do not require fixes or another attempt. A previously confirmed issue remains unresolved until there is evidence it was addressed; omission from a later review is not evidence by itself.
3. If the review failed or was incomplete, never treat an empty finding list as success. If the budget is exhausted, perform the recovery analysis below. Otherwise retry only when another invocation can usefully complete the review; if it cannot, stop and report the blocker.
4. If a complete review leaves no unresolved substantive findings and required validation has passed, the stage succeeds. After self-review succeeds, run the external stage if one was specified. After external success, or self-review success without an external reviewer, report the result and stop.
5. If confirmed issues or required validation failures remain and another attempt is available, make the scoped fixes and run relevant checks before requesting the next review. This also applies when a reviewer finds no issues but checks fail. Never label the stage successful while required checks are failing or unavailable. Report a blocker if progress requires missing access, information, or authorization.
6. If confirmed issues or required validation failures remain on the last allowed attempt, **stop before making further fixes** and perform the recovery analysis. This prevents ending the loop with fixes that have not been reviewed.

External-stage fixes stay within that stage. Do not restart self-review, reset a counter, switch reviewers to obtain a favorable verdict, or add an extra confirmation review after exhausting the budget. Self-review exhaustion prevents the external stage from starting.

## Recovery analysis after exhaustion

Start exactly one fresh, read-only analysis subagent with no inherited conversation history, using the main agent's model. Provide the objective, acceptance criteria, current code location and scope, unresolved findings, validation failures, and a concise factual history of attempted fixes. Do not pass the full conversation or prescribe a preferred solution.

Ask it to inspect the current code and identify:

- Simplifications that could remove the source of repeated problems.
- Missing, conflicting, or unenforced invariants.
- Root causes, mistaken assumptions, or gaps in the approach that explain stalled progress.
- Concrete next steps and checks that would demonstrate progress.

This is an analysis pass, not another acceptance review. For exhaustion caused by failed or incomplete reviews, also ask it to identify the review or tooling obstacle. Do not let it edit files, retry the reviewer, or recursively delegate. If this subagent is unavailable or fails, report the limitation without starting a replacement loop.

After receiving the analysis, stop. Do not implement its recommendations, continue to another stage, or initiate further reviews in this run.

## Report to the user

Summarize the scope, reviewers/models, attempts used versus each budget, confirmed issues fixed, and validation performed. Include any rejected substantive findings with concise reasons, unresolved findings with severity and locations, and skipped or incomplete stages. When recovery analysis ran, attribute its conclusions separately and give its recommended next steps.

Clearly distinguish a clean review from budget exhaustion, incomplete review, and blocked validation. Do not claim that an omitted stage ran or that proposed recovery work has been implemented.

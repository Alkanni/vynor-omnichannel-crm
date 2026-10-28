---
name: execute-issue
description: Execute a Ready GitHub issue through the Issue-Driven Development Workflow, from the Ready gate to an open PR, or run post-merge verification when its PR is already merged. Run as /execute-issue <issue-number>.
argument-hint: <issue-number>
disable-model-invocation: true
---

Execute issue #$ARGUMENTS in `Alkanni/vynor-omnichannel-crm`, following the "Issue-Driven Development Workflow" in AGENTS.md. Never merge, deploy, or close the issue.

1. Read the issue, its comments, its Kanban status, and any existing branch or PR. Continue from the last completed stage.
2. If its PR is already merged, run post-merge verification (AGENTS.md §6), post the evidence comment, move the item to `08 Post-Merge Verification`, and report `VERIFIED`. Stop there.
3. Ready gate: continue only if the item is in `03 Ready for Development`, or the owner explicitly told you in this chat to implement this issue (quote that instruction in an issue comment, then move the item to `03`). Otherwise stop with `AWAITING_APPROVAL`.
4. Check WIP and dependencies: no other agent item in `04`/`05`, and every dependency closed. Otherwise stop with `BLOCKED` and explain why.
5. Create the issue branch in its own worktree from an up-to-date `origin/main`, then move the item to `04 In Progress`.
6. Plan and implement strictly within scope. If the work needs more than the issue covers, or a requirement turns out to be ambiguous, stop and report: move the item back to `02 Triage & Analysis`, or add the `blocked` label with the required comment.
7. Move the item to `05 Testing & Validation`. Run the relevant checks, check every acceptance criterion, and review the full diff.
8. Commit, push, and open the PR (`Refs #$ARGUMENTS`). Move the item to `06 Code Review` once CI is green.
9. Finish with the final report (AGENTS.md §7) and status `READY_FOR_REVIEW`, listing the required owner actions.

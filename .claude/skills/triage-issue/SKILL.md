---
name: triage-issue
description: Triage a GitHub issue for the Issue-Driven Development Workflow (analyze it, complete scope, acceptance criteria, risks, and dependencies, move it to 02 Triage & Analysis, then stop at the Ready gate). Run as /triage-issue <issue-number>.
argument-hint: <issue-number>
disable-model-invocation: true
---

Triage issue #$ARGUMENTS in `Alkanni/vynor-omnichannel-crm`, following the "Issue-Driven Development Workflow" in AGENTS.md. Do not create a branch or edit repository files.

1. Read the issue with its comments (`gh issue view $ARGUMENTS --repo Alkanni/vynor-omnichannel-crm --comments`), then search related issues and PRs.
2. Trace the affected code. Start from `.ai-context/README.md` and `index.yaml`, and verify every claim in source.
3. Post one analysis comment in Indonesian that completes what the issue lacks: classification, scope In/Out, acceptance criteria, technical context (verified only; mark assumptions), implementation plan, Impact & Risk, testing requirements, dependencies/blockers, and Definition of Done. List ambiguous requirements as questions; never invent requirements, reproduction results, or root causes.
4. Make sure the issue is in the project and move it to `02 Triage & Analysis`.
5. Stop. Report with status `AWAITING_APPROVAL`, the analysis comment URL, and the decisions the owner must make before moving the issue to `03 Ready for Development`.

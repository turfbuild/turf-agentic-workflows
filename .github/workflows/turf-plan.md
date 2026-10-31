---
description: Plans the infra/ configuration on every pull request that touches it, scans its providers, and posts the plan with the staging approval verdict.
on: pull_request affecting infra/**
environment: staging
engine:
  id: claude
  model: claude-sonnet-5-5
timeout-minutes: 30
permissions:
  contents: read
  pull-requests: read
  id-token: write
concurrency:
  group: turf-staging
  cancel-in-progress: false
imports:
  - shared/turf.md
mcp-servers:
  turf:
    type: http
    url: http://localhost:3000/mcp
    allowed: [skill_deployment, read_skill_file, init, open, up, show, status, cancel]
safe-outputs:
  add-comment:
    max: 1
    hide-older-comments: true
  submit-pull-request-review:
    allowed-events: [COMMENT, REQUEST_CHANGES]
---

# Turf plan

You are the plan reviewer for a pull request. This run **plans only**: it never applies, and it ends by cancelling the convergence it made. The pull request is #${{ github.event.pull_request.number }} in ${{ github.repository }}; its head is checked out in the workspace.

{{#runtime-import .github/workflows/shared/turf-runbook.md}}

## This workflow's ending

Post the report with `add-comment`. Then submit one pull request review: `REQUEST_CHANGES` quoting the rule when the providers rule or the approval rule refused, otherwise a `COMMENT` saying the plan is ready to merge under the staging policy and what merging will do (the counts line).

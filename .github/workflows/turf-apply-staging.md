---
description: Applies infra/ to staging on every push to main that touches it, verifies the fleet through its function URLs, and reports on the merged pull request.
on:
  push:
    branches: [main]
    paths: ["infra/**"]
environment: staging
engine:
  id: claude
  model: claude-sonnet-5-5
timeout-minutes: 30
permissions:
  contents: read
  pull-requests: read
  issues: read
  id-token: write
concurrency:
  group: turf-staging
  cancel-in-progress: false
imports:
  - shared/turf.md
tools:
  # The break-fix rollback reads the merged commit's diff; gh-aw enables the other git
  # commands itself once create-pull-request is configured.
  bash: ["git diff:*", "git show:*"]
pre-agent-steps:
  - name: Deepen the checkout and name the committer, for a break-fix rollback
    run: |
      git fetch --deepen=1 origin || true
      git config user.name turf
      git config user.email turf@users.noreply.github.com
mcp-servers:
  turf:
    type: http
    url: http://localhost:3000/mcp
    headers:
      Authorization: "Bearer ${{ secrets.TURF_MCP_AUTH_TOKEN }}"
    allowed: [skill_deployment, read_skill_file, init, open, up, show, status, cancel, apply, output, state_list]
safe-outputs:
  add-comment:
    max: 2
    target: "*"
  create-issue:
    max: 1
    title-prefix: "[turf staging] "
  create-pull-request:
    max: 1
    draft: false
    base-branch: main
  add-labels:
    allowed: ["turf/applied-staging"]
    target: "*"
---

# Turf apply (staging)

You are deploying autonomously. This run **applies** to the environment the context names, under that environment's approval rule; no person is watching, so every decision is the rule's and every report is for the record. The commit being deployed is checked out in the workspace. If the convergence fails after resources were applied, open the break-fix pull request the runbook's step 8 describes. The label to add on the pull request when the apply completes: `turf/applied-staging`.

{{#runtime-import .github/workflows/shared/turf-runbook.md}}

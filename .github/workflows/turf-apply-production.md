---
description: Applies infra/ to production after a staging apply succeeds on main, under the production approval rule.
on:
  workflow_run:
    workflows: ["Turf apply (staging)"]
    types: [completed]
    branches: [main]
    conclusion: [success]
environment: production
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
  group: turf-production
  cancel-in-progress: false
imports:
  - shared/turf.md
tools:
  # The break-fix rollback reads the merged commit's diff; gh-aw enables the other git
  # commands itself once create-pull-request is configured.
  bash: ["git diff:*", "git show:*"]
pre-agent-steps:
  # gh-aw ends a run green whenever its agent finishes, so a staging run is green even when
  # its convergence failed (a failed verify, say). The staging agent labels the merged pull
  # request only when its apply converged: production starts only on that label.
  - name: Require a converged staging apply of this commit
    env:
      GH_TOKEN: ${{ github.token }}
      HEAD_SHA: ${{ github.event.workflow_run.head_sha }}
    run: |
      PR=$(gh pr list --state merged --search "$HEAD_SHA" --json number --jq '.[0].number // empty')
      if [ -n "$PR" ] && gh pr view "$PR" --json labels --jq '.labels[].name' | grep -qx 'turf/applied-staging'; then
        echo "Staging converged for #$PR."
      else
        echo "::error::Staging has not converged for $HEAD_SHA (no turf/applied-staging label on its pull request); production waits."
        exit 1
      fi
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
  # The label check above fails on purpose whenever staging has not converged; gh-aw would file
  # an "[aw] … failed before agent execution started" issue for each, so that report is off.
  report-failure-as-issue: false
  add-comment:
    max: 2
    target: "*"
  create-issue:
    max: 1
    title-prefix: "[turf production] "
  create-pull-request:
    max: 1
    draft: false
    base-branch: main
  add-labels:
    allowed: ["turf/applied-production"]
    target: "*"
---

# Turf apply (production)

You are deploying autonomously. This run **applies** to the environment the context names, under that environment's approval rule; no person is watching, so every decision is the rule's and every report is for the record. The commit being deployed is checked out in the workspace. If the convergence fails after resources were applied, open the break-fix pull request the runbook's step 8 describes. The label to add on the pull request when the apply completes: `turf/applied-production`.

{{#runtime-import .github/workflows/shared/turf-runbook.md}}

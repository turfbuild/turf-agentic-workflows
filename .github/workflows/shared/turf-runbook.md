## The runbook

You drive Turf through its MCP tools. Load `skill_deployment` first and follow it: one tool call at a time, each result read before the next call, never a dependent call batched with another. Everything specific to this run is in files on disk, not in this prompt.

### 1. Read the run context

Read these files with `cat`:

- `.turf-ci/context.json`: `path` (the configuration directory), `head_sha`, `event`, `environment`, `approval_policy`, `pull_request` (a number, or empty) and `backend` (`bucket`, `key`, `region`).
- `.turf-ci/comments.json`: the comments this workflow family posted earlier on the pull request, newest first; each ends with a fenced block tagged `turf` holding JSON. Empty when there is no pull request.
- `policy/providers.md` and `policy/approval.md`: the standing rules.

Then call `skill_deployment`.

### 2. Register the configuration and scan its providers

`init({ path })`. Read what it reports: `backend`, `workspace`, `variables`, `providers[]`, `readme`.

For every entry in `providers[]`, look up advisories against the provider's own module with the GitHub tool `list_global_security_advisories`: `ecosystem: "go"`, `affects: "<module>@v<version>"`, where the module is `github.com/<namespace>/terraform-provider-<name>` for a source of `registry.opentofu.org/<namespace>/<name>` or `registry.terraform.io/<namespace>/<name>`. Evaluate `policy/providers.md`. Keep a table: provider, version, advisories (count and highest severity, or "none"), verdict.

If any provider is denied, do not `open`: report the table and the refusing rule as step 6 says, and stop.

### 3. Open the workspace

`open({ workspace_name: <the workspace init reports, else "default">, backend_config: { bucket, key, region } })` with the values from the context's `backend`.

If `open` reports a `convergence`, or fails because the state is locked, do not try to clear it: report it (step 6) with the convergence id or the lock id, and stop. The README says how a person unlocks the state.

### 4. Plan

`up({})`. The variables arrive from the server's environment as `TF_VAR_*`; pass none yourself.

- `converged` with nothing applied: report "All resources up to date." and stop.
- `awaiting_approval`: continue.
- Anything else: report the outcome in the skill's words, with the `rounds[]` detail, and stop.

If the `up` call is cut off before it returns, call `status({})` to learn the convergence id, then `apply({ convergence_id })` with no digest: that hands the plan back without approving it. Never call `up` a second time.

### 5. Review the plan

`show({ convergence_id })` and read the plan document (`resource_changes`, `resource_drift`, `output_changes`). Summarize it in the deployment skill's format: the counts line, one line per address with its change symbol, before → after for updates and replacements (never a sensitive value), every entry of `plan.invocations`, and "a second round will follow" when `plan.deferred` is non-zero.

Evaluate `policy/approval.md` for the context's `approval_policy` and write the verdict: `approve` or `refuse`, with the rule that decided it.

If `.turf-ci/comments.json` holds a comment whose turf block has `"kind": "plan"`, compare that block's `changes` and `updates` with this plan's. Say "matches the reviewed plan", or list what differs.

### 6. Report

Every report is one comment, in this order:

1. A heading line: `Turf plan: X to add, Y to change, Z to destroy` (after an apply: `Turf apply: X added, Y changed, Z destroyed`), then `environment: <environment>`.
2. The Providers table.
3. The plan summary from step 5; put the per-address lines in a `<details>` block when there are more than about fifteen, with the counts line outside it.
4. The approval verdict and its rule, and the comparison with the reviewed plan when there was one.
5. After an apply: `Round k: applied N, deferred M` per round, each turf action's progress lines, and the root outputs from `output({})`.
6. A closing fenced block tagged `turf` holding one JSON object:

   ```
   { "kind": "plan" | "apply" | "refused" | "error",
     "head_sha": "...", "environment": "...",
     "add": 0, "change": 0, "destroy": 0, "replace": 0, "deferred": 0,
     "changes": [["<address>", "<create|update|replace|delete|forget>"], ...],
     "updates": { "<address>": { "<attribute>": ["<before>", "<after>"] } },
     "invocations": [["<caller address>", "<event>", "<action address>"], ...],
     "providers": [["<provider>", "<version>", "<verdict>"], ...] }
   ```

   `changes` lists every resource change that is not a no-op, sorted by address. `head_sha` and `environment` come from the context. Keep every value short; this block is what the next run compares against.

Where the comment goes:

- `event` is `pull_request`: the `add-comment` safe output, on the triggering pull request.
- otherwise, when the context's `pull_request` is a number: `add-comment` with that number as its target.
- otherwise: `create-issue`, titled with the heading line.

### 7. After the review

The workflow's own instructions, above this runbook, say whether this run **plans only** or **applies**.

**Plan only.** Post the report, then `cancel({ cause: "plan posted for review; this run holds nothing" })` so the state lock is released. Do that whatever the verdict was.

**Apply.** If the verdict is `refuse`: post the report with `"kind": "refused"`, then `cancel({ cause: "<the rule that refused>" })`, and stop; nothing is applied. If the verdict is `approve`: `apply({ convergence_id, plan_digest })` with the digest `up` returned, then converge:

- `awaiting_approval` (a later round): review it exactly as in step 5 under the same policy; approve it by its own digest, or refuse as above.
- `awaiting_actions`: perform every open request with your tools, as its prompt says, and answer all of them in one `apply({ convergence_id, action_results })`. Say what you did in `progress`, one line each. A step you could not perform, or a check that failed, is `succeeded: false` with an `error` diagnostic saying why. Never report a success you did not observe.
- `converged`: read `output({})`, post the report with `"kind": "apply"`, and add the label the workflow names.
- `failed`, `stalled`, `exhausted`, `stale`, `cancelled`, `error`: post the report with `"kind": "error"` and the detail from `rounds[]`, and `cancel` if the convergence is still paused.
- If an `apply` call is cut off before it returns, call it again with the same arguments: the convergence goes on in the engine, and the second call follows it.

Do not edit any file under the configuration directory. Do not call `destroy`, `taint`, `import` or `invoke`: they are not this workflow's to run.

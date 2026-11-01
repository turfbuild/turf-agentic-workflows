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

- `converged` with nothing applied: report "All resources up to date." and stop. An apply run also adds the label the workflow names, since the environment already matches this commit.
- `awaiting_approval`: continue.
- Anything else: report the outcome in the skill's words, with the `rounds[]` detail, and stop.

If the `up` call is cut off before it returns, call `status({})` to learn the convergence id, then `apply({ convergence_id })` with no digest: that hands the plan back without approving it. Never call `up` a second time.

### 5. Review the plan

`show({ convergence_id })` returns the plan document (`resource_changes`, `resource_drift`, `output_changes`). It is large. When the tool result is saved to a file instead of shown, do not page through it: run this command, exactly as written, with that file's path in place of `<file>`. It prints one line per moved resource, then one per change and per drifted resource with every attribute that differs, before and after (`"(sensitive)"` for a sensitive value, `"(known after apply)"` for one the apply decides), then the output changes. Summarize from its output. The sandbox refuses `jq -f`, so the program is inline.

```sh
jq -c 'def obj: if type == "object" then . else {} end; def marked: [.. | select(. == true)] | length > 0; def diff: (.before | obj) as $b | (.after | obj) as $a | (.after_unknown | obj) as $u | (.before_sensitive | obj) as $bs | (.after_sensitive | obj) as $as | [($b + $a + $u | keys_unsorted[]) as $k | select($u[$k] == true or $a[$k] != $b[$k]) | {($k): (if ($bs[$k] | marked) or ($as[$k] | marked) then "(sensitive)" elif $u[$k] == true then [$b[$k], "(known after apply)"] else [$b[$k], $a[$k]] end)}] | add // {}; (.resource_changes[]? | select(.previous_address) | {moved: .previous_address, to: .address}), (.resource_changes[]? | select(.change.actions != ["no-op"]) | {change: .address, actions: .change.actions} + (if .change.actions == ["create"] or .change.actions == ["delete"] then {} else {diff: (.change | diff)} end) + (if .change.replace_paths then {replace: .change.replace_paths} else {} end)), (.resource_drift[]? | {drift: .address, diff: (.change | diff)}), {outputs: (.output_changes // {} | map_values(.actions) | with_entries(select(.value != ["no-op"])))}' <file>
```

Summarize in the deployment skill's format: the counts line, one line per address with its change symbol, before → after for every attribute that differs in an update or a replacement (never a sensitive value), every entry of `plan.invocations`, one line per moved resource (`moved: <from> → <to>`: a move changes the state's address and nothing in the cloud), and "a second round will follow" when `plan.deferred` is non-zero. For drift, one line per drifted address with the attributes that differ, and say whether it looks like the provider catching up with the last apply (null become empty, a value another resource in this configuration set) or a change made outside the configuration; only the second needs a person's attention.

Evaluate `policy/approval.md` for the context's `approval_policy` and write the verdict: `approve` or `refuse`, with the rule that decided it.

If `.turf-ci/comments.json` holds a comment whose turf block has `"kind": "plan"` **and the same `environment` as this run**, compare that block's `changes` and `updates` with this plan's. Say "matches the reviewed plan", or list what differs. A plan block for another environment is not this run's reviewed plan: the pull request's plan run is staging's, so production is judged on its own, under its own policy, and the report says so.

### 6. Report

Every report is one comment, in this order:

1. A heading line: `Turf plan: X to add, Y to change, Z to destroy` (after an apply: `Turf apply: X added, Y changed, Z destroyed`), then `environment: <environment>`.
2. The Providers table.
3. The plan summary from step 5: the counts line, then the per-address lines in a fenced code block tagged `diff`, each address on a line starting with its change symbol and each attribute that differs on an indented line below it as `attribute: before → after`; a move as `moved: <from> → <to>`. Outside a code block the comment's markdown is escaped and the lines run together. Wrap the code block in a `<details>` block when there are more than about fifteen addresses.
4. The approval verdict and its rule, and the comparison with the reviewed plan when there was one.
5. After an apply: `Round k: applied N, deferred M` per round, each turf action's progress lines, and the root outputs from `output({})`.
6. A closing fenced block tagged `turf` holding one JSON object:

   ```
   { "kind": "plan" | "apply" | "refused" | "error",
     "head_sha": "...", "environment": "...",
     "add": 0, "change": 0, "destroy": 0, "replace": 0, "deferred": 0,
     "changes": [["<address>", "<create|update|replace|delete|forget|move>"], ...],
     "updates": { "<address>": { "<attribute>": ["<before>", "<after>"] } },
     "invocations": [["<caller address>", "<event>", "<action address>"], ...],
     "providers": [["<provider>", "<version>", "<verdict>"], ...] }
   ```

   `changes` lists every resource change that is not a no-op, and every move at its new address, sorted by address. `head_sha` and `environment` come from the context. Keep every value short; this block is what the next run compares against.

Where the comment goes:

- `event` is `pull_request`: the `add-comment` safe output, on the triggering pull request.
- otherwise, when the context's `pull_request` is a number: `add-comment` with that number as its target.
- otherwise: `create-issue`, titled with the heading line.

### 7. After the review

The workflow's own instructions, above this runbook, say whether this run **plans only** or **applies**.

**Plan only.** Post the report, then `cancel({ cause: "plan posted for review; this run holds nothing" })` so the state lock is released. Do that whatever the verdict was.

**Apply.** If the verdict is `refuse`, or step 5 found a reviewed plan for this environment that this plan does not match: post the report with `"kind": "refused"` and the rule, or the difference, as the reason, then `cancel({ cause: "<the rule that refused, or what differs from the reviewed plan>" })`, and stop; nothing is applied. When a reviewed plan for this environment exists, it is the only plan an apply run approves on its own. If the verdict is `approve` and the plan matches, or there was no reviewed plan for this environment: `apply({ convergence_id, plan_digest })` with the digest `up` returned, then converge:

- `awaiting_approval` (a later round): review it exactly as in step 5 under the same policy; approve it by its own digest, or refuse as above.
- `awaiting_actions`: perform every open request with your tools, as its prompt says, and answer all of them in one `apply({ convergence_id, action_results })`. Say what you did in `progress`, one line each. A step you could not perform, or a check that failed, is `succeeded: false` with an `error` diagnostic saying why. Never report a success you did not observe. The sandbox runs only simple shell commands: fetch a URL with one plain `curl -sS -m 15 -w '\n%{http_code}' <url>` per URL, with no loop, pipe, `sleep` or `$(...)`; to retry, call it again.
- `converged`: read `output({})`, post the report with `"kind": "apply"`, and add the label the workflow names.
- `failed`, `stalled`, `exhausted`, `stale`, `cancelled`, `error`: post the report with `"kind": "error"` and the detail from `rounds[]`, and `cancel` if the convergence is still paused. When the run ended `failed` because a turf action answered `succeeded: false` after resources were applied, the merged change is live and broken: go on to step 8.
- If an `apply` call is cut off before it returns, call it again with the same arguments: the convergence goes on in the engine, and the second call follows it.

### 8. Break-fix

Only after an apply run ended `failed` because a turf action reported `succeeded: false` after resources were applied; never after a refusal, a lock, or an error before anything was applied.

**A Terraform configuration is not rolled back by reverting the commit.** Some of its changes have already happened in the state or in the cloud, and restoring the files does not undo them:

- a `moved` block: the state is now at the new address, and the old configuration without the block would plan a create of the old address and a destroy of the new one, a replacement;
- a `removed` or `import` block: the resource has left, or entered, the state;
- a provider or module upgrade: state schemas do not downgrade;
- a delete: the data is gone.

Compose a limited rollback instead. The sandbox allows these git commands by name, so run each as its own call, exactly in this shape, never chained with `&&` and never with options before the subcommand (the committer's name is already configured):

1. Read the commit's diff: `git diff HEAD^ HEAD -- infra/`.
2. Start the branch: `git checkout -b break-fix-<pull_request>` (a flat name: git cannot create `break-fix/…` while a branch named `break-fix` exists).
3. Restore only the files whose change caused the failure, one `git checkout HEAD^ -- <file>` each. Keep every change of the kinds above. Re-read what you restored against what you kept: a kept rename must still be referenced by the restored files.
4. Commit: `git commit -am "Revert the <what> of #<pull_request>: <environment> verify failed"`.
5. Open the pull request with `create_pull_request`: `title` is the commit's first line (`Revert the <what> of #<pull_request>: <environment> verify failed`, never the merged pull request's title), `branch` is the branch from step 2, and the body has (a) what failed, quoting the action's error and your progress lines, with the run's link; (b) what was reverted and what was kept, and why; (c) what merging does (re-deploys the previous <what> to <environment>); (d) that the label was withheld, so production did not start.

If the failing change is itself one of the kinds above, no rollback undoes it: open an issue with `create_issue` instead, titled with the heading line, saying what a person must decide.

Do not edit any file under the configuration directory for this run's own plan or apply; the only edit this runbook allows is step 8's rollback, after the convergence has ended. Do not call `destroy`, `taint`, `import` or `invoke`: they are not this workflow's to run.

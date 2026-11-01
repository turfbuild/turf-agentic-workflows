# Approval rules

Which plans the agent may approve on its own, per environment. The GitHub Environment
names its rule in `TURF_APPROVAL_POLICY`, which the run context carries as
`approval_policy`. The deployment skill's own rules still apply underneath: never a
destroy plan, never a warning you cannot explain, never a plan the providers rule refused.
A move (a `moved` block: a new address in the state, nothing changed in the cloud) is
neither a create nor a delete, and is allowed under both rules.

## `staging`

Approve any plan, including replacements and deletes, **except** one that would:

- destroy the shared execution role (`aws_iam_role.lambda_exec`), or
- delete every function in the fleet (a `fleet_size` of zero cannot pass validation, so
  this means a plan whose deletes leave no `aws_lambda_function.hello` instance).

Growing or shrinking the fleet, patching the greeting, rebuilding a function: all approved.

## `production`

Approve only a plan made of **creates and in-place updates**:

- no replacement (`replace` must be zero),
- no delete of any kind, including a shrink of the fleet,
- the first rollout's creates (the role, the functions, their URLs and permissions) are
  allowed, since nothing exists yet.

Any other plan is **refused**: report it with the rule that refused it, say that a person
has to run the apply for this environment by hand, cancel the convergence, and apply
nothing.

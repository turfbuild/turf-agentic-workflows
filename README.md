# Turf on GitHub Agentic Workflows

An autonomous infrastructure loop: [Turf](https://turf.build) plans and applies a
Terraform configuration from inside
[GitHub Agentic Workflows](https://github.github.com/gh-aw/), and the agent driving it
reviews the plan, checks the providers, approves under a per-environment rule, verifies
the rollout by calling what it deployed, and reports on the pull request.

```
pull request touching infra/   →  turf-plan              plan, scan, verdict → one PR comment, then cancel
merge to main                  →  turf-apply-staging     plan, approve by the staging rule, apply, verify, report
staging succeeded              →  turf-apply-production  the same under the production rule
```

The configuration is a fleet of AWS Lambda functions with public URLs
([`infra/`](infra)); the verify step is a Turf action that fetches every URL and checks its
greeting and environment ([`infra/rollout.turf.hcl`](infra/rollout.turf.hcl)). The rules the agent reads are
prose in [`policy/`](policy). The demonstration environment (two GitHub Environments with
their variables, one AWS role per environment, the state bucket) is Terraform in
[`setup/`](setup), applied locally with Turf.

## How it runs

The agent runs in gh-aw's sandbox and talks to Turf over MCP. Turf's server, engine and
restate-server run on the runner itself, started by
[`.github/workflows/shared/turf.md`](.github/workflows/shared/turf.md) before the agent:
the cloud credentials (an OIDC-minted AWS session for the environment's role) live in
those processes and never in the agent's. Each workflow lists the Turf tools its run may
call, enforced at gh-aw's MCP gateway: a plan run cannot `apply`.

Everything the agent needs to know about a run comes from files on disk:
`.turf-ci/context.json` (environment, approval rule, backend, head commit) and
`.turf-ci/comments.json` (the earlier plan comment to compare against), written by a step
before the agent starts, and the two policy files.

## Bootstrap

1. `aws login` (or an `AWS_PROFILE`) and `export GITHUB_TOKEN=$(gh auth token)` in the
   environment of the Turf engine that will apply `setup/`.
2. `turf -C setup up`. It creates the OIDC provider (set `create_oidc_provider = false` if
   the account has one), the state bucket, a role per environment, and the GitHub
   Environments `staging` and `production` with their variables.
3. `gh secret set ANTHROPIC_API_KEY -R turfbuild/turf-agentic-workflows`: the agent's
   engine is Claude.
4. Open a pull request that changes `infra/`.

## If the state stays locked

The server releases the S3 lock when it stops cleanly. If a job was killed mid-apply, the
lock object is `s3://<bucket>/<environment>/lambda-fleet.tfstate.tflock`; confirm no run
is in progress, then delete it:

```sh
aws s3 rm s3://<bucket>/staging/lambda-fleet.tfstate.tflock
```

## Trademarks

Terraform is a registered trademark of HashiCorp. GitHub and GitHub Actions are trademarks
of GitHub, Inc. AWS and AWS Lambda are trademarks of Amazon.com, Inc. or its affiliates.
Turf is not affiliated with, endorsed by or sponsored by any of them.

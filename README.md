# Turf on GitHub Agentic Workflows

An autonomous infrastructure loop: [Turf](https://turf.build) plans and applies a
Terraform configuration from inside
[GitHub Agentic Workflows](https://github.github.com/gh-aw/), and the agent driving it
reviews the plan, checks the providers, approves under a per-environment policy, verifies
the rollout by calling what it deployed, and reports on the pull request.

**Read the paper.** [Pull Request to Production](https://turf.build/reference-architectures/pull-request-to-production/)
walks this loop through pull requests #7, #5 and #6 of this repository, with the agent's
transcripts (13 pages).

```
pull request touching infra/   →  turf-plan              plan, scan, verdict → one PR comment, then cancel
merge to main                  →  turf-apply-staging     plan, approve by the staging policy, apply, verify, report
staging succeeded              →  turf-apply-production  the same under the production policy
```

The configuration is a fleet of AWS Lambda functions with public URLs
([`infra/`](infra)); the verify step is a Turf action that fetches every URL and checks its
greeting and environment ([`infra/rollout.turf.hcl`](infra/rollout.turf.hcl)). The policies the agent reads are
prose in [`policy/`](policy). The demonstration environment (two GitHub Environments with
their variables, one AWS role per environment, the state bucket) is Terraform in
[`setup/`](setup), applied locally with Turf.

## How it runs

The agent runs in gh-aw's sandbox and talks to Turf over MCP. Turf's server, engine and
restate-server run on the runner itself, started by
[`.github/workflows/shared/turf.md`](.github/workflows/shared/turf.md) before the agent:
the cloud credentials (an OIDC-minted AWS session for the environment's role) live in
those processes and never in the agent's. Each workflow lists the Turf tools its run may
call, enforced at gh-aw's MCP gateway: a plan run cannot `apply`. The server requires a
bearer token, which only the gateway sends. The agent's container can reach the runner, so
without the token the agent could call the server directly and skip that list.

Everything the agent needs to know about a run comes from files on disk:
`.turf-ci/context.json` (environment, approval rule, backend, head commit) and
`.turf-ci/comments.json` (the earlier plan comment to compare against), written by a step
before the agent starts, and the two policy files.

A failed verify halts the apply. The agent reports why, withholds the label production
waits for, and opens a break-fix pull request: a limited rollback, never a wholesale revert
of the commit, since a `moved` block, an import, an upgrade or a delete has already
happened ([the runbook's step 8](.github/workflows/shared/turf-runbook.md)). `turf-plan`
reviews that pull request like any other, provided the repository secret
`GH_AW_CI_TRIGGER_TOKEN` holds a fine-grained token with Contents read and write, as
[gh-aw's docs describe](https://github.github.com/gh-aw/reference/triggering-ci/).

## Use it in your own repository

gh-aw imports resolve across repositories, so one line brings the whole component (Turf
installed, the AWS session minted by OIDC, the engine and the server started before the agent,
stopped and logged after it) into a workflow of your own:

```yaml
imports:
  - turfbuild/turf-agentic-workflows/.github/workflows/shared/turf.md@main
mcp-servers:
  turf:
    type: http
    url: http://localhost:3000/mcp
    headers:
      Authorization: "Bearer ${{ secrets.TURF_MCP_AUTH_TOKEN }}"
    allowed: [skill_deployment, read_skill_file, init, open, up, show, status, cancel]
```

Pin `@main` to a tag or a commit when you want a fixed version; `gh aw compile` caches the
import by commit SHA under `.github/aw/imports/`. The import expects a GitHub Environment on the
job (`environment: staging`, say) that defines `AWS_ROLE_ARN`, `AWS_REGION`, `TF_STATE_BUCKET`,
`TF_STATE_KEY`, `TURF_ENVIRONMENT` and `TURF_APPROVAL_POLICY`, plus any `TF_VAR_*` your
configuration reads, and the repository secret `TURF_MCP_AUTH_TOKEN` (any random string: the
import starts the server with it, and the `headers:` above send it); it plans the configuration at `infra/` and leaves the Turf tool list to your
workflow, so a plan run cannot `apply`. The runbook the agent follows can be pulled at run time
by URL, or copied and edited:

```markdown
{{#runtime-import https://raw.githubusercontent.com/turfbuild/turf-agentic-workflows/main/.github/workflows/shared/turf-runbook.md}}
```

It reads `policy/approval.md` and `policy/providers.md` from your repository: copy the two
files here and rewrite the paragraphs for your environments.

## Bootstrap

1. `aws login` (or an `AWS_PROFILE`) and `export GITHUB_TOKEN=$(gh auth token)` in the
   environment of the Turf engine that will apply `setup/`.
2. `turf -C setup up`. It creates the OIDC provider (set `create_oidc_provider = false` if
   the account has one), the state bucket, a role per environment, and the GitHub
   Environments `staging` and `production` with their variables.
3. `gh secret set ANTHROPIC_API_KEY -R turfbuild/turf-agentic-workflows`: the agent's
   engine is Claude.
4. `gh secret set TURF_MCP_AUTH_TOKEN -R turfbuild/turf-agentic-workflows --body "$(openssl rand -hex 32)"`:
   the bearer token the Turf server requires and the MCP gateway sends.
5. Open a pull request that changes `infra/`.

## If the state stays locked

The server releases the S3 lock when it stops cleanly. If a job was killed mid-apply, the
lock object is `s3://<bucket>/<environment>/lambda-fleet.tfstate.tflock`; confirm no run
is in progress, then delete it:

```sh
aws s3 rm s3://<bucket>/staging/lambda-fleet.tfstate.tflock
```

## Community

Questions, ideas, or your own take on an agentic pipeline: https://turf.build/discord/. A bug in
Turf goes to https://github.com/turfbuild/turf/issues. Release notes by email:
https://turf.build/newsletter/. Everything else: https://turf.build/community/.

## Trademarks

Terraform is a registered trademark of HashiCorp. GitHub and GitHub Actions are trademarks
of GitHub, Inc. AWS and AWS Lambda are trademarks of Amazon.com, Inc. or its affiliates.
Turf is not affiliated with, endorsed by or sponsored by any of them.

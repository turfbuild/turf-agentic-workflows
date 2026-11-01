---
# The Turf component: everything a workflow needs to drive Turf on the runner.
#
# The agent lives in gh-aw's sandbox and reaches Turf only as an HTTP MCP server
# at localhost:3000 (the compiler rewrites that to host.docker.internal). The
# server, the Turf engine and restate-server run on the runner host, started
# here before the MCP gateway comes up, with the cloud credentials in their
# environment and never in the agent's. Each workflow declares `mcp-servers.turf`
# itself, with the tools that run may call, and the bearer token the gateway sends:
#
#   headers:
#     Authorization: "Bearer ${{ secrets.TURF_MCP_AUTH_TOKEN }}"
#
# The token is what makes the tool list hold. The agent's container can reach
# host.docker.internal, so without it the agent could call the server directly
# and skip the gateway. The server requires the token (TURF_MCP_AUTH_TOKEN, a
# repository secret); only this step and the gateway's step get it, never the
# agent's.
engine:
  mcp:
    tool-timeout: 10m
tools:
  timeout: 600
  bash: ["cat:*", "ls:*", "echo:*", "jq:*", "curl:*"]
  github:
    toolsets: [default, security_advisories]
    # gh-aw's built-in tool map misses the advisory tools (list_global_security_advisories,
    # get_global_security_advisory) that GitHub's server exposes, and refuses them by name,
    # so allow the whole server: it runs read-only, limited to the toolsets above.
    allowed: ["*"]
network:
  allowed: [defaults, github, host.docker.internal, "*.lambda-url.us-west-2.on.aws"]
pre-agent-steps:
  - name: Record the run context for the agent
    env:
      GH_TOKEN: ${{ github.token }}
      TURF_ENVIRONMENT: ${{ vars.TURF_ENVIRONMENT }}
      TURF_APPROVAL_POLICY: ${{ vars.TURF_APPROVAL_POLICY }}
      TF_STATE_BUCKET: ${{ vars.TF_STATE_BUCKET }}
      TF_STATE_KEY: ${{ vars.TF_STATE_KEY }}
      AWS_REGION: ${{ vars.AWS_REGION }}
    run: |
      set -euo pipefail
      mkdir -p .turf-ci
      HEAD_SHA=$(git rev-parse HEAD)
      # The pull request this run is about: the triggering one, or the one merged at this commit.
      case "$GITHUB_EVENT_NAME" in
        pull_request) PR=$(jq -r '.pull_request.number' "$GITHUB_EVENT_PATH") ;;
        *) PR=$(gh pr list --state merged --search "$HEAD_SHA" --json number --jq '.[0].number // empty' || true) ;;
      esac
      if [ -n "${PR:-}" ]; then
        gh api "repos/$GITHUB_REPOSITORY/issues/$PR/comments" --paginate \
          | jq '[.[] | select(.user.login == "github-actions[bot]") | select(.body | test("```turf"))
                 | {id, created_at, body}] | sort_by(.created_at) | reverse' > .turf-ci/comments.json
      else
        echo '[]' > .turf-ci/comments.json
      fi
      jq -n --arg path "$GITHUB_WORKSPACE/infra" --arg sha "$HEAD_SHA" --arg event "$GITHUB_EVENT_NAME" \
            --arg env "$TURF_ENVIRONMENT" --arg policy "$TURF_APPROVAL_POLICY" --arg pr "${PR:-}" \
            --arg bucket "$TF_STATE_BUCKET" --arg key "$TF_STATE_KEY" --arg region "$AWS_REGION" \
            '{path: $path, head_sha: $sha, event: $event, environment: $env, approval_policy: $policy,
              pull_request: $pr, backend: {bucket: $bucket, key: $key, region: $region}}' > .turf-ci/context.json
      cat .turf-ci/context.json
  - name: Install Turf and restate-server
    env:
      RESTATE_VERSION: "1.8.1"
      TURF_VERSION: "v1.3.0"
    run: |
      set -euo pipefail
      cd "$RUNNER_TEMP"
      curl -fsSLO "https://github.com/restatedev/restate/releases/download/v${RESTATE_VERSION}/restate-server-x86_64-unknown-linux-musl.tar.xz"
      curl -fsSLO "https://github.com/restatedev/restate/releases/download/v${RESTATE_VERSION}/restate-server-x86_64-unknown-linux-musl.tar.xz.sha256"
      sha256sum -c restate-server-x86_64-unknown-linux-musl.tar.xz.sha256
      tar -xJf restate-server-x86_64-unknown-linux-musl.tar.xz
      sudo install restate-server-x86_64-unknown-linux-musl/restate-server /usr/local/bin/
      restate-server --version
      curl -fsSL https://get.turf.build/install.sh \
        | TURF_RESTATE_SERVER=/usr/local/bin/restate-server sh -s -- --no-brew --no-telemetry --version "$TURF_VERSION"
      "$HOME/.turf/bin/turf-mcp-server" --version
  - name: Mint AWS credentials and start the Turf engine and server
    env:
      TURF_MISE: "off"
      TURF_TELEMETRY: "off"
      TURF_RESTATE_SERVER: /usr/local/bin/restate-server
      TURF_MCP_AUTH_TOKEN: ${{ secrets.TURF_MCP_AUTH_TOKEN }}
      AWS_ROLE_ARN: ${{ vars.AWS_ROLE_ARN }}
      AWS_REGION: ${{ vars.AWS_REGION }}
      TF_VAR_fleet_size: ${{ vars.TF_VAR_fleet_size }}
      TF_VAR_greeting: ${{ vars.TF_VAR_greeting }}
      TF_VAR_name_prefix: ${{ vars.TF_VAR_name_prefix }}
      TF_VAR_aws_region: ${{ vars.TF_VAR_aws_region }}
      TF_VAR_environment: ${{ vars.TF_VAR_environment }}
    run: |
      set -euo pipefail
      : "${AWS_ROLE_ARN:?AWS_ROLE_ARN is empty: is this job running in a GitHub Environment that defines it?}"
      : "${TURF_MCP_AUTH_TOKEN:?TURF_MCP_AUTH_TOKEN is empty: set the repository secret to a random string, as the README Bootstrap describes}"
      # The job's OIDC token buys a one-hour session for this environment's role. The
      # credentials stay in this shell: the engine (providers) and the server (the S3
      # backend) inherit them; the agent container never sees them.
      TOKEN=$(curl -fsS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
        "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" | jq -r .value)
      CREDS=$(aws sts assume-role-with-web-identity --role-arn "$AWS_ROLE_ARN" \
        --role-session-name "turf-${GITHUB_RUN_ID}" --web-identity-token "$TOKEN" \
        --duration-seconds 3600 --query Credentials --output json)
      AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<<"$CREDS")
      AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"$CREDS")
      AWS_SESSION_TOKEN=$(jq -r .SessionToken <<<"$CREDS")
      export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
      unset TOKEN CREDS
      aws sts get-caller-identity --query Arn --output text

      BIN="$HOME/.turf/bin/turf-mcp-server"
      LOGS="$RUNNER_TEMP"
      nohup "$BIN" engine run >"$LOGS/turf-engine.out" 2>&1 &
      ENGINE=$!
      for i in $(seq 1 60); do
        if grep -q 'the local Turf engine is running' "$LOGS/turf-engine.out"; then break; fi
        if ! kill -0 "$ENGINE" 2>/dev/null; then
          echo '::error::the Turf engine exited during startup'
          tail -n 50 "$LOGS/turf-engine.out" "$HOME"/.turf/engine/*.log 2>/dev/null || true
          exit 1
        fi
        sleep 2
      done
      if ! grep -q 'the local Turf engine is running' "$LOGS/turf-engine.out"; then
        echo '::error::the Turf engine did not become ready in 120 s'
        tail -n 50 "$LOGS/turf-engine.out" "$HOME"/.turf/engine/*.log 2>/dev/null || true
        exit 1
      fi
      "$BIN" engine status

      # 0.0.0.0, so the gateway's container reaches it at host.docker.internal; the
      # bearer token in TURF_MCP_AUTH_TOKEN is what keeps everyone else out.
      nohup "$BIN" --transport http --addr 0.0.0.0:3000 >"$LOGS/turf-server.out" 2>&1 &
      SERVER=$!
      for i in $(seq 1 30); do
        if curl -fsS -o /dev/null -X POST http://127.0.0.1:3000/mcp \
             -H "Authorization: Bearer $TURF_MCP_AUTH_TOKEN" \
             -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
             -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}}'; then
          echo "turf-mcp-server is serving /mcp"
          exit 0
        fi
        if ! kill -0 "$SERVER" 2>/dev/null; then break; fi
        sleep 1
      done
      echo '::error::turf-mcp-server did not come up'
      tail -n 50 "$LOGS/turf-server.out" || true
      exit 1
post-steps:
  - name: Stop the Turf server and engine, collect their logs
    if: always()
    run: |
      # SIGTERM, then wait: the server detaches from any convergence and releases the state
      # lock on its way out, and the engine stops restate cleanly. A SIGKILL at job end
      # would leave the S3 lock held.
      pkill -TERM -f 'turf-mcp-server --transport http' || true
      for i in $(seq 1 90); do pgrep -f 'turf-mcp-server --transport http' >/dev/null || break; sleep 1; done
      pkill -TERM -f 'turf-mcp-server engine run' || true
      for i in $(seq 1 60); do pgrep -f 'turf-mcp-server engine run' >/dev/null || break; sleep 1; done
      mkdir -p "$RUNNER_TEMP/turf-logs"
      cp "$RUNNER_TEMP"/turf-*.out "$RUNNER_TEMP/turf-logs/" 2>/dev/null || true
      cp "$HOME"/.turf/engine/*.log "$HOME"/.turf/engine/engine.out "$RUNNER_TEMP/turf-logs/" 2>/dev/null || true
      ls -la "$RUNNER_TEMP/turf-logs" || true
  - name: Upload the Turf logs
    if: always()
    uses: actions/upload-artifact@v4
    with:
      name: turf-logs-${{ github.run_id }}-${{ github.run_attempt }}
      path: ${{ runner.temp }}/turf-logs
      if-no-files-found: warn
---

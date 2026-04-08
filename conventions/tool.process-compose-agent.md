# Convention: Process Compose Agent Interaction (tool.process-compose-agent)

## Overview

Standards for AI agents interacting with a running `process-compose` server
and for authoring `process-compose.yaml` configurations that work reliably
across parallel sessions, worktrees, and agent-driven environments.

## Headless Interface

1. Agents MUST NOT trigger the TUI (Terminal User Interface).
2. Running `process-compose` or `process-compose attach` without a subcommand MUST be avoided as it expects an interactive TTY and will hang the agent.
3. Agents SHOULD use the MCP Server (`process-compose-mcp`) if available for strictly typed tool access. See `tool.cli-coding-agents` for tool configuration paths.
4. Agents MAY use the REST API (default `http://localhost:8080`) by consuming the OpenAPI spec at `/openapi.yaml`.
5. When using the CLI, agents MUST request JSON output using `-o json` for reliable parsing. See `tool.standard-utilities` Rule 1 for `jq` parsing standards.

## Log Reading

6. Agents MUST NOT use the `-f` (follow) flag or attempt to stream logs continuously.
7. Log retrieval MUST be bounded using `--tail` (e.g., `process-compose process logs <name> --tail 100`).
8. Agents MUST strip ANSI color codes to preserve context window space and avoid breaking parsers.
9. The `--log-no-color` flag or `PC_LOG_NO_COLOR=1` environment variable MUST be used for all log commands.
10. Agents MUST NOT grep logs for readiness or health checks.
11. Readiness MUST be determined by polling the API or CLI for the `is_ready` status flag of the managed application service.

## Service Management

12. Agents MUST NOT use OS-level `kill` commands to restart services.
13. Native commands (e.g., `process-compose process restart <name>`) MUST be used to ensure graceful shutdown and respect configured backoffs.
14. After issuing a restart, agents SHOULD wait for the configured backoff period before verifying status.
15. Agents MUST respect the dependency graph; before restarting a foundational service, they SHOULD identify and monitor dependent services.

## Dynamic Port Allocation

16. Service ports MUST be assigned dynamically using `env_cmds` to avoid collisions across parallel sessions, worktrees, and concurrent agents.
17. `env_cmds` values MUST be commands that complete within 2 seconds and produce single-line output.
18. Variables defined in `env_cmds` MUST be referenced with the `$${VAR}` syntax (double dollar sign) inside `process-compose.yaml`. The `${VAR}` syntax resolves shell environment variables at parse time and will produce empty values for `env_cmds`-defined variables.
19. Commands containing `:` characters (e.g., `host:port` addresses) MUST be quoted in YAML to prevent the parser from interpreting the colon as a mapping indicator.
20. Shell hooks in `flake.nix` or `.envrc` MUST NOT set default values for ports that `env_cmds` manages, as pre-existing environment variables take precedence over `env_cmds`.

## Process Compose API Server

21. The process-compose API server SHOULD be disabled with `PC_NO_SERVER=1` in the global `environment` block when the REST API and remote CLI are not needed.
22. When the API server is needed, its port SHOULD also be assigned dynamically via `env_cmds` using the `PC_PORT_NUM` variable, or process-compose SHOULD be started with `--use-uds` to listen on a Unix domain socket instead of TCP.

## Advanced Tactics

23. If connection is refused or unauthorized, agents MUST check for API tokens (`PC_API_TOKEN`) or Unix Domain Sockets (`PC_SOCKET_PATH`). See `process.sandbox-agent` for environment availability.
24. Agents SHOULD use `process-compose project update` to apply configuration changes (YAML or `.env`) without restarting the entire stack. See `process.keystone-development` Rule 11 for platform dev standards.
25. For complex boot failures, agents SHOULD inspect the dependency graph via the `/graph` API or `process-compose graph --format json`.
26. Agents MAY dynamically scale services using `process-compose process scale <name> <count>` if the application supports the `${PC_REPLICA_NUM}` environment variable. See `tool.standard-utilities` Rule 1 for parsing scaled output.

## Golden Example

A `process-compose.yaml` with dynamic port allocation and no API server:

```yaml
version: "0.5"

environment:
  - "PC_NO_SERVER=1"

env_cmds:
  DB_PORT: "shuf -i 10000-60000 -n 1"
  WEB_PORT: "shuf -i 10000-60000 -n 1"

processes:
  database:
    command: "sqld --http-listen-addr 127.0.0.1:$${DB_PORT} --db-path ./data/sqld.db"
    availability:
      restart: on_failure

  web:
    command: "pnpm dev --port $${WEB_PORT}"
    environment:
      - "DB_PORT=$${DB_PORT}"
      - "DATABASE_URL=http://127.0.0.1:$${DB_PORT}"
    depends_on:
      database:
        condition: process_started
    availability:
      restart: on_failure
```

An agent diagnosing a failing service and applying a fix:

    # 1. Check status (JSON)
    process-compose process list -o json

    # 2. Fetch last 50 lines of logs without colors
    process-compose process logs backend --tail 50 --log-no-color

    # 3. Apply a fix to the .env file
    echo "DB_URL=postgres://localhost:5432/db" >> .env

    # 4. Update the project configuration dynamically
    process-compose project update

    # 5. Verify readiness
    process-compose process list -o json | jq '.[] | select(.name=="backend") | .is_ready'

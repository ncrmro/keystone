
## Cloudflare Workers

## Deployment

1. Workers MUST be deployed via `wrangler` from the project's dev shell.
2. Worker configuration MUST live in `wrangler.toml` at the project root.
3. Secrets MUST NOT be hardcoded — use `wrangler secret put` or environment-specific vars in `wrangler.toml`.

## Development

4. Local development SHOULD use `wrangler dev` for testing.
5. Workers MUST handle errors gracefully and return appropriate HTTP status codes.
6. Workers SHOULD log structured JSON for observability.

## Bindings

7. KV, D1, R2, and other bindings MUST be declared in `wrangler.toml`.
8. Binding names SHOULD be descriptive and uppercase (e.g., `SESSIONS_KV`, `ASSETS_BUCKET`).

## Limits

9. Workers MUST respect the CPU time limit (10ms free, 30s paid) — avoid synchronous heavy computation.
10. Response bodies SHOULD be streamed for large payloads.

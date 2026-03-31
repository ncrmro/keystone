# Convention: Headscale ACL generation (os.headscale-acl)

Standards for auto-generating Headscale ACL rules from keystone service
topology. ACL rules, tag ownership, and service tags are derived
declaratively from `keystone.services` and `keystone.hosts`.

## Tag naming

1. Service tags MUST follow the pattern `tag:svc-{service}` for server
   roles and `tag:svc-{service}-{role}` for specialized workers (e.g.,
   `tag:svc-immich`, `tag:svc-immich-ml`).
2. Infrastructure tags (`tag:server`, `tag:agent`, `tag:ocean-ingress`)
   remain manually assigned in static ACL config.
3. Service tags MUST be auto-registered by the service module via
   `keystone.os.tailscale.tags`.

## Identity model

4. In Headscale, a node is either **user-owned** (e.g., `ncrmro@`) or
   **tag-owned**. Adding tags converts a node from user-owned to
   tag-owned, which strips the user identity.
5. Client-role hosts (`keystone.hosts.*.role == "client"`) MUST NOT
   receive service tags. Tags would strip their user identity and break
   admin access rules like `ncrmro@ -> *:*`.
6. Server-role and agent-role hosts MAY receive service tags because they
   are already tag-based (`tagged-devices` user in Headscale).
7. ACL destinations for client-role workers MUST use `{primaryUser}@:{port}`
   instead of `tag:svc-*:{port}`.

## Auto-generation flow

8. Service modules (e.g., `immich.nix`) MUST register their tailscale
   tags on server/agent hosts via `keystone.os.tailscale.tags`.
9. `keystone.services.generatedACLRules` and
   `keystone.services.generatedTagOwners` MUST be populated in
   `modules/services.nix` based on the service topology.
10. The headscale host (mercury) consumes these via
    `keystone.headscale.aclRules` and
    `keystone.headscale.generatedTagOwners`, which are merged with
    static rules by the `headscale-acl` import module.
11. Tag owners for auto-generated tags MUST be set to `{primaryUser}@`,
    derived from the first key in `keystone.os.users`.
12. Ports in ACL rules MUST be derived from the service definition, not
    hardcoded in the ACL generation logic.

## Golden example

Given this service topology:

```nix
keystone.services = {
  immich.host = "ocean";            # role = "server" -> gets tag:svc-immich
  immich.workers = [ "workstation" ]; # role = "client" -> stays user-owned
};
```

The generated ACL rule is:

```json
{
  "src": ["tag:svc-immich"],
  "dst": ["ncrmro@:3003"]
}
```

If the worker were a server-role host instead:

```json
{
  "src": ["tag:svc-immich"],
  "dst": ["tag:svc-immich-ml:3003"]
}
```

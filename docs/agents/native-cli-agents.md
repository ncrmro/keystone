---
title: Native CLI agents
description: How Keystone generates native agent definitions for Claude Code, Gemini CLI, Codex, and OpenCode
---

# Native CLI agents

Keystone can project OS-agent identities and archetype specialists into each
supported coding CLI through that tool's native custom-agent format.

This is the deep reference for:

- what Keystone generates,
- how OS agents differ from archetype agents,
- which launch surface each CLI actually supports, and
- what Keystone normalizes vs what Keystone does not attempt to normalize.

For the normative contract, see [Spec: Native CLI agent launch surfaces](../../specs/006-native-cli-agent-launch-surfaces.md).

## Concepts

Keystone generates two kinds of agents:

- **OS agents** are concrete identities such as `drago`. They carry real
  Keystone context like host, notes path, and archetype.
- **Archetype agents** are role-specialized agents such as `engineer` or
  `product`. They represent a role, not a concrete principal.

The naming rule is:

- preserve the bare OS-agent name when the target CLI allows it, and
- preserve the bare archetype name when the target CLI allows it, unless there
  is a collision that requires disambiguation.

Keystone does not invent a fake universal agent flag. It emits native files and
expects each CLI to use its own documented agent-selection surface.

## Source of truth

The generator reads the shared manifest at:

- `~/.config/keystone/agent-assets.json`

That manifest is produced from the Keystone Nix configuration and provides the
data used to generate CLI-native assets, including:

- OS-agent name
- archetype
- notes path
- host metadata
- resolved capabilities

The generation step is implemented in:

- [`modules/terminal/scripts/keystone-sync-agent-assets.sh`](../../modules/terminal/scripts/keystone-sync-agent-assets.sh)

## What Keystone generates

For each supported CLI, Keystone writes native agent definitions in that tool's
own discovery path.

| CLI | Native path | Generated format | Native launch surface |
| --- | --- | --- | --- |
| Claude Code | `~/.claude/agents/*.md` | Markdown with frontmatter | `claude --agent <name>` and Claude's native agent UI |
| Gemini CLI | `~/.gemini/agents/*.md` | Markdown with frontmatter | Gemini's native subagent flow and explicit `@name` invocation |
| Codex | `~/.codex/agents/*.toml` | TOML custom-agent files | Codex native custom-agent workflow |
| OpenCode | `~/.config/opencode/agents/*.md` | Markdown agent files | OpenCode primary-agent or `@name` subagent flow |

Keystone also continues to generate:

- shared MCP configuration,
- Keystone workflow commands and skills, and
- canonical instruction files such as `~/.keystone/AGENTS.md`.

Those are related, but separate from native agent definition generation.

## OS agents vs archetypes

An OS-agent definition includes concrete Keystone identity context:

- agent name
- notes root
- host
- resolved archetype

An archetype definition includes only role context:

- archetype name
- archetype conventions
- no impersonated notebook identity
- no host-specific principal switch

This distinction matters because Keystone must keep durable notebook routing
correct:

- launching `drago` can point workflows at Drago's notes root,
- launching `engineer` must not silently impersonate Drago or any other agent.

## Native launch behavior

Keystone follows the upstream CLI contract instead of flattening everything into
one fake interface.

### Claude Code

- Keystone generates `.claude/agents/<name>.md`.
- Concrete OS agents can keep direct names like `drago`.
- Archetypes can keep names like `engineer` when no collision exists.
- Claude's documented session-wide surface is the model here:
  `claude --agent <name>`.

Upstream docs:

- <https://code.claude.com/docs/en/sub-agents>

### Gemini CLI

- Keystone generates `.gemini/agents/<name>.md`.
- Gemini uses native subagent behavior and explicit `@name` forcing.
- Keystone must not document a fake `gemini --agent <name>` flow unless Gemini
  documents one.

Upstream docs:

- <https://geminicli.com/docs/core/subagents/>

### Codex

- Keystone generates `.codex/agents/<name>.toml`.
- Keystone uses Codex custom-agent definitions, not a Keystone wrapper.
- Keystone must not claim `codex --agent <name>` unless Codex documents that
  exact surface.

Upstream docs:

- <https://developers.openai.com/codex/subagents>

### OpenCode

- Keystone generates `.config/opencode/agents/<name>.md`.
- Keystone relies on OpenCode's native primary-agent and subagent model.
- Keystone must not invent shortcut flags like `--engineer` or `--product`.

Upstream docs:

- <https://opencode.ai/docs/agents/>

## What Keystone does not normalize

Keystone does not try to hide real tool differences.

It does not:

- invent bespoke flags such as `--engineer` or `--product`,
- promise `--agent` on tools that do not document that surface,
- replace upstream binaries with wrapper shims whose main purpose is rewriting
  agent semantics, or
- blur the distinction between OS-agent identity and archetype role.

Repo-local helpers may still exist for other reasons, such as worktree bootstrapping
or spec setup, but they must preserve the underlying CLI's native agent behavior.

## Related implementation details

- [Agents](agents.md) covers human-side tooling like `agentctl`.
- [OS agents](os-agents.md) covers agent provisioning and runtime behavior.
- [CLI coding agents](../terminal/cli-coding-agents.md) covers shared MCP,
  commands, and skills across the coding CLIs.
- [Terminal module](../terminal/terminal.md) provides the user-facing terminal
  overview.

## Development mode

In development mode, Keystone writes generated assets into the live checkout so
they appear as repo diffs instead of immutable Home Manager symlinks.

For native CLI agents, that means:

- changes to archetypes or conventions regenerate native agent files,
- generated assets can be reviewed in Git before they are committed, and
- the same manifest drives both locked-mode and dev-mode generation.

For PR-visible previews, render the generated assets into a repo directory:

```bash
ks sync-agent-assets --output-root tests/fixtures/agents
```

That preview mode uses the same generator, but writes into a reviewable
directory instead of the live CLI home paths. The fixture tree can include
native agents, commands, skills, and generated instruction files for each CLI.

## Collision handling

If a concrete OS-agent name and an archetype name would collide in a target CLI:

- the concrete OS agent keeps the bare name, and
- the non-OS-agent variant is disambiguated.

This preserves the most important ergonomic contract:

```bash
claude --agent drago
```

That bare OS-agent form should stay stable whenever the target CLI permits it.

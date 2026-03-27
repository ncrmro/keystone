# Convention: Project Navigation (process.project-navigation)

Standards for how agents effectively navigate, discover requirements, and inspect
information within a project to minimize context usage and time-to-discovery.

## Requirement Discovery

1. The project-level agent configuration file (e.g., `AGENT.md`, `CLAUDE.md`, or `GEMINI.md`) MUST declare the **Requirement Prefix** (e.g., `SPEC-`, `REQ-`, `TODO-`) used throughout the codebase.
2. Agents MUST use `rg` (ripgrep) with the declared Requirement Prefix to identify relevant files and sections when investigating a task or bug.
3. When searching for requirements in git history, agents MUST use `git grep` or `git log -G` with the Requirement Prefix.

## Structured Data Inspection

4. Agents MUST use `jq` or `yq` to inspect JSON and YAML files respectively, rather than reading the entire file content.
5. Before reading an unknown structured file, agents MUST inspect its top-level keys using `yq 'keys' <file>` or `jq 'keys' <file>` to understand the schema.
6. For large structured files, agents MUST use filtered queries to extract only the necessary nodes (e.g., `yq '.services.web' docker-compose.yml`) to keep the context window lean.

## Efficient Filesystem Exploration

7. Agents SHOULD check the size of a file using `ls -lh <file>` before attempting to read it in full.
8. If a file exceeds 50KB, agents MUST NOT read it in its entirety; they MUST use `read_file` with `start_line` and `end_line` or `grep` to extract relevant sections.
9. Agents SHOULD use `glob` or `list_directory` to map the directory structure before exploring file contents to avoid "blind" reads.

## LSP and Documentation

10. Source code MUST be documented using language-standard conventions (e.g., Python Docstrings, JSDoc, Rustdoc) to enable LSP-based discovery.
11. Agents SHOULD utilize available Language Servers (e.g., `nil` for Nix, `rust-analyzer` for Rust) via provided tools to perform cross-reference lookups and symbol searches.
12. When investigating unfamiliar symbols, agents SHOULD use LSP features like "Go to Definition" or "Find References" before resorting to manual `rg` searches.

## Golden Example

### Finding Requirements for a Feature

The agent needs to find the spec for "TPM Unlock". `AGENT.md` says the prefix is `SPEC-`.

```bash
# Fast discovery of relevant files
rg "SPEC-.*TPM Unlock"
```

### Inspecting a Large Configuration File

The agent needs to know the memory limit for the `db` service in a 2000-line `docker-compose.yml`.

```bash
# 1. Check file size (it's large)
ls -lh docker-compose.yml

# 2. Inspect keys to confirm structure
yq 'keys' docker-compose.yml

# 3. Extract exactly what is needed
yq '.services.db.deploy.resources.limits.memory' docker-compose.yml
```

### Navigating Code with LSP

Instead of `rg "my_function"`, use LSP to find where it's defined and used.

```bash
# (Conceptual) Use LSP tool to find definition
lsp_definition path/to/file.py --line 42 --char 10
```

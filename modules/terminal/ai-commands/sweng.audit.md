---
description: Start the sweng/audit DeepWork workflow to check dev environment health
argument-hint: <repository path>
---

Start the sweng/audit DeepWork workflow to check dev environment health.

Use the DeepWork MCP tools to start the workflow:
- job_name: "sweng"
- workflow_name: "audit"
- goal: "$ARGUMENTS" (path to the repository to audit, defaults to current working directory)

Follow the workflow instructions returned by the MCP server. This audits the repo against keystone conventions: devshell setup (flake.nix, .envrc, direnv), git conventions (.gitignore, CODEOWNERS, commit format), TDD infrastructure, and CI pipeline health.

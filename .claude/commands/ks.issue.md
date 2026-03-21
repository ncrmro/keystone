Start the keystone_system/issue DeepWork workflow to write a keystone spec.

Use the DeepWork MCP tools to start the workflow:
- job_name: "keystone_system"
- workflow_name: "issue"
- goal: "$ARGUMENTS" (use the user's arguments as the feature description)

Follow the workflow instructions returned by the MCP server. This produces a keystone spec with RFC 2119 requirements, user story, and ASCII architecture diagrams.

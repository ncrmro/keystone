# Choose Research Platforms

## Objective

Ask the user where they would like deep research to be conducted. This step determines which AI platforms and tools will be used for the research gathering phase.

## Task

### Process

1. **Present platform options to the user**

   Use the AskUserQuestion tool with multiSelect enabled to let the user choose one or more platforms:

   - **Local only** - Use Claude's built-in WebSearch and WebFetch tools. Fast, stays in this session, good for quick/standard depth.
   - **Gemini Deep Research** - Open Gemini in Chrome and use its Deep Research feature. Best for comprehensive, multi-source investigations. Note: Gemini will ask clarifying questions and show a research plan before starting.
   - **ChatGPT Deep Research** - Open ChatGPT in Chrome and use its research capabilities. Good for thorough web research with citations. Note: ChatGPT may ask clarifying questions before starting deep research.
   - **Grok** - Open Grok (X/Twitter) in Chrome. Best for real-time information and social media context.
   - **Perplexity** - Open Perplexity in Chrome. Excellent for research with inline citations and source quality.

   **Parallel research**: If the user selects multiple platforms, research will be conducted on all of them in parallel (using separate browser tabs) and results synthesized together. This provides broader coverage and cross-validation.

2. **Record the platform selection**

   Create a `platforms.md` file in the research directory that documents:
   - Which platforms were selected
   - Whether parallel research mode is enabled (2+ platforms)
   - Any platform-specific instructions or preferences noted by the user

3. **Handle browser automation context**

   If any external platform is selected (not "Local only"):
   - Verify Claude in Chrome MCP tools are available by checking tabs_context_mcp
   - If not available, warn the user and suggest falling back to "Local only"
   - If available, confirm browser automation is ready for the gather step

## Output Format

### research/[topic_slug]/platforms.md

```markdown
# Research Platforms

**Selected**: [comma-separated list of platforms]
**Parallel Mode**: [Yes if 2+ platforms, No otherwise]
**Date**: [YYYY-MM-DD]

## Platform Details

### [Platform Name]
- **Type**: [local | browser-automated]
- **Best for**: [what this platform excels at]
- **Notes**: [any user-specified preferences or instructions]

[Repeat for each selected platform]

## Execution Plan

[Brief description of how the gather step should use these platforms:
- For local only: use WebSearch and WebFetch
- For single external: open that platform, conduct research, extract findings
- For parallel: open multiple tabs, conduct research in each, then synthesize]
```

## Quality Criteria

- At least one platform is selected
- Selection is confirmed by the user via AskUserQuestion
- If external platforms selected, browser automation availability is verified
- platforms.md is created in the research directory (or a temp location if scope hasn't run yet)
- Execution plan clearly describes how platforms will be used in gather step


## Context

This is the first step before scoping. By choosing platforms upfront, the user controls the research methodology. External AI platforms like Gemini Deep Research can provide more thorough web crawling and synthesis than local tools alone. Parallel research across multiple platforms increases coverage and allows cross-validation of findings.

**Important: Clarifying Questions Flow**

When using Gemini or ChatGPT for deep research, these platforms follow a two-phase approach:
1. **Initial review**: After receiving the research question, they analyze it and may ask clarifying questions to refine scope, understand intent, or identify specific angles to explore.
2. **Approval gate**: They present a research plan or summary of understanding and ask for confirmation before beginning the actual deep research.

This mirrors good research practice — clarify the question before diving in. During the gather step, be prepared to answer these clarifying questions (consulting the user if needed) and approve the research plan before the platform begins its work.

The gather step will read this file to know which tools and platforms to use for source collection.

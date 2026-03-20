# Define Research Scope

## Objective

Define the research question, classify the research type and depth level, and detect whether this research is associated with an existing project. Output a `scope.md` file that guides all subsequent steps.

## Task

### Process

1. **Gather inputs using structured questions**

   Ask structured questions using the AskUserQuestion tool to collect:

   - **Topic**: The research question or subject. If triggered from digest_notes, this is pre-filled from the parsed research topic.
   - **Type**: One of: science, business, competitive, market, technical.
   - **Depth**: One of:
     - **Quick** - Web search summary, 3+ sources, key findings only
     - **Standard** - Multi-source web research, 5+ diverse sources, synthesized analysis
     - **Deep** - Thorough investigation, 8+ sources, includes browser automation for interactive research
   - **Project** (optional): An associated project tag (e.g., `#Catalyst`, `#Meze`).

2. **Detect project association**

   Check if the topic relates to a known project:
   - Read `projects/README.md` for active project tags and descriptions
   - If the user provided a project tag, validate it exists
   - If no tag provided, check if the topic keywords match a project's description or domain
   - If a match is found, confirm with the user

3. **Generate the topic slug**

   Create a filesystem-safe slug from the topic:
   - Lowercase, hyphens for spaces, no special characters
   - Keep it short but descriptive (e.g., `nix-remote-builders`, `meal-plan-market-size`)

4. **Create the research directory and scope file**

   - Create `research/[topic_slug]/` directory
   - Write `research/[topic_slug]/scope.md`

## Output Format

### research/[topic_slug]/scope.md

```markdown
# Research Scope: [Topic Name]

**Slug**: [topic_slug]
**Type**: [science | business | competitive | market | technical]
**Depth**: [quick | standard | deep]
**Project**: [#ProjectTag or N/A]
**Date**: [YYYY-MM-DD]

## Research Question

[Clear, specific statement of what this research aims to answer]

## Sub-Questions

- [Specific sub-question that helps answer the main question]
- [Another sub-question]
- [Another sub-question]

## Search Strategy

[Brief outline of where to look based on type and depth:
- For science: academic databases, arxiv, research institutions
- For business: industry reports, company filings, market data
- For competitive: competitor websites, product reviews, pricing pages
- For market: market reports, consumer surveys, trend data
- For technical: documentation, benchmarks, architecture comparisons]

## Project Context

[If associated with a project: why this research matters to the project's goals.
If N/A: omit this section]
```

## Quality Criteria

- Topic is clearly defined as a specific, answerable research question
- Type is one of the five valid categories
- Depth level is set and appropriate for the question
- Topic slug is filesystem-safe and descriptive
- Sub-questions break the main question into researchable parts
- Search strategy is tailored to the type and depth
- Project association is validated against `projects/README.md` if provided


## Context

This is the foundation step. The scope file guides the gather step on what to search for, the synthesize step on what question to answer, and the report step on how to structure the output. A well-defined scope prevents wasted effort in later steps.

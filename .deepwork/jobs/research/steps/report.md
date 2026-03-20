# Write Research Report

## Objective

Produce the final `README.md` following the research_report doc spec, create a `bibliography.md` if external sources were cited, and create a project symlink if a project was specified in the scope.

## Task

### Process

1. **Read all inputs**

   - Read `research/[topic_slug]/scope.md` for metadata (type, depth, project, question)
   - Read `research/[topic_slug]/analysis.md` for synthesized findings and insights
   - Read `research/[topic_slug]/sources.md` for source details and URLs
   - Read the doc spec at `.deepwork/doc_specs/research_report.md` for the required structure

2. **Write README.md**

   Follow the research_report doc spec structure. The report must satisfy these doc spec quality criteria:

   - **Clear Scope**: Begin with the research question, type, depth level
   - **Structured Findings**: Organize into logical sections with headers, each finding citing sources
   - **Key Takeaways**: 3-5 actionable takeaways drawn from the analysis
   - **Source Attribution**: All claims reference sources with inline markdown links
   - **Project Context**: If project-associated, reference the tag and explain relevance

   Write for the target audience (researcher and project stakeholders). Be concise — the analysis file has the detailed reasoning; the README is the polished deliverable.

3. **Create bibliography.md (if sources were cited)**

   Only create this file if external sources were used. Follow the doc spec at `.deepwork/doc_specs/research_bibliography.md`:

   - **Complete Entries**: Title, author/publisher, URL, date accessed, 1-2 sentence annotation
   - **Categorized Sources**: Group by type (academic, industry report, news, docs, blog) or topic
   - **Consistent Format**: Same citation format throughout

   Pull source details from `sources.md` and organize them into the bibliography structure.

4. **Create project symlink (if applicable)**

   If scope.md specifies a project tag:

   ```bash
   # Create the project's research directory if it doesn't exist
   mkdir -p projects/[ProjectName]/research

   # Create a relative symlink
   ln -s ../../../research/[topic_slug] projects/[ProjectName]/research/[topic_slug]
   ```

   Use the project name as it appears in `projects/README.md` (matching the folder name under `projects/`). Verify the symlink resolves correctly.

## Output Format

### research/[topic_slug]/README.md

Follow the structure from `.deepwork/doc_specs/research_report.md`:

```markdown
# Research: [Topic Name]

## Overview

**Type**: [science | business | competitive | market | technical]
**Depth**: [quick | standard | deep]
**Project**: [#ProjectTag or N/A]
**Date**: [YYYY-MM-DD]

## Research Question

[Clear statement of what this research aimed to answer]

## Findings

### [Finding Area 1]

[Findings with inline citations like [Source Title](url)]

### [Finding Area 2]

[Findings with inline citations]

## Key Takeaways

1. [Actionable takeaway]
2. [Actionable takeaway]
3. [Actionable takeaway]

## Related

- [Links to related research, project files, or external resources]
- [Link to bibliography if created: [Bibliography](bibliography.md)]
```

### research/[topic_slug]/bibliography.md (conditional)

Follow the structure from `.deepwork/doc_specs/research_bibliography.md`:

```markdown
# Bibliography: [Topic Name]

## Sources

### [Category, e.g., Academic / Industry Reports]

1. **[Title]** - [Author/Publisher]
   - URL: [link]
   - Accessed: [YYYY-MM-DD]
   - [1-2 sentence annotation]
```

## Quality Criteria

- README.md follows the research_report doc spec structure exactly
- All findings cite sources with inline markdown links
- Key takeaways section has 3-5 actionable conclusions
- Bibliography.md exists if external sources were cited, with categorized annotated entries
- If a project was specified, a symlink exists at `projects/[ProjectName]/research/[topic_slug]` and resolves correctly
- Related section links to bibliography and any associated project files


## Context

This is the final step. The README.md is the primary deliverable — it should stand on its own as a useful document. The bibliography provides provenance for anyone wanting to verify or extend the research. The project symlink ensures the research is discoverable from the project directory.

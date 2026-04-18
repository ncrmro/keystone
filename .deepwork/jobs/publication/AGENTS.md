# DeepWork Job: publication

## Job Overview

Transform research, projects, spikes, or ideas into polished publications (blog posts, technical articles, internal docs, or tutorials) with audience-specific tone and comprehensive quality validation.

## Writing Style

All text generated for Nicholas must follow the writing style guide at `WRITING_STYLE.md` (vault root). This covers voice, vocabulary texture, scientific metaphors, tone calibration, anti-patterns, and structural directives. Run the checklist in section 8 before finalizing any output.

## Job-Specific Context

### Source Material Types

This job works best with:
- **Projects**: Existing project documentation, READMEs, implementation notes
- **Spikes**: Technical investigations with README files documenting findings
- **Research**: Compiled research notes from the `research` job
- **Ideas**: Raw concepts that need to be developed into full content

Provide the path to the source material when running `research_and_scope` step.

### Publication Organization

Outputs use slug-based directories in `workflow/publications/[slug]/`:
- `workflow/publications/[slug]/scope.md` - Publication scope and requirements
- `workflow/publications/[slug]/outline.md` - Structured content outline
- `workflow/publications/[slug]/draft.md` - First complete draft
- `workflow/publications/[slug]/README.md` - Polished, publication-ready document (displays automatically)
- `workflow/publications/[slug]/metadata.yml` - Publication metadata and quality review status

The slug is derived from the publication title (lowercase, hyphens, no special chars).
Example: "Budget-Aware Agent Orchestration" → `budget-aware-agent-orchestration`

### Publication Types

The job supports five publication types:
- **blog** (800-2000 words): Public-facing, engaging
- **announcement** (500-800 words): Product launch press release using Amazon working-backwards format. See `../press_release/templates/working-backwards-template.md` for the template. Key constraints: under one page, problem before solution, two quotes (maker + customer), no jargon.
- **internal**: Team-focused, context-aware, concise
- **technical_article** (1500-3000 words): Deep technical dive
- **tutorial**: Step-by-step, beginner-friendly

### Tone Selection Guide

**Professional/Terse**:
- Best for: Business communications, formal documentation, enterprise content
- Characteristics: Concise, authoritative, fact-focused
- Example use: Internal company documentation, formal proposals

**Funny/Facetious**:
- Best for: Public blog posts, engaging technical content, personal writing
- Characteristics: Humorous, playful, relatable while still informative
- Example use: Developer blog posts, technical storytelling

**Academic/Technical**:
- Best for: Research papers, deep technical articles, rigorous analysis
- Characteristics: Precise terminology, detailed methodology, formal structure
- Example use: Technical deep-dives, research documentation

### Audience Targeting

**Technical Practitioners** (developers, engineers):
- Include code examples and implementation details
- Use technical jargon appropriately
- Provide architecture diagrams and system designs
- Focus on "how" not just "what"

**General Tech Audience** (tech-interested non-specialists):
- Explain concepts with analogies
- Limit jargon, define necessary terms
- Focus on "what" and "why"
- Use relatable, non-technical examples

**Internal Team** (colleagues with shared context):
- Reference internal systems and organizational context
- Skip basic explanations for familiar concepts
- Focus on practical team application
- Can use internal terminology freely

## Quality Standards

Publications must meet all 6 quality criteria from `.deepwork/doc_specs/publication.md`:

1. **Engaging Opening**: Strong hook, clear value proposition, no generic intros
2. **Clear Structure**: Logical flow, clear headings, smooth transitions
3. **Tone Consistency**: Selected tone maintained throughout
4. **Audience Appropriateness**: Depth and language match audience expertise
5. **Actionable Takeaways**: Clear conclusions, next steps, resources
6. **Verified Citations**: All external links tested and confirmed to exist

The `review_publication` step has quality validation hooks that enforce these criteria.

## Common Workflows

### Blog Post from Spike
```bash
/publication                           # Full workflow
# Inputs:
# - source_material: workflow/spikes/[spike_name]/README.md
# - target_audience: general_tech
# - publication_tone: funny
# - publication_type: blog
```

### Technical Article from Project
```bash
/publication
# Inputs:
# - source_material: projects/[project_name]/README.md
# - target_audience: technical_practitioners
# - publication_tone: academic
# - publication_type: technical_article
```

### Internal Doc from Research
```bash
/publication
# Inputs:
# - source_material: research/[topic]/README.md
# - target_audience: internal_team
# - publication_tone: professional
# - publication_type: internal
```

## Tips for Success

1. **Choose the right source**: Publications work best when source material already has substantial content. Don't try to create a blog post from a 2-line idea.

2. **Match tone to audience and platform**: Funny tone works great for personal blogs but may not suit enterprise documentation.

3. **Trust the review step**: The quality validation hooks will iterate until all criteria pass. Don't skip the review step.

4. **Use metadata file**: The `metadata.yml` output documents publication status and quality review results for future reference.

5. **Iterate on outline**: If the outline doesn't feel right, you can re-run `create_outline` step before drafting.

## Job Management

This folder is managed using the `deepwork_jobs` slash commands:

- `/deepwork_jobs.define` - Modify the job.yml specification
- `/deepwork_jobs.implement` - Regenerate step instruction files
- `/deepwork_jobs.learn` - Improve instructions based on execution learnings

Run `deepwork sync` after changes to regenerate commands.

## Learning History

### 2026-02-06: Slug Directory Pattern
- **Source**: Publication workflow run for "Budget-Aware Agent Orchestration"
- **Issue**: Files were written to flat `workflow/publications/` instead of `workflow/publications/[slug]/`
- **Resolution**: Updated job.yml and all step instructions to use slug-based paths
- **Reference**: `job.yml` changelog v1.0.1

### 2026-02-06: Opening Framing and Concrete Examples
- **Source**: Same publication run, user feedback during review
- **Issues**:
  1. Draft led with technical cause ("token limits") instead of reader pain ("work not shipping")
  2. Abstract framework needed concrete JSON example to be actionable
- **Resolution**: Updated doc spec quality criteria:
  - "Engaging Opening" now requires leading with symptoms, not technical causes
  - "Actionable Takeaways" now requires concrete examples (code/JSON/diagrams)
- **Reference**: `job.yml` changelog v1.0.2, `.deepwork/doc_specs/publication.md`

### 2026-02-06: Citation Verification Required
- **Source**: Same publication run, user found broken Wikipedia link
- **Issue**: Resources section included link to `https://en.wikipedia.org/wiki/Resource-constrained_project_scheduling_problem` which does not exist
- **Root Cause**: Agent generated a plausible-looking URL without verifying it exists
- **Resolution**:
  - Added quality criterion 6 "Verified Citations" to doc spec
  - Updated `review_publication` step to require WebSearch/WebFetch verification of all external links
  - Added explicit "Step 4b: Verify All External Links" to review workflow
- **Reference**: `job.yml` changelog v1.0.3, `.deepwork/doc_specs/publication.md`

### 2026-03-02: Announcement Publication Type (Working-Backwards Format)
- **Source**: Plant Caravan Cloud press release written using publication workflow
- **Issue**: Publication workflow didn't have a dedicated type for product announcements/press releases. The blog type was used but produced content that didn't follow the Amazon working-backwards structure (problem→solution narrative, two quotes, under one page).
- **Resolution**:
  - Added "announcement" as a publication type (blog, **announcement**, internal, technical_article, tutorial)
  - Added working-backwards structure to `create_outline.md` under announcement type
  - Added Step 3b in `draft_publication.md` with announcement-specific guidance
  - Template reference: `../press_release/templates/working-backwards-template.md`
- **Reference**: `job.yml` v1.2.0

### 2026-03-02: Publication Destination
- **Source**: Plant Caravan Cloud press release — working files were copied to project repo
- **Learning**: Only the final publication content goes to the project repo's publish directory. Working files (scope, outline, draft, metadata) stay in the obsidian vault's `workflow/publications/[slug]/` directory.

## Last Updated

- **Date**: 2026-03-02
- **From**: Announcement type + working-backwards template
- **Version**: 1.2.0

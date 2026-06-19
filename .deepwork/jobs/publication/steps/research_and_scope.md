# Research and Scope

## Objective

Analyze the source material and define the publication scope, including target audience, tone, publication type, and key themes to cover. This step establishes the foundation for creating a high-quality, audience-appropriate publication.

## Task

Gather user requirements and analyze the source material to create a comprehensive scope document that guides all subsequent publication steps.

### Step 1: Gather User Parameters

Ask structured questions to collect the required user inputs:

1. **Source Material**: What is the path to the project, spike, research notes, or idea to publish?
2. **Target Audience**: Who should this publication target?
   - technical_practitioners (developers, engineers)
   - general_tech (tech-interested readers without deep expertise)
   - internal_team (colleagues familiar with organizational context)
3. **Publication Tone**: What tone should the publication use?
   - professional (formal, concise, business-appropriate)
   - funny (humorous, playful, entertaining while informative)
   - academic (rigorous, detailed, precise technical language)
4. **Publication Type**: What type of publication is this?
   - blog (public-facing, engaging, 800-2000 words)
   - announcement (product launch press release, Amazon working-backwards format, under 1 page / ~500-800 words)
   - internal (team-focused, context-aware, concise)
   - technical_article (deep technical dive, code-heavy, 1500-3000 words)
   - tutorial (step-by-step, beginner-friendly, practical examples)

Use the AskUserQuestion tool to ask structured questions for these inputs.

### Step 2: Analyze Source Material

Read and analyze the source material to understand:

1. **Core Content**: What is the main topic, problem, or solution?
2. **Key Themes**: What are the 3-5 most important points or insights?
3. **Technical Depth**: How technical is the source material?
4. **Existing Structure**: What structure or organization already exists?
5. **Assets**: Are there code examples, diagrams, data, or other assets to include?

### Step 3: Define Publication Scope

Based on the user inputs and source material analysis, define:

1. **Publication Goal**: What should readers understand or be able to do after reading?
2. **Audience Fit**: How should content depth and language be adjusted for the target audience?
3. **Tone Application**: What does the selected tone mean for this specific content?
4. **Key Messages**: What are the 3-5 core messages to convey?
5. **Estimated Length**: Based on publication type and content, what's the target word count?
6. **Success Criteria**: What makes this publication successful for the target audience?

### Step 4: Generate Publication Slug

Create a URL-friendly slug for the publication directory:

1. Derive from the main topic/title (e.g., "Budget-Aware Agent Orchestration" → `budget-aware-agent-orchestration`)
2. Use lowercase, hyphens for spaces, no special characters
3. Keep it concise but descriptive (3-6 words typically)
4. Create the directory: `workflow/publications/[slug]/`

### Step 5: Create Scope Document

Write a comprehensive scope document that includes:

- All user parameters (source, audience, tone, type)
- Source material summary
- Key themes and messages
- Publication goal and success criteria
- Audience considerations
- Tone guidelines
- Estimated length and structure approach

## Output Format

### workflow/publications/[slug]/scope.md

A comprehensive scope document that guides outline and draft creation. The `[slug]` is a URL-friendly directory name derived from the publication title (e.g., `budget-aware-agent-orchestration`).

**Structure**:
```markdown
# Publication Scope

## Source Information
- **Source Material**: [path]
- **Source Type**: [project/spike/research/idea]
- **Source Summary**: [2-3 sentence summary of source content]

## Publication Parameters
- **Target Audience**: [technical_practitioners|general_tech|internal_team]
- **Publication Tone**: [professional|funny|academic]
- **Publication Type**: [blog|internal|technical_article|tutorial]
- **Estimated Length**: [word count range]

## Publication Goal
[What should readers understand or be able to do after reading?]

## Key Themes
1. [Theme 1]
2. [Theme 2]
3. [Theme 3]
[4-5 total]

## Audience Considerations
- **Knowledge Level**: [What can we assume they know?]
- **Content Depth**: [How technical should we get?]
- **Language**: [Jargon level, explanation style]

## Tone Guidelines
[How the selected tone applies to this specific content]

## Success Criteria
- [Criterion 1: What makes this publication successful?]
- [Criterion 2]
- [Criterion 3]

## Assets and References
- [Code examples, diagrams, data sources, external resources]
```

## Quality Criteria

- All four user parameters collected through structured questions
- Source material thoroughly analyzed (not just skimmed)
- Key themes are specific and derived from source content (not generic)
- Audience considerations address knowledge level, content depth, and language
- Tone guidelines explain how to apply the selected tone to this specific content
- Success criteria are measurable and audience-focused
- Publication goal is clear and achievable

## Context

This is the first step in the publication workflow. The scope document you create here determines:
- What the outline will structure (step 2)
- How the draft will be written (step 3)
- What the review will validate (step 4)

A thorough, well-considered scope document prevents wasted effort in later steps by establishing clear direction upfront. Think of this as the publication's blueprint - get it right here, and everything else flows smoothly.

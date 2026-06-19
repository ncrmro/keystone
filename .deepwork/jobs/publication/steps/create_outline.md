# Create Outline

## Objective

Develop a structured outline for the publication based on the scope document, organizing key themes into a logical flow that suits the publication type and engages the target audience.

## Task

Transform the key themes and messages from the scope document into a detailed outline that will guide the drafting process.

### Step 1: Read the Scope Document

Read `workflow/publications/[slug]/scope.md` (in the same slug directory from step 1) to understand:
- Publication goal and success criteria
- Key themes and messages
- Target audience and content depth
- Publication tone and type
- Source material summary

### Step 2: Choose Structure Based on Publication Type

Select an appropriate structure for the publication type:

**Blog Posts**:
1. Hook/Opening (attention-grabbing intro)
2. Context/Problem (why this matters)
3. Main Content (2-4 sections covering key themes)
4. Examples/Application (practical demonstration)
5. Conclusion/Takeaways (summary and next steps)

**Internal Docs**:
1. Purpose/Overview
2. Background/Context (organizational context)
3. Key Information (organized by theme)
4. Implementation/Usage (how to apply)
5. References/Resources

**Technical Articles**:
1. Abstract/Introduction
2. Problem Statement
3. Solution/Approach (technical details)
4. Implementation (code examples, architecture)
5. Results/Analysis
6. Conclusion/Future Work

**Tutorials**:
1. Introduction (what you'll learn)
2. Prerequisites (required knowledge/tools)
3. Step-by-step Instructions (numbered, detailed)
4. Examples/Practice (hands-on exercises)
5. Troubleshooting
6. Next Steps

**Announcements / Press Releases** (Amazon working-backwards format):
1. Headline + Subheadline (product name + benefit, one-sentence value prop)
2. Intro (city/date + one sentence launch statement)
3. Problem (2-3 specific, visceral customer pain points)
4. Solution (mirror each pain point with its resolution)
5. Maker Quote (why we built this — vision, motivation)
6. How It Works (concrete mechanics — what the user does)
7. Customer Quote (specific benefit, emotional, first-person)
8. CTA (where to go, what's available now)

Key constraints for announcements: under one page, no jargon, problem before solution, two quotes (builder + customer), specific not vague. See `press_release/templates/working-backwards-template.md` for the full template and examples.

### Step 3: Organize Key Themes

Map the key themes from the scope document to outline sections:
1. Which theme belongs in which section?
2. What's the logical progression?
3. Where do examples or code belong?
4. How do sections build on each other?

### Step 3b: Craft the Working Title

The title is the first thing readers see. It must earn its place.

**Requirements**:
- Read `WRITING_STYLE.md` for the author's voice and anti-patterns
- Check existing titles: scan `projects/ncrmro-website/posts/` and `workflow/publications/*/metadata.yml` for `title:` fields
- **Avoid repeating title patterns** — if multiple posts already use the same formula (e.g., "Announcing X"), choose a different structure
- Titles should be specific and intriguing, not formulaic. Prefer titles that convey the insight or tension over titles that just name the thing.

**Anti-patterns**:
- "Announcing X" (overused — only acceptable if no other posts use this pattern)
- "A Guide to X" / "Introduction to X" (generic)
- "How I Built X" (unless the personal journey is genuinely the point)

**Good examples**: "Alpha One: Engineering the Plant Caravan Sensor Platform", "Hot Keys and Hardware Keys for Agentic Workflows", "We Gave an LLM Access to Our Plant's Grafana Dashboard"

### Step 4: Add Detail to Each Section

For each outline section, specify:
- **Section title** (clear, descriptive heading)
- **Key points** (2-5 bullet points covering what this section addresses)
- **Content notes** (tone guidance, depth level, examples to include)
- **Estimated length** (paragraph count or word range)

### Step 5: Validate Flow

Check that the outline:
- Has a clear beginning, middle, and end
- Progresses logically (doesn't jump around)
- Addresses all key themes from scope
- Matches the target audience's needs
- Supports the publication goal

## Output Format

### workflow/publications/[slug]/outline.md

A detailed outline that structures the publication's content. Use the same slug directory established in the research_and_scope step.

**Structure**:
```markdown
# Publication Outline

## Metadata
- **Title**: [Working title for the publication]
- **Type**: [blog|internal|technical_article|tutorial]
- **Estimated Total Length**: [word count]

## Structure

### 1. [Section Title]
**Purpose**: [What this section accomplishes]

**Key Points**:
- [Point 1]
- [Point 2]
- [Point 3]

**Content Notes**:
- Tone: [How to apply the selected tone here]
- Depth: [Level of technical detail]
- Examples: [What examples or assets to include]

**Estimated Length**: [paragraph count or word range]

---

### 2. [Section Title]
[Repeat structure for each section]

---

[Continue for all sections]

## Flow Check
- [ ] Clear progression from intro to conclusion
- [ ] All key themes from scope addressed
- [ ] Appropriate depth for target audience
- [ ] Examples strategically placed
- [ ] Conclusion ties back to opening
```

## Quality Criteria

- Outline structure matches the publication type (blog/internal/technical_article/tutorial)
- All key themes from the scope document are incorporated
- Each section has clear purpose and key points (not vague placeholders)
- Content notes provide specific guidance for tone, depth, and examples
- Sections flow logically and build on each other
- Estimated lengths are realistic for the publication type
- Opening section has a strong hook strategy
- Conclusion section has clear takeaways

## Context

The outline is the structural blueprint for the publication. A strong outline makes drafting much easier because you know exactly what to write in each section, what depth to aim for, and how sections connect.

This step transforms the scope document's key themes into a concrete plan. The better organized and more detailed this outline, the smoother the drafting process will be. Think of this as the architectural plan before construction - you're deciding where everything goes and how it all fits together.

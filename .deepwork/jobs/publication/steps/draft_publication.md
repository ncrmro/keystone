# Draft Publication

## Objective

Write the complete publication following the outline, applying the appropriate tone and content depth for the target audience while maintaining high quality across all sections.

## Task

Transform the outline into a full, publication-ready draft that engages readers, delivers on the publication goal, and meets the quality standards defined in the publication doc spec.

### Step 1: Review Scope and Outline

Read both input files from the publication's slug directory:
- `workflow/publications/[slug]/scope.md`: Understand audience, tone, goal, and success criteria
- `workflow/publications/[slug]/outline.md`: Follow the structure and content notes

### Step 1b: Read the Writing Style Guide

**Before writing anything**, read `WRITING_STYLE.md` in the vault root. This defines the author's voice — vocabulary, tone, structure, anti-patterns. The draft must pass the style guide's 8-point diagnostic checklist. Key principles:

- Precise vocabulary placed where a simpler word would lose meaning (one per paragraph max, never stacked)
- Cross-domain scientific/technical metaphors to illuminate concepts
- Layered meaning: surface-clear, subtext-rich
- Warmth from specificity, not hollow enthusiasm
- Every sentence earns its place — no filler, no platitudes
- Blog structure: thesis first, load-bearing analogies, end with implication (not summary)

The tone categories below provide *additional* guidance, but `WRITING_STYLE.md` takes precedence for voice and style.

### Step 2: Apply Tone Throughout

Understand how to write in the selected tone:

**Professional/Terse**:
- Formal, business-appropriate language
- Concise sentences, no fluff
- Direct, authoritative voice
- Focus on facts and insights
- Example: "The monitoring platform uses ESP32 microcontrollers with LoRa for low-power, long-range sensor networks."

**Funny/Facetious**:
- Humorous, playful language
- Personal anecdotes or relatable scenarios
- Light sarcasm or wit
- Still informative, not just entertaining
- Example: "Sure, you could wire up sensors by hand like some kind of medieval peasant, or you could use ESP32s and join the rest of us in the 21st century."

**Academic/Technical**:
- Rigorous, precise language
- Technical terminology without over-explanation
- Formal structure and citations
- Detailed, methodical explanations
- Example: "We implement a distributed sensor network using ESP32-based nodes (Espressif Systems, 2016) configured with LoRa transceivers operating at 915 MHz to achieve communication ranges exceeding 2 km in urban environments."

### Step 3: Adjust Depth for Audience

**Technical Practitioners**:
- Include implementation details and code examples
- Use technical jargon appropriately
- Explain the "how" not just the "what"
- Provide architecture diagrams or system designs
- Assume familiarity with core concepts

**General Tech Audience**:
- Explain technical concepts with analogies
- Limit jargon, define necessary terms
- Focus on "what" and "why" over "how"
- Use relatable examples
- Don't assume specialized knowledge

**Internal Team**:
- Reference shared context and internal systems
- Use organizational terminology
- Focus on practical application to team's work
- Can skip basic explanations for familiar concepts

### Step 3b: Announcement-Specific Guidance

If `publication_type` is "announcement", follow the Amazon working-backwards press release format. Key rules:

- **Under one page** — strictly enforced (~500-800 words)
- **Problem before solution** — the pain paragraph comes before the fix
- **Two quotes required** — maker quote (vision/why) and customer quote (specific benefit)
- **No jargon** — written for customers, not engineers or journalists
- **Specific, not vague** — concrete scenarios, not abstract descriptions
- **No boilerplate** — no "About" section, no filler, no padding

Read `../../press_release/templates/working-backwards-template.md` (relative to the publication job dir) for the full template, structure, and examples.

The structure is: Headline → Subheadline → Intro → Problem → Solution → Maker Quote → How It Works → Customer Quote → CTA. Do not deviate from this order.

### Step 4: Write Each Section

Following the outline, write each section:

1. **Start with the hook**: Capture attention in the first 2-3 sentences
2. **Follow the outline structure**: Use the section titles and key points as your guide
3. **Apply content notes**: Follow tone and depth guidance from the outline
4. **Include examples**: Add code blocks, diagrams, or practical demonstrations where specified
5. **Maintain flow**: Ensure smooth transitions between sections
6. **End with takeaways**: Provide clear conclusions and next steps

### Step 5: Add Frontmatter Metadata

Include YAML frontmatter at the top of the draft:

```yaml
---
title: "Publication Title"
date: "YYYY-MM-DD"
audience: [technical_practitioners|general_tech|internal_team]
tone: [professional|funny|academic]
tags: [keyword1, keyword2, keyword3]
source: "path/to/source/material"
publication_type: [blog|internal|technical_article|tutorial]
---
```

### Step 6: Format Properly

- Use proper markdown formatting
- Include code blocks with syntax highlighting
- Add headings that match outline sections
- Use lists, emphasis, and blockquotes appropriately
- Ensure readability (not walls of text)

## Output Format

### workflow/publications/[slug]/draft.md

A complete, publication-ready draft with frontmatter metadata. Use the same slug directory from previous steps.

**Structure**:
```markdown
---
title: "[Engaging, descriptive title]"
date: "2026-02-04"
audience: [audience from scope]
tone: [tone from scope]
tags: [3-5 relevant keywords]
source: "[source material path]"
publication_type: [type from scope]
---

# [Title]

[Hook paragraph - 2-3 sentences that grab attention and set up the content]

## [Section 1 Title]

[Section 1 content following outline structure and tone]

## [Section 2 Title]

[Section 2 content]

[Continue for all sections from outline]

## Conclusion

[Synthesize key points, provide clear takeaways, suggest next steps]

## Resources

[Links to further reading, tools, documentation if applicable]
```

## Quality Criteria

This step has a **doc spec** that defines quality standards. The draft must meet these criteria from `.deepwork/doc_specs/publication.md`:

1. **Engaging Opening**: Strong hook in first 2-3 sentences, clear value proposition, avoids generic introductions
2. **Clear Structure**: Logical flow, clear headings, appropriate formatting, smooth transitions, appropriate length
3. **Tone Consistency**: Selected tone maintained from opening to conclusion without jarring shifts
4. **Audience Appropriateness**: Depth and language match target audience's expertise level
5. **Actionable Takeaways**: Clear conclusions, specific next steps, links to resources, practical applications

Additionally:
- Draft follows the outline structure completely (doesn't skip or rearrange sections)
- All key themes from scope are addressed
- Examples and code blocks are included where specified
- Frontmatter metadata is complete and accurate
- Markdown formatting is proper and readable
- Length is appropriate for publication type (blog: 800-2000 words, technical_article: 1500-3000 words, etc.)

## Context

This is where the planning pays off. The scope and outline have done the hard work of figuring out what to write and how to structure it. Now you're executing that plan.

Don't just mechanically fill in sections - bring the content to life with the appropriate tone, engage the reader, and deliver real value. This draft should be ready for review, not a rough sketch. Aim for publication quality, knowing the review step will refine it further.

The draft is the most substantial artifact in the workflow - it's where ideas become readable, engaging content that serves the target audience.

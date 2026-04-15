# Review Publication

## Objective

Validate the draft publication against quality criteria, ensuring it meets the publication doc spec standards for engaging content, clear structure, tone consistency, audience appropriateness, and actionable takeaways. Refine the draft into a final, publication-ready document.

## Task

Review the draft comprehensively, compare it against the scope requirements and doc spec quality criteria, and produce a polished final publication with complete metadata.

### Step 1: Read Input Files

Read both required inputs from the publication's slug directory:
- `workflow/publications/[slug]/draft.md`: The publication to review
- `workflow/publications/[slug]/scope.md`: Original requirements and success criteria

### Step 2: Validate Against Doc Spec Quality Criteria

Check the draft against all 5 quality criteria from `.deepwork/doc_specs/publication.md`:

#### 1. Engaging Opening
- [ ] Hook captures attention in first 2-3 sentences
- [ ] Clearly states what reader will learn or gain
- [ ] Sets appropriate expectations for depth and scope
- [ ] Avoids generic introductions like "In this post, I will..."

**If it fails**: Rewrite the opening with a stronger hook.

#### 2. Clear Structure
- [ ] Logical flow from introduction through body to conclusion
- [ ] Clear section headings guide the reader
- [ ] Proper formatting (code blocks, lists, emphasis)
- [ ] Smooth transitions between sections
- [ ] Length appropriate to content (not padded or rushed)

**If it fails**: Reorganize sections, improve transitions, adjust length.

#### 3. Tone Consistency
- [ ] Selected tone (professional/funny/academic) maintained throughout
- [ ] No jarring tone shifts
- [ ] Voice is consistent from opening to conclusion

**If it fails**: Revise sections where tone wavers, ensure consistency.

#### 4. Audience Appropriateness
- [ ] Content depth matches target audience expertise
- [ ] Language suits audience (jargon level, explanations)
- [ ] Technical practitioners get implementation details
- [ ] General tech audience gets conceptual explanations
- [ ] Internal team gets relevant organizational context

**If it fails**: Adjust depth and language for the audience.

#### 5. Actionable Takeaways
- [ ] Clear conclusions synthesize the content
- [ ] Specific next steps or actions for readers
- [ ] Links to resources for further learning
- [ ] Practical examples or applications

**If it fails**: Strengthen conclusion with concrete takeaways.

#### 6. Writing Style Guide Compliance
Read `WRITING_STYLE.md` and run the 8-point diagnostic:
- [ ] Precise vocabulary used without stacking (one well-placed word per paragraph max)
- [ ] Cross-domain scientific/technical metaphors illuminate concepts (not decorate)
- [ ] Meaning is layered (surface-clear, subtext-rich)
- [ ] Warmth derived from specificity, not generic enthusiasm
- [ ] All generic LLM filler eradicated (no platitudes, no filler openers, no breathless enthusiasm)
- [ ] Every sentence earns its place
- [ ] Blog structure follows: thesis first, load-bearing analogies, end with implication
- [ ] Title is not formulaic or repetitive of existing posts

**If it fails**: Rewrite offending sections. This is the most common failure mode — LLM defaults produce exactly the kind of writing the style guide explicitly forbids.

### Step 3: Validate Against Scope Requirements

Compare the draft to the scope document:
- [ ] Addresses the publication goal
- [ ] Covers all key themes
- [ ] Meets audience considerations
- [ ] Follows tone guidelines
- [ ] Satisfies success criteria

### Step 4: Technical and Editorial Review

Check for:
- **Technical accuracy**: Are code examples correct? Are technical claims accurate?
- **Clarity**: Is anything confusing or unclear?
- **Grammar and style**: Are there typos, awkward phrasing, or errors?
- **Completeness**: Are there gaps in the content?
- **Length**: Is it within the expected range for the publication type?
- **Citation verification**: Use WebSearch or WebFetch to verify ALL external links work and point to existing content

### Step 4b: Verify All External Links

For every external URL in the Resources section or body:
1. Use WebSearch to confirm the resource exists (e.g., search for the article/page title)
2. If the link doesn't exist, find a working alternative or remove the citation
3. Never include URLs that haven't been verified to work

### Step 5: Refine and Finalize

Based on the review:
1. **Fix any quality criteria failures** - Don't accept "good enough"
2. **Polish the writing** - Improve clarity, flow, and readability
3. **Verify metadata** - Ensure frontmatter is complete and accurate
4. **Final read-through** - Check that everything flows well

### Step 5b: Keep Intermediate Files in Sync

When making changes during review (or after user feedback), update files in dependency order:

1. **scope.md** - If publication goal, themes, or audience considerations changed
2. **outline.md** - If structure, sections, or title changed
3. **draft.md** - If content changed significantly
4. **README.md** - Final output (always updated last)

This ensures all artifacts remain consistent. If only minor edits are needed (typo fixes, small phrasing changes), updating just draft.md and README.md is acceptable.

### Step 6: Create Final Publication

Save the refined publication as `workflow/publications/[slug]/README.md` with:
- All quality criteria met
- Scope requirements satisfied
- Editorial polish applied
- Complete frontmatter metadata

### Step 7: Generate Metadata File

Create a separate metadata file documenting the publication:

```yaml
title: "[Publication title]"
date: "YYYY-MM-DD"
audience: [technical_practitioners|general_tech|internal_team]
tone: [professional|funny|academic]
publication_type: [blog|internal|technical_article|tutorial]
source_material: "[path to source]"
word_count: [approximate word count]
tags:
  - [tag1]
  - [tag2]
  - [tag3]
status: "final"
quality_review:
  engaging_opening: true
  clear_structure: true
  tone_consistency: true
  audience_appropriateness: true
  actionable_takeaways: true
```

## Output Format

### workflow/publications/[slug]/README.md

The polished, publication-ready document that passes all quality criteria. Named `README.md` so it displays automatically when browsing the directory.

**Doc Spec**: `.deepwork/doc_specs/publication.md`

**Structure**: Same as draft.md but refined and validated.

### workflow/publications/[slug]/metadata.yml

A YAML file documenting the publication metadata and quality review status.

**Structure**:
```yaml
title: "Publication Title"
date: "2026-02-04"
audience: technical_practitioners
tone: professional
publication_type: blog
source_material: "projects/plant-caravan/spikes/monitoring-hardware-platform/README.md"
word_count: 1500
tags:
  - IoT
  - hardware
  - monitoring
status: "final"
quality_review:
  engaging_opening: true
  clear_structure: true
  tone_consistency: true
  audience_appropriateness: true
  actionable_takeaways: true
notes: "Additional context about the publication if needed"
```

### Step 8: Generate Anticipated Reader Questions

After finalizing the publication, generate 3-5 questions or comments that readers might raise. This helps the author:
- Identify gaps or unclear sections before publishing
- Prepare responses for likely feedback
- Decide whether to address questions in the publication itself

**Question categories to consider:**
- **Clarification**: "What do you mean by X?" / "How does Y work exactly?"
- **Alternatives**: "Why not use Z instead?" / "What about [competing approach]?"
- **Edge cases**: "Does this work when...?" / "What happens if...?"
- **Deeper dive**: "Can you expand on X?" / "Where can I learn more about Y?"
- **Skepticism**: "Isn't this overkill?" / "Does this actually matter in practice?"

**Output format** - Add to metadata.yml:
```yaml
anticipated_questions:
  - question: "What if I don't have a YubiKey yet?"
    category: clarification
    addressed_in_post: true
  - question: "Why not just use fine-grained GitHub tokens for everything?"
    category: alternatives
    addressed_in_post: true
  - question: "Is this really necessary for solo developers?"
    category: skepticism
    addressed_in_post: false
```

Present the questions to the user and ask if they want to address any unaddressed ones in the publication.

## Quality Criteria

This step has **quality validation hooks** that check the final publication. All criteria must pass:

1. **Engaging Opening**: Strong hook in first 2-3 sentences, clear value proposition
2. **Clear Structure**: Logical flow, clear headings, smooth transitions
3. **Tone Consistency**: Selected tone maintained throughout entire publication
4. **Audience Appropriateness**: Depth and language match target audience expertise
5. **Actionable Takeaways**: Clear conclusions, specific next steps, useful resources
6. **Verified Citations**: All external links verified to exist and work

Additionally:
- All scope requirements addressed
- Technical accuracy verified (code examples work, claims are correct)
- All external URLs tested with WebSearch/WebFetch before inclusion
- Grammar and style are polished
- Metadata file is complete and accurate
- Final publication is truly publication-ready (not "almost done")

## Context

This is the final step in the publication workflow. Your job is to ensure the publication is truly ready for its audience - whether that's publishing to a blog, sharing with the team, or posting as a technical article.

Don't rubber-stamp the draft. Be rigorous in your review. If something doesn't meet the quality criteria, fix it. The goal is to produce publications that are engaging, well-structured, appropriately toned, audience-matched, and actionable.

This step's quality validation hooks will loop until all criteria pass, so take the time to get it right.

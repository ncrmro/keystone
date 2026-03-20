# Synthesize Findings

## Objective

Analyze the gathered sources to produce a structured analysis that directly answers the research question. Synthesize across sources rather than summarizing each individually.

## Task

### Process

1. **Read inputs**

   - Read `research/[topic_slug]/scope.md` for the research question and sub-questions
   - Read `research/[topic_slug]/sources.md` for all gathered findings

2. **Map findings to sub-questions**

   For each sub-question from the scope:
   - Identify which sources address it
   - Note where sources agree, disagree, or are silent
   - Assess the strength of evidence (single source vs. corroborated)

3. **Identify cross-cutting themes**

   Look for patterns that span multiple sources:
   - Recurring themes or trends
   - Contradictions between sources (note which seems more reliable)
   - Unexpected findings not anticipated in the scope
   - Gaps where no sources provide adequate information

4. **Formulate key insights**

   Distill the analysis into 3-5 key insights that:
   - Directly address the main research question
   - Are supported by evidence from multiple sources
   - Are actionable or decision-relevant
   - Note confidence level (high/medium/low based on evidence strength)

5. **Draft takeaway recommendations**

   Based on the analysis, draft preliminary takeaways:
   - What should the reader do with this information?
   - If project-associated, how does this affect the project?
   - What further research might be needed?

## Output Format

### research/[topic_slug]/analysis.md

```markdown
# Analysis: [Topic Name]

## Research Question

[Restated from scope for context]

## Findings by Sub-Question

### [Sub-Question 1]

**Evidence strength**: [strong | moderate | weak]

[Synthesized answer drawing from multiple sources. Cite sources by title with markdown links.]

### [Sub-Question 2]

**Evidence strength**: [strong | moderate | weak]

[Synthesized answer]

## Cross-Cutting Themes

### [Theme 1]

[Description of the theme, citing supporting sources]

### [Theme 2]

[Description of the theme]

## Contradictions and Gaps

- **[Topic]**: [Source A] says X while [Source B] says Y. [Assessment of which is more credible and why.]
- **Gap**: [Area where insufficient evidence was found]

## Key Insights

1. **[Insight title]** (Confidence: [high/medium/low])
   [1-2 sentence explanation with source references]

2. **[Insight title]** (Confidence: [high/medium/low])
   [1-2 sentence explanation]

3. **[Insight title]** (Confidence: [high/medium/low])
   [1-2 sentence explanation]

## Preliminary Takeaways

- [Actionable recommendation based on the analysis]
- [Another recommendation]
- [Further research suggestion if applicable]
```

## Quality Criteria

- Directly addresses the research question and each sub-question from scope.md
- Synthesizes across multiple sources rather than summarizing each individually
- Identifies patterns, contradictions, and gaps in the evidence
- Key insights include confidence levels based on evidence strength
- Source citations use inline markdown links
- Preliminary takeaways are actionable


## Context

This is the analytical core of the research workflow. The gather step collected raw material; this step transforms it into structured understanding. The report step will use this analysis to produce the final deliverable, so the analysis must be thorough enough that the report step doesn't need to re-interpret raw sources.

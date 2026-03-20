# Gather Sources

## Objective

Search for and collect information using the selected research platforms. The platforms file determines which tools to use, and the depth level determines how thorough the search should be.

## Task

### Process

1. **Read the scope and platforms files**

   Read `research/[topic_slug]/scope.md` to understand:
   - The research question and sub-questions
   - The research type (determines where to look)
   - The depth level (determines how many sources)
   - The search strategy outlined in scope

   Read `research/[topic_slug]/platforms.md` to understand:
   - Which platforms to use (local, gemini, chatgpt, grok, perplexity)
   - Whether parallel mode is enabled (multiple platforms)
   - The execution plan for each platform

2. **Execute research based on selected platforms**

   **Local Only:**
   Use Claude's built-in tools based on depth level:
   - Quick: WebSearch for 3-5 queries, WebFetch 3+ sources
   - Standard: WebSearch for 5-8 queries, WebFetch 5+ diverse sources
   - Deep: WebSearch for 8-12 queries, WebFetch + browser automation for interactive sources

   **Gemini Deep Research:**
   - Open Gemini (gemini.google.com) using tabs_create_mcp and navigate
   - Navigate to Deep Research mode
   - Enter the research question from scope.md
   - **Initial review phase**: Gemini will analyze the query and may ask clarifying questions before starting. Review these questions and answer them (or consult the user if needed) to refine the research scope.
   - **Approval gate**: After clarification, Gemini shows a research plan and asks for approval. Review the plan and approve to start deep research.
   - Let Gemini conduct its deep research (this may take several minutes)
   - Extract the findings, sources, and citations from Gemini's response
   - Save the raw output as `sources_gemini.md`

   **ChatGPT Deep Research:**
   - Open ChatGPT (chat.openai.com) using browser automation
   - Use research/browse mode if available
   - Enter the research question
   - **Initial review phase**: ChatGPT may ask clarifying questions to better understand the research scope. Answer these (or consult the user if needed) before it begins deep research.
   - **Approval gate**: ChatGPT typically presents its understanding and asks for confirmation before proceeding. Approve to start the research.
   - Let it gather sources and conduct research
   - Extract findings and citations
   - Save as `sources_chatgpt.md`

   **Grok:**
   - Open Grok (grok.x.com or x.com/grok) using browser automation
   - Enter the research question
   - Grok excels at real-time info and social media context
   - Extract findings, especially any X/Twitter sources
   - Save as `sources_grok.md`

   **Perplexity:**
   - Open Perplexity (perplexity.ai) using browser automation
   - Enter the research question
   - Perplexity provides inline citations and source quality indicators
   - Extract findings with their numbered citations
   - Save as `sources_perplexity.md`

   **Parallel Mode (2+ platforms):**
   - Open each selected platform in separate browser tabs
   - Enter the same research question in each
   - Allow all platforms to conduct research simultaneously
   - Extract findings from each platform into separate source files
   - In the summary, note areas of agreement/disagreement across platforms

3. **Consolidate findings**

   After gathering from all platforms:
   - Create the main `sources.md` file
   - If parallel mode: merge findings from all platform-specific source files
   - Deduplicate sources (same URL from multiple platforms)
   - Note which platform found which source
   - Highlight areas where platforms agree (high confidence) or disagree (needs verification)

4. **Source type targeting by research type**

   | Research Type | Priority Sources |
   |--------------|-----------------|
   | Science | Academic papers, research institutions, preprints, data repositories |
   | Business | Industry reports, company filings, business news, analyst coverage |
   | Competitive | Competitor websites, product reviews, pricing, feature comparisons |
   | Market | Market size reports, consumer surveys, trend analysis, demographic data |
   | Technical | Official docs, benchmarks, architecture posts, GitHub repos, Stack Overflow |

5. **Document each source**

   For every source consulted, record:
   - Title and URL
   - Author/publisher if available
   - Date published (or date accessed if no publish date)
   - Source type (academic, news, blog, docs, report, etc.)
   - Key findings or excerpts relevant to the research question
   - Reliability assessment (high/medium/low)
   - Which platform found this source (for parallel mode)

## Output Format

### research/[topic_slug]/sources_[platform].md (for external platforms)

When using Gemini, ChatGPT, Grok, or Perplexity, save the raw output from each platform:

```markdown
# Sources from [Platform Name]

**Platform**: [gemini | chatgpt | grok | perplexity]
**Query**: [The research question sent to the platform]
**Date**: [YYYY-MM-DD]
**Raw Response Length**: [approximate word count]

## Platform Response

[Preserve the full response from the AI platform, including any formatting, citations, and source links it provided]

## Extracted Sources

[List of URLs and source titles found in the response]
```

### research/[topic_slug]/sources.md (consolidated)

```markdown
# Sources: [Topic Name]

**Depth**: [quick | standard | deep]
**Platforms Used**: [comma-separated list]
**Sources gathered**: [count]
**Date**: [YYYY-MM-DD]

## Cross-Platform Summary

**Platform agreement**: [Topics where multiple platforms found similar information]
**Unique findings**: [Information only found by one platform]
**Conflicts**: [Areas where platforms disagreed]

---

## Source 1: [Title]

- **URL**: [link]
- **Found by**: [platform(s) that cited this source]
- **Author/Publisher**: [name or "Unknown"]
- **Date**: [published date or "Accessed YYYY-MM-DD"]
- **Type**: [academic | news | blog | docs | report | product | forum]
- **Reliability**: [high | medium | low]

### Key Findings

- [Finding relevant to the research question]
- [Another finding]
- [Direct quote or data point if notable]

---

## Source 2: [Title]

[Same structure repeated for each source]

---

## Summary of Coverage

**Well-covered areas**: [Topics with multiple corroborating sources]
**Gaps identified**: [Sub-questions with insufficient evidence]
**Conflicting information**: [Areas where sources disagree]
```

## Quality Criteria

- Minimum source count met for the depth level (quick: 3, standard: 5, deep: 8)
- Sources are diverse in type (not all from the same category)
- Each source has a URL and key findings documented
- Reliability is assessed for each source
- Coverage summary identifies gaps and conflicts
- All selected platforms from platforms.md were used
- For parallel mode: findings from each platform are saved separately and then merged
- For external platforms: raw output is preserved in platform-specific source files


## Context

This step produces the raw material that the synthesize step will analyze. The choice of platforms from the previous step determines the research methodology:

- **Local only**: Fast, stays in session, good for quick lookups
- **Single external platform**: Leverages that platform's unique strengths (Gemini for depth, Grok for real-time, etc.)
- **Parallel platforms**: Maximum coverage, cross-validation, but takes longer

Thorough, well-documented source gathering is essential — the final report quality depends directly on source quality. Document enough detail that the synthesize step can work without re-visiting sources.

When using external platforms, preserve their raw output in platform-specific files. This creates an audit trail and allows the synthesize step to reference the original AI-generated analysis if needed.

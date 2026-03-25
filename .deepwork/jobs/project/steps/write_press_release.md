# Write Press Release

## Objective

Draft a working-backwards press release following the `process.press-release` convention, using the structured context brief as source material.

## Task

Read the context brief from the previous step and the conventions at `.agents/conventions/process.press-release.md` and `.agents/roles/press-release-writer.md`. Then write a complete press release that announces the feature as if it has already launched.

### Process

1. **Read the conventions**
   - Read `.agents/conventions/process.press-release.md` for structural rules
   - Read `.agents/roles/press-release-writer.md` for tone and behavior guidance
   - These are the authoritative source — follow them precisely

2. **Read the context brief**
   - Review `context_brief.md` from the gather_context step
   - Identify: customer, problem, solution, key claims, quote direction, CTA

3. **Write the headline**
   - State the customer benefit in plain language
   - Do NOT lead with the feature name or technical capability
   - Bad: "Project X Launches New S3-Compatible Storage API"
   - Good: "Developers Now Store and Retrieve Any Amount of Data Without Managing Servers"

4. **Write the opening paragraph**
   - Answer: who is the customer, what can they now do, why does it matter
   - Present tense, as if the product is launched
   - Do NOT include a city dateline (e.g., "San Francisco, CA —") unless the user explicitly requests one

5. **Write the body — succinct, semi-terse structure**
   The press release body follows this flow: **current state → why this → how → what**
   - **Current state**: What the customer struggles with today (the problem)
   - **Why this**: Why this matters now — the motivation for building it
   - **How**: How the product solves the problem (customer outcomes, not technical implementation)
   - **What**: Key features at a high level, staying within the claims from the context brief
   - Keep each section to 1-3 sentences. Be direct. No filler.

6. **Include ASCII art mockup**
   - If the product has a UI (TUI, GUI, CLI output, web page), include an ASCII art mockup showing the key interaction
   - The mockup should show the product in use with realistic data — not empty states
   - Use box-drawing characters (`┌ ─ ┐ │ └ ┘ ├ ┤ ┬ ┴ ┼`) for structure
   - Place the mockup between the body and the call to action
   - If the product has no visual interface (e.g., a library or API), omit the mockup

7. **Write the call to action**
   - How the customer gets started
   - Be specific — a URL, a signup flow, a command

8. **Optional: Write FAQ**
   - Anticipate 2-3 objections or questions
   - Keep answers concise

9. **Final check**
   - Verify word count is 300-500 words (aim for concise)
   - Verify present tense throughout
   - Verify no jargon, internal metrics, or implementation details
   - Verify claims match the context brief's key claims
   - Verify NO fictional customer quotes are included
   - Verify NO city dateline is included (unless user requested one)
   - Write the local workflow artifacts under `.deepwork/tmp/`, not ad hoc `/tmp/` paths

10. **Stage the local outputs**
    - Write the press release draft to `.deepwork/tmp/press_release.mdx`
    - Write the issue URL to `.deepwork/tmp/press_release_issue_url.md`
    - These files are transient workflow artifacts for DeepWork output handoff

11. **Publish the canonical copy**
    - After the press release file is written and passes the final check, create an issue on the project's repo that contains the full press release content
    - Use `gh issue create` (GitHub) or `fj issue create` (Forgejo) depending on where the project is hosted
    - The issue title should match the press release headline
    - The issue body should contain the full press release content
    - Label the issue with `press-release` (create the label if it doesn't exist)
    - Record the **full URL** of the created issue in `.deepwork/tmp/press_release_issue_url.md`
    - If the project repo already stores press releases as tracked content, publish the finalized draft there as a separate explicit step after the issue is created
    - If the project does not store press releases in-repo, keep `.deepwork/tmp/press_release.mdx` as the transient local artifact and treat the issue as the canonical published record

## Output Format

### press_release.mdx

The finished press release in MDX format. Write the local workflow artifact to
`.deepwork/tmp/press_release.mdx`.

If the project already stores press releases in-repo, publish the finalized draft
to the project's designated directory, typically `posts/press_releases/`, as a
separate explicit publication step.

### press_release_issue_url.md

A single-line file at `.deepwork/tmp/press_release_issue_url.md` containing the full
URL of the issue created for the press release (e.g.,
`https://github.com/owner/repo/issues/42`). This URL is required for traceability —
downstream workflows like `milestone/setup` link back to the press release via this URL.

**Structure**:
```mdx
## [Headline: Customer Benefit in Plain Language]

[Opening paragraph: who the customer is, what they can now do, why it matters]

**Current state**: [What the customer struggles with today — 1-3 sentences]

**Why this**: [Why it matters now — 1-2 sentences]

**How**: [How the product solves it — customer outcomes — 1-3 sentences]

**What**: [Key features at a high level — 1-3 sentences]

```
[ASCII art mockup showing the product in use — realistic data, box-drawing characters]
```

[Call to action: how to get started]

---

### FAQ
- **Q: [Anticipated question]**
  A: [Answer]
```

**Do NOT include:**
- City dateline (e.g., "San Francisco, CA —") — omit unless user explicitly requests
- Fictional customer quotes — no fabricated testimonials

## Quality Criteria

- The headline and opening paragraph state the customer benefit, not the feature name
- Body follows the current state → why → how → what structure
- The entire release is written in present tense
- Succinct and semi-terse — no filler, no verbose marketing prose
- No jargon, buzzwords, or internal terminology — a non-technical reader can understand it
- The press release clearly implies what must be built to deliver the promise
- Word count is 300-500 words
- Includes a specific call to action
- No internal metrics or implementation details appear
- Claims do not exceed what the context brief defines as deliverable
- ASCII art mockup included for products with a UI (TUI, GUI, CLI, web) — shows realistic usage
- No fictional customer quotes
- No city dateline (unless user explicitly requested one)

## Next Steps

After this workflow completes, suggest the following to the user:

> The press release is done. The natural next step is to run **`milestone/setup`** to create a milestone with user stories derived from this press release. The press release issue URL (`press_release_issue_url.md`) feeds directly into milestone setup as the scope source.
>
> After milestone setup, run **`milestone/engineering_handoff`** to create functional requirement specs and a plan issue.

The full pipeline is: `project/press_release` → `milestone/setup` → `milestone/engineering_handoff`.

## Context

This press release is a working-backwards document in the Amazon tradition. It serves two audiences: customers (who should understand the value immediately) and the development team (who should understand what needs to be built). The quality of this document determines whether the team invests in building the feature — so clarity and honesty about what is being promised are essential.

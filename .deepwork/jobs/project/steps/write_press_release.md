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

5. **Write the problem paragraph**
   - This MUST come before the solution paragraph
   - Draw from the Problem section of the context brief
   - Be specific and concrete about what customers struggled with

6. **Write the solution paragraph**
   - Explain how the product solves the problem
   - Focus on customer outcomes, not technical implementation
   - No internal metrics or architecture details

7. **Write the customer quote**
   - Use the quote direction from the context brief
   - The quote should articulate the value in the customer's own words
   - Include fictional name, title, and company

8. **Write the details paragraph**
   - Cover key features at a high level
   - Stay within the claims defined in the context brief

9. **Write the call to action**
   - How the customer gets started
   - Be specific — a URL, a signup flow, a command

10. **Optional: Write FAQ**
    - Anticipate 2-3 objections or questions
    - Keep answers concise

11. **Final check**
    - Verify word count is 400-600 words
    - Verify present tense throughout
    - Verify no jargon, internal metrics, or implementation details
    - Verify claims match the context brief's key claims

## Output Format

### press_release.mdx

The finished press release in MDX format. Save to `posts/press_releases/` in the project's repository.

**Structure**:
```mdx
## [Headline: Customer Benefit in Plain Language]

**[City, Date]** — [Opening paragraph: who the customer is, what they can now do, why it matters]

[Problem paragraph: what the customer struggled with before]

[Solution paragraph: how the product solves it]

> "[Customer quote articulating the value]"
> — [Fictional customer name, title, company]

[Details paragraph: key features, how it works at a high level]

[Call to action: how to get started]

---

### FAQ
- **Q: [Anticipated question]**
  A: [Answer]
```

## Quality Criteria

- The headline and opening paragraph state the customer benefit, not the feature name
- A problem paragraph precedes the solution paragraph
- The entire release is written in present tense
- No jargon, buzzwords, or internal terminology — a non-technical reader can understand it
- The press release clearly implies what must be built to deliver the promise
- Word count is 400-600 words
- Includes a fictional customer quote that articulates genuine value
- Includes a specific call to action
- No internal metrics or implementation details appear
- Claims do not exceed what the context brief defines as deliverable

## Context

This press release is a working-backwards document in the Amazon tradition. It serves two audiences: customers (who should understand the value immediately) and the development team (who should understand what needs to be built). The quality of this document determines whether the team invests in building the feature — so clarity and honesty about what is being promised are essential.

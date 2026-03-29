# Step: Gather Slide Requirements

Collect all information needed to produce a focused, audience-appropriate presentation.

## Your Task

Ask the human operator (or infer from context) the following details. Produce a structured requirements document.

### Information to Collect

1. **Topic** — What is the presentation about? (e.g., "Plant Caravan Q1 milestone review", "AI tooling strategy")
2. **Audience** — Who will see this? (e.g., "internal team", "investors", "customers", "CEO")
3. **Project** — Which project does this relate to? Use the project slug (e.g., `plant-caravan`) or leave blank if general.
4. **Milestone** — Which milestone or initiative is this for? Use the milestone slug (e.g., `hydrotower-v1`) or leave blank.
5. **Key messages** — What are the 3–5 things the audience must take away?
6. **Approximate slide count** — How many slides? (default: 10–15)
7. **Tone** — Formal, casual, technical, executive-summary?
8. **Existing artifacts** — Are there demo screenshots, URLs, or documents to reference?

## Output

Write all collected information to `slide_requirements.md` in structured Markdown:

```markdown
# Slide requirements

## Topic
{topic}

## Audience
{audience}

## Project
{project slug or "none"}

## Milestone
{milestone slug or "none"}

## Key messages
1. {message}
2. {message}
…

## Slide count
{n}

## Tone
{tone}

## Existing artifacts
- {artifact or URL}
```

## Quality Checklist

Before calling `finished_step`, verify:
- [ ] Topic is specific and actionable for a writer
- [ ] Audience is named (not just "general")
- [ ] At least 3 key messages are listed
- [ ] `slide_requirements.md` exists and is well-structured

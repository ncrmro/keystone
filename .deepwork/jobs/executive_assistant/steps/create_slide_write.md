# Step: Write Slides

Produce the full Slidev `slides.md` content for the presentation.

## Your Task

Read `slide_requirements.md` and `scaffold_report.md` to determine:
- The deck directory path
- The topic, audience, key messages, tone, and artifact references

Then write the complete `slides.md` into the scaffolded directory.

## Slidev Format

Each slide is separated by `---`. The file begins with a YAML front matter block.

### Required Structure

```
---
theme: default
title: {title}
---

# {title}
{subtitle or audience} · {date}

---

## Agenda
1. {topic 1}
2. {topic 2}
…

---

## {Section}
{content}

---

…

## Key Takeaways
- {message 1}
- {message 2}
- {message 3}

---

## Next Steps
- {action 1}
- {action 2}

---

# Thank You
{contact or call to action}
```

### Content Rules

- Write from the **audience's perspective** — frame everything as outcomes and value, not implementation.
- Each slide should have a single clear point.
- Use bullet points, not paragraphs, for body content.
- Keep slide titles short (≤ 7 words).
- Reference any existing artifacts (screenshots, URLs) from `slide_requirements.md` where relevant.
- Tone MUST match what was specified in requirements (formal, casual, technical, executive-summary).

### Slide Count

Target the slide count specified in requirements (default 10–15). Include at minimum:
- Title slide
- Agenda slide
- One slide per key message
- Key Takeaways slide
- Next Steps slide
- Closing / Thank You slide

## Output

Overwrite `~/notes/presentations/{id} {slug}/slides.md` with the full deck content.

Write `slides_draft_report.md`:

```markdown
# Slides draft report

## Deck path
~/notes/presentations/{id} {slug}/slides.md

## Slide count
{n}

## Sections
- {section name}
- …

## Key messages covered
- [ ] {message 1}
- [ ] {message 2}
…
```

## Quality Checklist

Before calling `finished_step`, verify:
- [ ] `slides.md` starts with a valid Slidev YAML front matter block
- [ ] All key messages from requirements appear in the deck
- [ ] Slide count is within the requested range
- [ ] No credentials, API keys, or internal infrastructure details are present
- [ ] Tone matches the requested style
- [ ] `slides_draft_report.md` is written

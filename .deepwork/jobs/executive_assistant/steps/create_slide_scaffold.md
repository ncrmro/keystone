# Step: Scaffold Presentation

Create the zk note directory for the slide deck in `~/notes/presentations/` and initialize Git LFS if needed.

## Your Task

### 1. Generate a zk ID and slug

Run the following to get the current timestamp ID:

```bash
date '+%Y%m%d%H%M'
```

Create a slug from the topic in `slide_requirements.md` (lowercase, hyphens, no special characters). For example, "Plant Caravan Q1 Review" → `plant-caravan-q1-review`.

### 2. Create the directory structure

```bash
NOTES=~/notes
ID="<timestamp>"
SLUG="<topic-slug>"
DIR="$NOTES/presentations/$ID $SLUG"

mkdir -p "$DIR/assets"
```

### 3. Write `index.md`

Create `$DIR/index.md` with the front matter from the `presentation.md` zk template. Fill in:
- `id` — the timestamp you generated
- `title` — human-readable presentation title
- `type: presentation`
- `project` — from `slide_requirements.md` (or `""`)
- `milestone` — from `slide_requirements.md` (or `""`)
- `date` — today's date (YYYY-MM-DD)
- `slidev_path` — `presentations/{id} {slug}/slides.md`

### 4. Write a placeholder `slides.md`

Create `$DIR/slides.md` with the Slidev front matter block and a single title slide:

```markdown
---
theme: default
title: {title}
---

# {title}

{audience} · {date}

---

<!-- slides to be written in the next step -->
```

### 5. Check and initialize Git LFS

```bash
cd ~/notes
git lfs version 2>/dev/null || echo "WARNING: git-lfs not installed"
git lfs install 2>/dev/null || true
```

If git-lfs is not installed, note it in the output but do not fail — the scaffold can proceed without it.

### 6. Verify `.gitattributes`

Confirm `~/notes/.gitattributes` exists and contains the LFS rules for `presentations/**/assets/*`. If it does not exist, create it per the `process.slide-deck` convention.

## Output

Write `scaffold_report.md`:

```markdown
# Scaffold report

## Directory
~/notes/presentations/{id} {slug}/

## Files created
- index.md
- slides.md
- assets/ (empty)

## Git LFS status
{installed / not installed}

## .gitattributes
{present / created}
```

## Quality Checklist

Before calling `finished_step`, verify:
- [ ] `~/notes/presentations/{id} {slug}/index.md` exists with correct front matter
- [ ] `~/notes/presentations/{id} {slug}/slides.md` exists with valid Slidev header
- [ ] `~/notes/presentations/{id} {slug}/assets/` directory exists
- [ ] `~/notes/.gitattributes` contains LFS rules for `presentations/**/assets/*`
- [ ] `scaffold_report.md` is written

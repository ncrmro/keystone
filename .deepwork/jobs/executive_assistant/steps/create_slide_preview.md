# Step: Preview and Capture

Launch the Slidev dev server, capture a screenshot of the opening slide, and commit the presentation artifacts to git.

## Your Task

### 1. Start the Slidev dev server

Navigate to the deck directory and launch Slidev on port 3031:

```bash
cd ~/notes/presentations/{id} {slug}
npx slidev slides.md --port 3031 &
SLIDEV_PID=$!
```

Wait up to 15 seconds for the server to become ready:

```bash
for i in $(seq 1 15); do
  curl -sf http://localhost:3031 > /dev/null && echo "ready" && break
  sleep 1
done
```

If the server does not become ready within 15 seconds, note the failure in the output but continue to the commit step (screenshots are optional).

### 2. Navigate Chrome to the deck

Use the Chrome DevTools MCP to navigate the pre-provisioned Chromium to the Slidev dev server:

```javascript
await mcp.chrome_devtools.navigate_page({ url: "http://localhost:3031" });
```

Wait 2 seconds for the slide to render, then capture a screenshot:

```javascript
const screenshot = await mcp.chrome_devtools.take_screenshot();
// Save to: ~/notes/presentations/{id} {slug}/assets/slide-01.png
```

Save the screenshot to `~/notes/presentations/{id} {slug}/assets/slide-01.png`.

### 3. Stop the dev server

```bash
kill $SLIDEV_PID 2>/dev/null || true
```

### 4. Commit to git

Stage and commit all presentation files:

```bash
cd ~/notes
git add presentations/{id}\ {slug}/
git commit -m "feat: add presentation — {title}"
```

If git-lfs is installed and the screenshot was saved, verify LFS tracking:

```bash
git lfs ls-files | grep "presentations/"
```

### 5. Write the preview report

Write `preview_report.md`:

```markdown
# Preview report

## Dev server
{launched successfully / failed to start}

## Screenshot
{saved to assets/slide-01.png / not captured}

## LFS tracking
{screenshot tracked by LFS / LFS not available}

## Git commit
{commit SHA}

## Deck path
~/notes/presentations/{id} {slug}/

## Slides URL (while dev server is running)
http://localhost:3031
```

## Quality Checklist

Before calling `finished_step`, verify:
- [ ] Git commit was created with the presentation files
- [ ] `preview_report.md` is written
- [ ] Dev server outcome (success or failure) is documented
- [ ] Screenshot capture outcome is documented
- [ ] If screenshot was captured, `assets/slide-01.png` exists in the deck directory

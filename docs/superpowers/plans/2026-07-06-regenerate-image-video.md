# Regenerate Image and Video Entry Points Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make existing storyboard image and video regeneration actions explicit in the frontend UI.

**Architecture:** Reuse the current frontend generation functions and backend APIs. The implementation only changes the episode production page template and CSS: image regeneration stays wired to `genShotFrame`, and video regeneration stays wired to `genVid`.

**Tech Stack:** Vue 3 single-file component, TypeScript, Vite, existing pure CSS styling, existing backend image/video APIs.

## Global Constraints

- Do not add backend endpoints.
- Do not change image or video generation request parameters.
- Do not delete old static image or video files.
- Do not add one-click combined image-and-video regeneration.
- Do not add batch regeneration.
- Do not auto-trigger composed video regeneration.
- Preserve old resources when regeneration fails.
- Main file to modify: `frontend/app/pages/drama/[id]/episode/[episodeNumber].vue`.

---

## File Structure

- Modify: `frontend/app/pages/drama/[id]/episode/[episodeNumber].vue`
  - Template: make first-frame and last-frame regenerate controls explicit.
  - Template: change video action button text to `重新生成视频` when a video already exists.
  - Style: add or adjust small overlay/button styles for image regenerate controls.
- No changes: `frontend/app/composables/useApi.ts`
- No changes: backend routes, backend services, or database schema.

---

### Task 1: Make Storyboard Frame Regeneration Explicit

**Files:**
- Modify: `frontend/app/pages/drama/[id]/episode/[episodeNumber].vue:961-997`
- Modify: `frontend/app/pages/drama/[id]/episode/[episodeNumber].vue:3742-3747`

**Interfaces:**
- Consumes: existing `getFirstFrame(sb)`, `getLastFrame(sb)`, `isPendingShotFrame(sb.id, frameType)`, `genShotFrame(sb, frameType)`, and `openImageViewer(src, title)`.
- Produces: explicit `.frame-regenerate-btn` controls that call `genShotFrame(sb, 'first_frame')` or `genShotFrame(sb, 'last_frame')`.

- [ ] **Step 1: Inspect the existing frame thumbnail block**

Open `frontend/app/pages/drama/[id]/episode/[episodeNumber].vue` and locate the thumbnail block around the existing first-frame markup:

```vue
<div class="frame-thumb-wrap">
  <div class="frame-thumb" @click.stop="!isPendingShotFrame(sb.id, 'first_frame') && genShotFrame(sb, 'first_frame')">
    <img
      v-if="getFirstFrame(sb)"
      :src="'/' + getFirstFrame(sb)"
      class="previewable-image"
      @click.stop="openImageViewer('/' + getFirstFrame(sb), `镜头 #${String(i + 1).padStart(2, '0')} 首帧`)"
    />
    <div v-else class="frame-thumb-empty">
      <Loader2 v-if="isPendingShotFrame(sb.id, 'first_frame')" :size="14" class="animate-spin" />
      <svg v-else width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
    </div>
    <span v-if="getFirstFrame(sb)" class="frame-re">
      <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>
    </span>
  </div>
  <span class="frame-thumb-label">{{ isPendingShotFrame(sb.id, 'first_frame') ? '首帧生成中' : '首帧' }}</span>
</div>
```

Expected: the first-frame and last-frame blocks both contain a hidden `.frame-re` icon and the thumbnail wrapper itself calls `genShotFrame`.

- [ ] **Step 2: Replace the first-frame hidden icon with an explicit button**

In the first-frame block, replace the existing hidden icon block:

```vue
<span v-if="getFirstFrame(sb)" class="frame-re">
  <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>
</span>
```

with this explicit button:

```vue
<button
  v-if="getFirstFrame(sb)"
  type="button"
  class="frame-regenerate-btn"
  :disabled="isPendingShotFrame(sb.id, 'first_frame')"
  @click.stop="genShotFrame(sb, 'first_frame')"
>
  <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>
  重新生成
</button>
```

Expected: existing-image first-frame thumbnails show a real clickable `重新生成` control; image preview click still opens the image viewer because the `<img>` click handler remains unchanged.

- [ ] **Step 3: Replace the last-frame hidden icon with an explicit button**

In the last-frame block, replace the existing hidden icon block:

```vue
<span v-if="getLastFrame(sb)" class="frame-re">
  <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>
</span>
```

with this explicit button:

```vue
<button
  v-if="getLastFrame(sb)"
  type="button"
  class="frame-regenerate-btn"
  :disabled="isPendingShotFrame(sb.id, 'last_frame')"
  @click.stop="genShotFrame(sb, 'last_frame')"
>
  <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>
  重新生成
</button>
```

Expected: existing-image last-frame thumbnails show the same `重新生成` control and use `last_frame` as the generation type.

- [ ] **Step 4: Replace `.frame-re` CSS with `.frame-regenerate-btn` CSS**

Find this existing CSS:

```css
.frame-re {
  position: absolute; top: 3px; right: 3px; width: 18px; height: 18px;
  border-radius: 50%; background: rgba(0,0,0,0.5); color: #fff;
  display: none; align-items: center; justify-content: center;
}
.frame-thumb:hover .frame-re { display: flex; }
```

Replace it with:

```css
.frame-regenerate-btn {
  position: absolute;
  right: 4px;
  bottom: 4px;
  display: flex;
  align-items: center;
  gap: 3px;
  height: 20px;
  padding: 0 6px;
  border: 1px solid rgba(255,255,255,0.22);
  border-radius: 999px;
  background: rgba(0,0,0,0.58);
  color: #fff;
  font-size: 10px;
  font-weight: 600;
  line-height: 1;
  cursor: pointer;
  opacity: 0;
  transform: translateY(2px);
  transition: opacity 0.15s, transform 0.15s, background 0.15s;
}
.frame-thumb:hover .frame-regenerate-btn,
.frame-regenerate-btn:focus-visible {
  opacity: 1;
  transform: translateY(0);
}
.frame-regenerate-btn:hover:not(:disabled) { background: rgba(0,0,0,0.72); }
.frame-regenerate-btn:disabled { cursor: not-allowed; opacity: 0.56; }
```

Expected: the regenerate button appears on hover/focus, is text-labeled, and does not replace the image preview behavior.

- [ ] **Step 5: Run frontend build to verify template and CSS are valid**

Run:

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/frontend && npm run build
```

Expected: build completes without Vue template or CSS errors.

- [ ] **Step 6: Commit Task 1**

Run:

```bash
git add frontend/app/pages/drama/[id]/episode/[episodeNumber].vue
git commit -m "feat: show storyboard frame regenerate actions"
```

Expected: commit succeeds.

---

### Task 2: Show Regenerate Video Text for Existing Videos

**Files:**
- Modify: `frontend/app/pages/drama/[id]/episode/[episodeNumber].vue:1248-1252`

**Interfaces:**
- Consumes: existing `hasVid(sb)`, `isPendingVideo(sb.id)`, and `genVid(sb)`.
- Produces: video action text that distinguishes `生成视频` from `重新生成视频`.

- [ ] **Step 1: Inspect the existing video action button**

Open `frontend/app/pages/drama/[id]/episode/[episodeNumber].vue` and locate this button in the video production tab:

```vue
<button class="btn btn-sm" :disabled="isPendingVideo(sb.id)" @click="genVid(sb)">
  <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2" ry="2"/></svg>
  {{ isPendingVideo(sb.id) ? '生成中' : '生成视频' }}
</button>
```

Expected: current text does not distinguish whether `hasVid(sb)` is true.

- [ ] **Step 2: Update the button label expression**

Replace the text expression:

```vue
{{ isPendingVideo(sb.id) ? '生成中' : '生成视频' }}
```

with:

```vue
{{ isPendingVideo(sb.id) ? '生成中' : (hasVid(sb) ? '重新生成视频' : '生成视频') }}
```

The complete button should be:

```vue
<button class="btn btn-sm" :disabled="isPendingVideo(sb.id)" @click="genVid(sb)">
  <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2" ry="2"/></svg>
  {{ isPendingVideo(sb.id) ? '生成中' : (hasVid(sb) ? '重新生成视频' : '生成视频') }}
</button>
```

Expected: cards with an existing `videoUrl` show `重新生成视频`; cards without a video still show `生成视频`; pending cards still show `生成中`.

- [ ] **Step 3: Run frontend build to verify the template is valid**

Run:

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/frontend && npm run build
```

Expected: build completes without Vue template or TypeScript errors.

- [ ] **Step 4: Commit Task 2**

Run:

```bash
git add frontend/app/pages/drama/[id]/episode/[episodeNumber].vue
git commit -m "feat: label existing video generation as regenerate"
```

Expected: commit succeeds.

---

### Task 3: Manual Verification Pass

**Files:**
- No code files should change in this task.

**Interfaces:**
- Consumes: UI changes from Task 1 and Task 2.
- Produces: verified behavior notes for the final response.

- [ ] **Step 1: Start the frontend dev server if it is not already running**

Run:

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/frontend && npm run dev
```

Expected: Vite starts on the configured frontend port and reports a local URL.

- [ ] **Step 2: Start the backend dev server if it is not already running**

Run in a separate terminal/session:

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/backend && npm run dev
```

Expected: backend starts on the configured API port without startup errors.

- [ ] **Step 3: Verify image regeneration UI states**

Open the episode page that contains at least one storyboard with existing first-frame or last-frame images. Confirm:

```text
- Existing first-frame thumbnail shows a visible/focusable “重新生成” control on hover.
- Existing last-frame thumbnail shows a visible/focusable “重新生成” control on hover when first/last frame mode is active.
- Clicking the thumbnail image still opens the image viewer.
- Clicking “重新生成” triggers the existing frame generation pending state.
- During pending state, repeated clicks are disabled by the existing pending guard.
```

Expected: all confirmations pass.

- [ ] **Step 4: Verify video regeneration UI states**

Open the video production tab. Confirm:

```text
- A storyboard without video shows “生成视频”.
- A storyboard with video shows “重新生成视频”.
- Clicking “重新生成视频” starts the existing video generation flow.
- During pending state, the button shows “生成中” and is disabled.
- If generation fails, the old video remains visible and the existing failure message area is used.
```

Expected: all confirmations pass.

- [ ] **Step 5: Run final frontend build**

Run:

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/frontend && npm run build
```

Expected: build completes successfully.

- [ ] **Step 6: Capture final git status**

Run:

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama && git status --short
```

Expected: working tree contains only intentional changes, or is clean if each task was committed.

---

## Self-Review

- Spec coverage: Task 1 covers explicit first-frame and last-frame regeneration. Task 2 covers existing-video button text. Task 3 covers success and failure behavior verification. No backend changes are included, matching the spec.
- Placeholder scan: this plan contains no TBD, TODO, or incomplete implementation steps.
- Type consistency: all referenced functions already exist in `frontend/app/pages/drama/[id]/episode/[episodeNumber].vue`: `getFirstFrame`, `getLastFrame`, `isPendingShotFrame`, `genShotFrame`, `openImageViewer`, `hasVid`, `isPendingVideo`, and `genVid`.

# Compose TTS Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `enableTTS` flag to the video compose stage so the user can skip TTS audio generation while keeping subtitle burn-in.

**Architecture:** The toggle lives in the frontend compose tab as a Vue `ref<boolean>` defaulting to `true`. It is passed as `{ enable_tts }` in the POST body to both compose endpoints. The backend routes read the flag and forward it to `composeStoryboard()` via a new `ComposeOptions` interface. Inside `composeStoryboard`, a single `shouldGenerateAudio` boolean gates TTS; subtitle generation remains independent and still runs when `dialogue` has speakable text.

**Tech Stack:** TypeScript (backend Hono + Drizzle), Vue 3 SFC (frontend Nuxt 3), FFmpeg via fluent-ffmpeg.

## Global Constraints

- Only the video **compose** stage is affected — image generation, video generation, individual TTS generation (`/storyboards/:id/generate-tts`), and voice sample endpoints are untouched.
- No database schema changes.
- `enableTTS` defaults to `true`; omitting it from the request body must behave identically to `true`.
- Subtitle generation (SRT file) runs whenever `dialogue` has speakable text, **regardless** of `enableTTS`.
- Frontend toggle state is session-only (not persisted); page refresh resets to `true`.
- Backend TypeScript must pass `npm run typecheck` in `backend/`.
- Frontend must pass `npm run build` in `frontend/`.

---

## File Structure

| File | Change |
|------|--------|
| `backend/src/services/ffmpeg-compose.ts` | Add `ComposeOptions` interface + `options` param to `composeStoryboard`; gate TTS logic on `enableTTS` |
| `backend/src/routes/compose.ts` | Parse `enable_tts` from request body; pass as `{ enableTTS }` to `composeStoryboard` |
| `frontend/app/composables/useApi.ts` | Add optional `opts` param to `composeAPI.shot` and `composeAPI.all` |
| `frontend/app/pages/drama/[id]/episode/[episodeNumber].vue` | Add `composeTTSEnabled` ref + toggle UI in compose tab; pass flag when calling compose APIs |

---

### Task 1: Backend service — `ComposeOptions` + `enableTTS` gate

**Files:**
- Modify: `backend/src/services/ffmpeg-compose.ts:53`

**Interfaces:**
- Produces: `composeStoryboard(storyboardId: number, options?: ComposeOptions): Promise<string>` where `ComposeOptions = { enableTTS?: boolean }` — used by Task 2.

- [ ] **Step 1: Open the file and locate the function signature**

Open `backend/src/services/ffmpeg-compose.ts` and find line 53:

```ts
export async function composeStoryboard(storyboardId: number): Promise<string> {
```

- [ ] **Step 2: Add the `ComposeOptions` interface above the function**

Insert immediately before the `composeStoryboard` function declaration:

```ts
export interface ComposeOptions {
  enableTTS?: boolean
}
```

- [ ] **Step 3: Update the function signature**

Replace:

```ts
export async function composeStoryboard(storyboardId: number): Promise<string> {
```

with:

```ts
export async function composeStoryboard(storyboardId: number, options: ComposeOptions = {}): Promise<string> {
```

- [ ] **Step 4: Add `shouldGenerateAudio` flag after `parsedDialogue` is computed**

Find the line (around line 71):

```ts
  const parsedDialogue = parseDialogueForTTS(sb.dialogue)
```

Immediately after it, add:

```ts
  const shouldGenerateAudio = (options.enableTTS ?? true) && !parsedDialogue.ignorable
```

- [ ] **Step 5: Gate the TTS block on `shouldGenerateAudio`**

Find the existing TTS block that starts around line 73–74:

```ts
    if (!parsedDialogue.ignorable) {
      if (sb.ttsAudioUrl) {
```

Replace the outer condition from:

```ts
    if (!parsedDialogue.ignorable) {
```

with:

```ts
    if (shouldGenerateAudio) {
```

The inner logic (reuse existing `ttsAudioUrl`, call `generateTTS`, write back to DB) remains unchanged.

- [ ] **Step 6: Keep subtitle generation independent of `enableTTS`**

Find the subtitle generation block that starts around line 108:

```ts
    if (!parsedDialogue.ignorable) {
      const srtDir = path.join(STORAGE_ROOT, 'subtitles')
```

This condition must stay as `!parsedDialogue.ignorable` — **do not change it**. Verify it is unchanged.

- [ ] **Step 7: Run TypeScript typecheck**

Run:

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/backend && npm run typecheck
```

Expected: exits with code 0, no errors.

- [ ] **Step 8: Commit**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add backend/src/services/ffmpeg-compose.ts
git commit -m "feat: add ComposeOptions.enableTTS to composeStoryboard"
```

---

### Task 2: Backend routes — parse `enable_tts` and forward to service

**Files:**
- Modify: `backend/src/routes/compose.ts:12-23` (single compose)
- Modify: `backend/src/routes/compose.ts:26-60` (batch compose)

**Interfaces:**
- Consumes: `composeStoryboard(storyboardId, { enableTTS?: boolean })` from Task 1.
- Produces: both compose routes accept optional `{ enable_tts: boolean }` in the JSON body and forward `{ enableTTS }` to the service.

- [ ] **Step 1: Update the single-compose route**

Find the single-compose route handler in `backend/src/routes/compose.ts` (around line 12):

```ts
app.post('/storyboards/:id/compose', async (c) => {
  const id = Number(c.req.param('id'))
  try {
    logTaskStart('ComposeAPI', 'single-compose', { storyboardId: id })
    const composedUrl = await composeStoryboard(id)
```

Replace those lines with:

```ts
app.post('/storyboards/:id/compose', async (c) => {
  const id = Number(c.req.param('id'))
  const body = await c.req.json().catch(() => ({}))
  const enableTTS: boolean = body.enable_tts !== false
  try {
    logTaskStart('ComposeAPI', 'single-compose', { storyboardId: id, enableTTS })
    const composedUrl = await composeStoryboard(id, { enableTTS })
```

- [ ] **Step 2: Update the batch-compose route**

Find the batch-compose route handler (around line 26):

```ts
app.post('/episodes/:id/compose-all', async (c) => {
  const episodeId = Number(c.req.param('id'))
  const storyboards = db.select().from(schema.storyboards)
    .where(eq(schema.storyboards.episodeId, episodeId))
    .orderBy(schema.storyboards.storyboardNumber)
    .all()

  if (storyboards.length === 0) return badRequest(c, 'No storyboards found')

  const withVideo = storyboards.filter(sb => sb.videoUrl)
  if (withVideo.length === 0) return badRequest(c, 'No storyboards have video yet')

  // 异步处理
  db.update(schema.storyboards)
    .set({ status: 'compose_processing' })
    .where(eq(schema.storyboards.episodeId, episodeId))
    .run()

  ;(async () => {
    for (const sb of withVideo) {
      try {
        await composeStoryboard(sb.id)
```

Replace:

```ts
app.post('/episodes/:id/compose-all', async (c) => {
  const episodeId = Number(c.req.param('id'))
  const storyboards = db.select().from(schema.storyboards)
```

with:

```ts
app.post('/episodes/:id/compose-all', async (c) => {
  const episodeId = Number(c.req.param('id'))
  const body = await c.req.json().catch(() => ({}))
  const enableTTS: boolean = body.enable_tts !== false
  const storyboards = db.select().from(schema.storyboards)
```

And replace the inner `composeStoryboard(sb.id)` call:

```ts
        await composeStoryboard(sb.id)
```

with:

```ts
        await composeStoryboard(sb.id, { enableTTS })
```

- [ ] **Step 3: Run TypeScript typecheck**

Run:

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/backend && npm run typecheck
```

Expected: exits with code 0, no errors.

- [ ] **Step 4: Commit**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add backend/src/routes/compose.ts
git commit -m "feat: pass enable_tts from compose routes to composeStoryboard"
```

---

### Task 3: Frontend API — add optional `opts` to `composeAPI`

**Files:**
- Modify: `frontend/app/composables/useApi.ts:93-97`

**Interfaces:**
- Produces:
  ```ts
  composeAPI.shot(id: number, opts?: { enable_tts?: boolean }): Promise<any>
  composeAPI.all(epId: number, opts?: { enable_tts?: boolean }): Promise<any>
  ```
  Used by Task 4.

- [ ] **Step 1: Update `composeAPI` in `useApi.ts`**

Find lines 93–97:

```ts
export const composeAPI = {
  shot: (id: number) => api.post(`/compose/storyboards/${id}/compose`),
  all: (epId: number) => api.post(`/compose/episodes/${epId}/compose-all`),
  status: (epId: number) => api.get(`/compose/episodes/${epId}/compose-status`),
}
```

Replace with:

```ts
export const composeAPI = {
  shot: (id: number, opts?: { enable_tts?: boolean }) =>
    api.post(`/compose/storyboards/${id}/compose`, opts ?? {}),
  all: (epId: number, opts?: { enable_tts?: boolean }) =>
    api.post(`/compose/episodes/${epId}/compose-all`, opts ?? {}),
  status: (epId: number) => api.get(`/compose/episodes/${epId}/compose-status`),
}
```

- [ ] **Step 2: Run frontend build to verify types**

Run:

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/frontend && npm run build
```

Expected: build completes without TypeScript or Vue template errors.

- [ ] **Step 3: Commit**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add frontend/app/composables/useApi.ts
git commit -m "feat: add optional opts param to composeAPI.shot and composeAPI.all"
```

---

### Task 4: Frontend UI — TTS toggle in compose tab

**Files:**
- Modify: `frontend/app/pages/drama/[id]/episode/[episodeNumber].vue`

**Interfaces:**
- Consumes: `composeAPI.shot(id, opts)` and `composeAPI.all(epId, opts)` from Task 3.
- Produces: `composeTTSEnabled` ref and toggle UI; updated `doCompose` and `batchCompose` calls.

- [ ] **Step 1: Add `composeTTSEnabled` ref**

Find the block where `pendingComposeIds` is declared (around line 1518):

```ts
  const pendingComposeIds: Ref<number[]> = ref([])
```

On the line immediately after it, add:

```ts
  const composeTTSEnabled = ref(true)
```

- [ ] **Step 2: Add the TTS toggle to the compose section bar**

Find the compose section bar (around line 1274–1283):

```vue
            <div class="prod-section-bar">
              <span class="dim" style="font-size:12px">{{ sbs.length }} 个镜头</span>
              <span class="tag mono">{{ composedCount }}/{{ sbs.length }} 已合成</span>
              <div class="ml-auto flex gap-1">
                <button class="btn btn-sm" @click="batchCompose">
                  <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/></svg>
                  批量合成
                </button>
              </div>
            </div>
```

Replace with:

```vue
            <div class="prod-section-bar">
              <span class="dim" style="font-size:12px">{{ sbs.length }} 个镜头</span>
              <span class="tag mono">{{ composedCount }}/{{ sbs.length }} 已合成</span>
              <div class="ml-auto flex gap-1" style="align-items:center">
                <label class="compose-tts-toggle" style="display:flex;align-items:center;gap:5px;cursor:pointer;font-size:12px;color:var(--text-2)">
                  <input type="checkbox" v-model="composeTTSEnabled" style="cursor:pointer" />
                  合成时包含配音
                </label>
                <button class="btn btn-sm" @click="batchCompose">
                  <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/></svg>
                  批量合成
                </button>
              </div>
            </div>
```

- [ ] **Step 3: Update `doCompose` to pass the toggle flag**

Find `doCompose` (around line 2813):

```ts
async function doCompose(sb) {
  try {
    delete failedComposeMessages.value[sb.id]
    if (!isPendingCompose(sb.id)) pendingComposeIds.value.push(sb.id)
    await composeAPI.shot(sb.id)
```

Replace `await composeAPI.shot(sb.id)` with:

```ts
    await composeAPI.shot(sb.id, { enable_tts: composeTTSEnabled.value })
```

- [ ] **Step 4: Update `batchCompose` to pass the toggle flag**

Find `batchCompose` (around line 2846):

```ts
async function batchCompose() {
  await composeAPI.all(epId.value)
```

Replace `await composeAPI.all(epId.value)` with:

```ts
  await composeAPI.all(epId.value, { enable_tts: composeTTSEnabled.value })
```

- [ ] **Step 5: Run frontend build**

Run:

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/frontend && npm run build
```

Expected: build completes without errors.

- [ ] **Step 6: Commit**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add frontend/app/pages/drama/[id]/episode/[episodeNumber].vue
git commit -m "feat: add TTS toggle to compose tab"
```

---

### Task 5: Manual Verification

**Files:** No code changes.

- [ ] **Step 1: Start backend dev server**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/backend && npm run dev
```

Expected: backend starts on port 5679 with no errors.

- [ ] **Step 2: Start frontend dev server**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/frontend && npm run dev
```

Expected: Vite starts on port 3013.

- [ ] **Step 3: Verify default state (TTS enabled)**

Open the episode workbench and navigate to the compose tab. Confirm:

```text
- "合成时包含配音" checkbox is checked by default.
- Clicking "开始合成" on a storyboard with dialogue triggers the normal compose flow
  (check backend logs for AudioTask START tts-generate).
- Clicking "批量合成" sends enable_tts: true (or omits the field and defaults to true).
```

- [ ] **Step 4: Verify TTS disabled behavior**

Uncheck "合成时包含配音". Then:

```text
- Click "开始合成" on a storyboard with dialogue.
- Confirm backend logs do NOT show AudioTask START tts-generate.
- Confirm composed video file is created (check storyboards.composedVideoUrl or logs).
- Confirm composed video has no audio track (open file in a player and confirm no sound).
- Confirm subtitle is still burned in if the storyboard has dialogue (check video visually or log for subtitles= filter).
```

- [ ] **Step 5: Verify unrelated flows are unaffected**

```text
- Clicking "生成视频" still works as before (no enable_tts involved).
- Clicking the individual "生成配音" button on a storyboard still calls /generate-tts normally.
- Voice sample generation on a character still works.
```

- [ ] **Step 6: Run final backend typecheck and frontend build**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/backend && npm run typecheck
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/frontend && npm run build
```

Expected: both pass without errors.

---

## Self-Review

**Spec coverage:**
- ✅ Toggle only in compose tab — Task 4 places the checkbox in the compose section bar only.
- ✅ Default on — `composeTTSEnabled = ref(true)` and backend `enable_tts !== false` default.
- ✅ Off = skip TTS, keep subtitle — Task 1 uses `shouldGenerateAudio` for TTS only; subtitle block condition remains `!parsedDialogue.ignorable`.
- ✅ No DB changes — no schema modifications anywhere.
- ✅ Does not affect generate-tts endpoint — routes/compose.ts only, not storyboards.ts.
- ✅ Frontend build and backend typecheck in every task.

**Placeholder scan:** No TBDs, no "handle edge cases" without code, no "similar to Task N".

**Type consistency:**
- `ComposeOptions.enableTTS` (Task 1) matches usage in Task 2: `{ enableTTS }`.
- `composeAPI.shot(id, opts?: { enable_tts?: boolean })` (Task 3) matches call in Task 4: `{ enable_tts: composeTTSEnabled.value }`.
- `composeTTSEnabled` declared in Task 4 Step 1; used in Task 4 Steps 3 and 4.

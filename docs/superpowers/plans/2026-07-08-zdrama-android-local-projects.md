# ZdramaAndroid Local Projects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local project creation, list, and detail flow so users can create drama project drafts before Agnes generation is implemented.

**Architecture:** Use `SQLiteOpenHelper` for this phase because Room compiler/KAPT is intentionally disabled under the current AGP 4.2.2 + Kotlin 1.5.31 + Mac arm64 baseline. Keep the local store behind `DramaRepository` so a future Room migration does not affect UI code.

**Tech Stack:** Android Gradle Plugin 4.2.2, Gradle Wrapper 6.8.3-all, Kotlin 1.5.31, compileSdkVersion 33, targetSdkVersion 33, XML + ViewBinding, AppCompat, Material Components, SQLiteOpenHelper, RecyclerView.

## Global Constraints

- Android Gradle Plugin: `4.2.2`.
- Gradle Wrapper distribution: `gradle-6.8.3-all.zip`.
- Kotlin Gradle plugin: `1.5.31`.
- `compileSdkVersion 33`, `minSdkVersion 23`, `targetSdkVersion 33`.
- Build with JDK 11: `JAVA_HOME=/opt/homebrew/opt/openjdk@11 ./gradlew assembleDebug`.
- UI must use Android XML + ViewBinding; do not add Jetpack Compose.
- Use AndroidX Media2, not Media3.
- WorkManager must stay at `androidx.work:work-runtime-ktx:2.7.1` or newer compatible version to avoid Android S+ PendingIntent crashes.
- Do not enable Room compiler/KAPT in this phase.
- Do not implement Agnes text/image/video generation pipeline in this phase.
- Do not commit unless the user explicitly asks.

---

## File Structure

- Modify: `ZdramaAndroid/app/build.gradle` — add RecyclerView dependency if absent.
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/local/DramaLocalDatabase.kt` — SQLiteOpenHelper schema.
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/local/ProjectLocalDataSource.kt` — local CRUD operations.
- Modify: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/repository/DramaRepository.kt` — use local data source and expose project operations.
- Modify: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/domain/model/DramaModels.kt` — add `DramaProject` domain model.
- Modify: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/domain/usecase/CreateDramaUseCase.kt` — create draft project through repository.
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/domain/usecase/GetProjectsUseCase.kt` — list projects.
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/domain/usecase/GetProjectDetailUseCase.kt` — project detail.
- Modify: `ZdramaAndroid/app/src/main/res/values/strings.xml` — add create/list/detail strings.
- Create: `ZdramaAndroid/app/src/main/res/layout/activity_create_project.xml` — create form.
- Create: `ZdramaAndroid/app/src/main/res/layout/activity_project_list.xml` — list screen.
- Create: `ZdramaAndroid/app/src/main/res/layout/activity_project_detail.xml` — detail screen.
- Create: `ZdramaAndroid/app/src/main/res/layout/item_project.xml` — RecyclerView row.
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/ui/create/CreateProjectActivity.kt` — create project UI.
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/ui/project/ProjectListActivity.kt` — list UI.
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/ui/project/ProjectAdapter.kt` — RecyclerView adapter.
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/ui/project/ProjectDetailActivity.kt` — detail UI.
- Modify: `ZdramaAndroid/app/src/main/AndroidManifest.xml` — register activities.
- Modify: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/ui/main/MainActivity.kt` — route Create and Projects buttons.

---

## Tasks

### Task 1: Local Project Store

- [ ] Add RecyclerView dependency:

```groovy
implementation 'androidx.recyclerview:recyclerview:1.2.1'
```

- [ ] Create `DramaProject` domain model with all project draft fields.
- [ ] Create `DramaLocalDatabase` with a `projects` table matching `ProjectEntity` fields.
- [ ] Create `ProjectLocalDataSource` with `insertProject`, `getProjects`, `getProject`.
- [ ] Update `DramaRepository` to use `ProjectLocalDataSource`.
- [ ] Update create/get use cases.
- [ ] Verify build:

```bash
cd ZdramaAndroid
JAVA_HOME=/opt/homebrew/opt/openjdk@11 ./gradlew assembleDebug
```

Expected: `BUILD SUCCESSFUL`.

### Task 2: Create Project Screen

- [ ] Add strings for title, prompt, style, target audience, aspect ratio, shot count, duration, save.
- [ ] Create XML form with Material text inputs.
- [ ] Implement `CreateProjectActivity`, validating title and prompt are non-blank.
- [ ] On save, create project with `ProjectStatus.DRAFT` and `GenerationStage.NONE`, then finish.
- [ ] Verify build with the same command.

### Task 3: Project List And Detail Screens

- [ ] Add project row and list XML.
- [ ] Implement `ProjectAdapter`.
- [ ] Implement `ProjectListActivity` to load projects in `onResume` and open detail on tap.
- [ ] Implement `ProjectDetailActivity` showing title, prompt, style, audience, aspect ratio, shot count, duration, status, stage.
- [ ] Verify build with the same command.

### Task 4: Navigation And Final Verification

- [ ] Register create/list/detail activities in Manifest.
- [ ] Wire MainActivity Create and Projects buttons to real screens.
- [ ] Run final build.
- [ ] Confirm no stale `room-compiler`, `kotlin-kapt`, `media3`, or `work-runtime-ktx:2.6.0` references remain.

## Self-Review

- This plan creates a local project draft workflow only.
- It does not call Agnes generation APIs, start WorkManager jobs, generate images/videos, or implement playback.
- It preserves the current build constraints and avoids reintroducing Room compiler/KAPT.

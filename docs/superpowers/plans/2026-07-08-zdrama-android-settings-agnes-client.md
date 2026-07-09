# ZdramaAndroid Settings And Agnes Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the first usable Android feature slice: settings persistence for Agnes API/model configuration and a lightweight Agnes chat-completions connection test.

**Architecture:** Keep `ZdramaAndroid/` as a single-module Android app. Add a small settings data layer backed by encrypted/shared preferences, a traditional XML `SettingsActivity`, and a Retrofit client factory wired to the existing `AgnesApiService` and `AgnesAuthInterceptor` skeletons.

**Tech Stack:** Android Gradle Plugin 4.2.2, Gradle Wrapper 6.8.3-all, Kotlin 1.5.31, compileSdkVersion 33, targetSdkVersion 33, XML + ViewBinding, AppCompat, Material Components, Retrofit/OkHttp/Gson, AndroidX Security Crypto.

## Global Constraints

- Android Gradle Plugin: `4.2.2`.
- Gradle Wrapper distribution: `gradle-6.8.3-all.zip`.
- Kotlin Gradle plugin: `1.5.31`.
- `compileSdkVersion 33`, `minSdkVersion 23`, `targetSdkVersion 33`.
- Build with JDK 11: `JAVA_HOME=/opt/homebrew/opt/openjdk@11 ./gradlew assembleDebug`.
- UI must use Android XML + ViewBinding; do not add Jetpack Compose.
- Use AndroidX Media2, not Media3.
- Do not enable Room compiler/KAPT in this phase.
- Do not implement full text/image/video generation pipeline in this phase.
- Do not commit unless the user explicitly asks.

---

## File Structure

Create or modify these files:

- Modify: `ZdramaAndroid/app/build.gradle` — add AndroidX Security Crypto dependency.
- Modify: `ZdramaAndroid/app/src/main/AndroidManifest.xml` — declare `SettingsActivity`.
- Modify: `ZdramaAndroid/app/src/main/res/values/strings.xml` — add settings labels and messages.
- Create: `ZdramaAndroid/app/src/main/res/layout/activity_settings.xml` — settings screen XML.
- Modify: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/ui/main/MainActivity.kt` — open settings screen.
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/settings/AgnesSettings.kt` — immutable settings model and defaults.
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/settings/AgnesSettingsStore.kt` — encrypted/shared preference persistence.
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/remote/AgnesClientFactory.kt` — Retrofit/OkHttp builder from settings.
- Modify: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/remote/AgnesApiService.kt` — add lightweight chat DTO compatibility only if needed.
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/repository/AgnesConnectionRepository.kt` — connection test boundary.
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/domain/usecase/TestAgnesConnectionUseCase.kt` — use case for settings screen.
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/ui/settings/SettingsActivity.kt` — settings form and actions.
- Modify: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/ui/settings/SettingsPlaceholder.kt` — keep route marker or remove if unused.

---

### Task 1: Settings Model And Persistence

**Files:**
- Modify: `ZdramaAndroid/app/build.gradle`
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/settings/AgnesSettings.kt`
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/settings/AgnesSettingsStore.kt`

**Interfaces:**
- Produces: `data class AgnesSettings`, `class AgnesSettingsStore`, `fun load(): AgnesSettings`, `fun save(settings: AgnesSettings)`, `fun hasApiKey(): Boolean`.
- Later tasks consume these settings to build Retrofit and populate the UI.

- [ ] **Step 1: Add AndroidX Security Crypto and lifecycle runtime dependencies**

Modify `ZdramaAndroid/app/build.gradle` dependencies block by adding:

```groovy
implementation 'androidx.lifecycle:lifecycle-runtime-ktx:2.3.1'
implementation 'androidx.security:security-crypto:1.1.0-alpha03'
```

Keep `room-runtime:2.3.0` runtime-only and do not add `kotlin-kapt`.

- [ ] **Step 2: Create settings model**

Create `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/settings/AgnesSettings.kt`:

```kotlin
package com.huobao.zdrama.data.settings

data class AgnesSettings(
    val apiKey: String,
    val baseUrl: String,
    val textModel: String,
    val imageModel: String,
    val videoModel: String,
    val requestTimeoutSeconds: Long
) {
    companion object {
        const val DEFAULT_BASE_URL = "https://apihub.agnes-ai.com/"
        const val DEFAULT_IMAGE_MODEL = "agnes-image-2.0-flash"
        const val DEFAULT_VIDEO_MODEL = "agnes-video-v2.0"
        const val DEFAULT_TIMEOUT_SECONDS = 120L

        fun defaults(): AgnesSettings {
            return AgnesSettings(
                apiKey = "",
                baseUrl = DEFAULT_BASE_URL,
                textModel = "",
                imageModel = DEFAULT_IMAGE_MODEL,
                videoModel = DEFAULT_VIDEO_MODEL,
                requestTimeoutSeconds = DEFAULT_TIMEOUT_SECONDS
            )
        }
    }
}
```

- [ ] **Step 3: Create settings store**

Create `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/settings/AgnesSettingsStore.kt`:

```kotlin
package com.huobao.zdrama.data.settings

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys

class AgnesSettingsStore(context: Context) {
    private val appContext = context.applicationContext
    private val securePreferences: SharedPreferences by lazy { createSecurePreferences() }
    private val plainPreferences: SharedPreferences by lazy {
        appContext.getSharedPreferences(PLAIN_PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun load(): AgnesSettings {
        val defaults = AgnesSettings.defaults()
        return AgnesSettings(
            apiKey = securePreferences.getString(KEY_API_KEY, defaults.apiKey).orEmpty(),
            baseUrl = plainPreferences.getString(KEY_BASE_URL, defaults.baseUrl).orEmpty().ifBlank { defaults.baseUrl },
            textModel = plainPreferences.getString(KEY_TEXT_MODEL, defaults.textModel).orEmpty(),
            imageModel = plainPreferences.getString(KEY_IMAGE_MODEL, defaults.imageModel).orEmpty().ifBlank { defaults.imageModel },
            videoModel = plainPreferences.getString(KEY_VIDEO_MODEL, defaults.videoModel).orEmpty().ifBlank { defaults.videoModel },
            requestTimeoutSeconds = plainPreferences.getLong(KEY_TIMEOUT_SECONDS, defaults.requestTimeoutSeconds)
        )
    }

    fun save(settings: AgnesSettings) {
        securePreferences.edit()
            .putString(KEY_API_KEY, settings.apiKey.trim())
            .apply()
        plainPreferences.edit()
            .putString(KEY_BASE_URL, normalizeBaseUrl(settings.baseUrl))
            .putString(KEY_TEXT_MODEL, settings.textModel.trim())
            .putString(KEY_IMAGE_MODEL, settings.imageModel.trim())
            .putString(KEY_VIDEO_MODEL, settings.videoModel.trim())
            .putLong(KEY_TIMEOUT_SECONDS, settings.requestTimeoutSeconds)
            .apply()
    }

    fun hasApiKey(): Boolean {
        return load().apiKey.isNotBlank()
    }

    private fun createSecurePreferences(): SharedPreferences {
        val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
        return EncryptedSharedPreferences.create(
            SECURE_PREFS_NAME,
            masterKeyAlias,
            appContext,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    private fun normalizeBaseUrl(value: String): String {
        val trimmed = value.trim().ifBlank { AgnesSettings.DEFAULT_BASE_URL }
        return if (trimmed.endsWith("/")) trimmed else "$trimmed/"
    }

    companion object {
        private const val SECURE_PREFS_NAME = "agnes_secure_settings"
        private const val PLAIN_PREFS_NAME = "agnes_plain_settings"
        private const val KEY_API_KEY = "api_key"
        private const val KEY_BASE_URL = "base_url"
        private const val KEY_TEXT_MODEL = "text_model"
        private const val KEY_IMAGE_MODEL = "image_model"
        private const val KEY_VIDEO_MODEL = "video_model"
        private const val KEY_TIMEOUT_SECONDS = "timeout_seconds"
    }
}
```

- [ ] **Step 4: Build verify**

Run:

```bash
cd ZdramaAndroid
JAVA_HOME=/opt/homebrew/opt/openjdk@11 ./gradlew assembleDebug
```

Expected: `BUILD SUCCESSFUL`.

---

### Task 2: Agnes Client Factory And Connection Test Boundary

**Files:**
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/remote/AgnesClientFactory.kt`
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/repository/AgnesConnectionRepository.kt`
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/domain/usecase/TestAgnesConnectionUseCase.kt`

**Interfaces:**
- Consumes: `AgnesSettings`, `AgnesApiService`, `AgnesAuthInterceptor`.
- Produces: `AgnesClientFactory.create(settings: AgnesSettings): AgnesApiService`, `AgnesConnectionRepository.testTextModel(settings: AgnesSettings): Result<Unit>`, `TestAgnesConnectionUseCase.execute(settings: AgnesSettings): Result<Unit>`.

- [ ] **Step 1: Create Retrofit client factory**

Create `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/remote/AgnesClientFactory.kt`:

```kotlin
package com.huobao.zdrama.data.remote

import com.google.gson.GsonBuilder
import com.huobao.zdrama.data.settings.AgnesSettings
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit

class AgnesClientFactory {
    fun create(settings: AgnesSettings): AgnesApiService {
        val loggingInterceptor = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BASIC
        }
        val okHttpClient = OkHttpClient.Builder()
            .addInterceptor(AgnesAuthInterceptor(object : ApiKeyProvider {
                override fun getApiKey(): String? = settings.apiKey
            }))
            .addInterceptor(loggingInterceptor)
            .connectTimeout(settings.requestTimeoutSeconds, TimeUnit.SECONDS)
            .readTimeout(settings.requestTimeoutSeconds, TimeUnit.SECONDS)
            .writeTimeout(settings.requestTimeoutSeconds, TimeUnit.SECONDS)
            .build()

        val gson = GsonBuilder().create()
        return Retrofit.Builder()
            .baseUrl(normalizeBaseUrl(settings.baseUrl))
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create(gson))
            .build()
            .create(AgnesApiService::class.java)
    }

    private fun normalizeBaseUrl(value: String): String {
        val trimmed = value.trim().ifBlank { AgnesSettings.DEFAULT_BASE_URL }
        return if (trimmed.endsWith("/")) trimmed else "$trimmed/"
    }
}
```

- [ ] **Step 2: Create connection repository**

Create `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/data/repository/AgnesConnectionRepository.kt`:

```kotlin
package com.huobao.zdrama.data.repository

import com.huobao.zdrama.data.remote.AgnesClientFactory
import com.huobao.zdrama.data.remote.ChatCompletionRequest
import com.huobao.zdrama.data.remote.ChatMessage
import com.huobao.zdrama.data.settings.AgnesSettings

class AgnesConnectionRepository(
    private val clientFactory: AgnesClientFactory = AgnesClientFactory()
) {
    suspend fun testTextModel(settings: AgnesSettings): Result<Unit> {
        if (settings.apiKey.isBlank()) {
            return Result.failure(IllegalArgumentException("Agnes API Key is required"))
        }
        if (settings.textModel.isBlank()) {
            return Result.failure(IllegalArgumentException("Text model is required"))
        }
        return runCatching {
            val service = clientFactory.create(settings)
            service.createChatCompletion(
                ChatCompletionRequest(
                    model = settings.textModel,
                    messages = listOf(ChatMessage(role = "user", content = "ping")),
                    temperature = 0.0,
                    max_tokens = 8
                )
            )
        }.map { Unit }
    }
}
```

- [ ] **Step 3: Create use case**

Create `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/domain/usecase/TestAgnesConnectionUseCase.kt`:

```kotlin
package com.huobao.zdrama.domain.usecase

import com.huobao.zdrama.data.repository.AgnesConnectionRepository
import com.huobao.zdrama.data.settings.AgnesSettings

class TestAgnesConnectionUseCase(
    private val repository: AgnesConnectionRepository = AgnesConnectionRepository()
) {
    suspend fun execute(settings: AgnesSettings): Result<Unit> {
        return repository.testTextModel(settings)
    }
}
```

- [ ] **Step 4: Build verify**

Run:

```bash
cd ZdramaAndroid
JAVA_HOME=/opt/homebrew/opt/openjdk@11 ./gradlew assembleDebug
```

Expected: `BUILD SUCCESSFUL`.

---

### Task 3: Settings Screen UI

**Files:**
- Modify: `ZdramaAndroid/app/src/main/res/values/strings.xml`
- Create: `ZdramaAndroid/app/src/main/res/layout/activity_settings.xml`
- Create: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/ui/settings/SettingsActivity.kt`
- Modify: `ZdramaAndroid/app/src/main/AndroidManifest.xml`
- Modify: `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/ui/main/MainActivity.kt`

**Interfaces:**
- Consumes: `AgnesSettingsStore`, `TestAgnesConnectionUseCase`.
- Produces: A launchable Settings screen that loads/saves config and runs lightweight text-model test.

- [ ] **Step 1: Add strings**

Add these entries to `ZdramaAndroid/app/src/main/res/values/strings.xml`:

```xml
<string name="settings_title">Agnes Settings</string>
<string name="settings_api_key">API Key</string>
<string name="settings_base_url">Base URL</string>
<string name="settings_text_model">Text model</string>
<string name="settings_image_model">Image model</string>
<string name="settings_video_model">Video model</string>
<string name="settings_save">Save</string>
<string name="settings_test_text_model">Test Text Model</string>
<string name="settings_saved">Settings saved</string>
<string name="settings_test_success">Connection test succeeded</string>
<string name="settings_test_failed">Connection test failed</string>
```

- [ ] **Step 2: Create settings layout**

Create `ZdramaAndroid/app/src/main/res/layout/activity_settings.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@color/zdrama_black">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:padding="24dp">

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="@string/settings_title"
            android:textColor="@color/zdrama_text_primary"
            android:textSize="24sp"
            android:textStyle="bold" />

        <com.google.android.material.textfield.TextInputLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="20dp"
            android:hint="@string/settings_api_key"
            app:endIconMode="password_toggle">

            <com.google.android.material.textfield.TextInputEditText
                android:id="@+id/apiKeyInput"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:inputType="textPassword" />
        </com.google.android.material.textfield.TextInputLayout>

        <com.google.android.material.textfield.TextInputLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="12dp"
            android:hint="@string/settings_base_url">

            <com.google.android.material.textfield.TextInputEditText
                android:id="@+id/baseUrlInput"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:inputType="textUri" />
        </com.google.android.material.textfield.TextInputLayout>

        <com.google.android.material.textfield.TextInputLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="12dp"
            android:hint="@string/settings_text_model">

            <com.google.android.material.textfield.TextInputEditText
                android:id="@+id/textModelInput"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:inputType="text" />
        </com.google.android.material.textfield.TextInputLayout>

        <com.google.android.material.textfield.TextInputLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="12dp"
            android:hint="@string/settings_image_model">

            <com.google.android.material.textfield.TextInputEditText
                android:id="@+id/imageModelInput"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:inputType="text" />
        </com.google.android.material.textfield.TextInputLayout>

        <com.google.android.material.textfield.TextInputLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="12dp"
            android:hint="@string/settings_video_model">

            <com.google.android.material.textfield.TextInputEditText
                android:id="@+id/videoModelInput"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:inputType="text" />
        </com.google.android.material.textfield.TextInputLayout>

        <com.google.android.material.button.MaterialButton
            android:id="@+id/saveButton"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="20dp"
            android:text="@string/settings_save" />

        <com.google.android.material.button.MaterialButton
            android:id="@+id/testTextModelButton"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="12dp"
            android:text="@string/settings_test_text_model" />
    </LinearLayout>
</ScrollView>
```

- [ ] **Step 3: Create SettingsActivity**

Create `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/ui/settings/SettingsActivity.kt`:

```kotlin
package com.huobao.zdrama.ui.settings

import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.huobao.zdrama.R
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.data.settings.AgnesSettingsStore
import com.huobao.zdrama.databinding.ActivitySettingsBinding
import com.huobao.zdrama.domain.usecase.TestAgnesConnectionUseCase
import kotlinx.coroutines.launch

class SettingsActivity : AppCompatActivity() {
    private lateinit var binding: ActivitySettingsBinding
    private lateinit var settingsStore: AgnesSettingsStore
    private val testConnectionUseCase = TestAgnesConnectionUseCase()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        settingsStore = AgnesSettingsStore(this)
        render(settingsStore.load())

        binding.saveButton.setOnClickListener {
            settingsStore.save(readForm())
            Toast.makeText(this, R.string.settings_saved, Toast.LENGTH_SHORT).show()
        }
        binding.testTextModelButton.setOnClickListener {
            testTextModel()
        }
    }

    private fun render(settings: AgnesSettings) {
        binding.apiKeyInput.setText(settings.apiKey)
        binding.baseUrlInput.setText(settings.baseUrl)
        binding.textModelInput.setText(settings.textModel)
        binding.imageModelInput.setText(settings.imageModel)
        binding.videoModelInput.setText(settings.videoModel)
    }

    private fun readForm(): AgnesSettings {
        return AgnesSettings(
            apiKey = binding.apiKeyInput.text?.toString().orEmpty(),
            baseUrl = binding.baseUrlInput.text?.toString().orEmpty(),
            textModel = binding.textModelInput.text?.toString().orEmpty(),
            imageModel = binding.imageModelInput.text?.toString().orEmpty(),
            videoModel = binding.videoModelInput.text?.toString().orEmpty(),
            requestTimeoutSeconds = AgnesSettings.DEFAULT_TIMEOUT_SECONDS
        )
    }

    private fun testTextModel() {
        val settings = readForm()
        settingsStore.save(settings)
        binding.testTextModelButton.isEnabled = false
        lifecycleScope.launch {
            val result = testConnectionUseCase.execute(settings)
            binding.testTextModelButton.isEnabled = true
            val messageRes = if (result.isSuccess) {
                R.string.settings_test_success
            } else {
                R.string.settings_test_failed
            }
            Toast.makeText(this@SettingsActivity, messageRes, Toast.LENGTH_SHORT).show()
        }
    }
}
```

- [ ] **Step 4: Register activity**

Add this activity inside the `<application>` block in `AndroidManifest.xml` before `MainActivity`:

```xml
<activity
    android:name=".ui.settings.SettingsActivity"
    android:exported="false" />
```

- [ ] **Step 5: Wire main settings button**

Modify `MainActivity.kt` to import `Intent` and `SettingsActivity`, then open the screen:

```kotlin
import android.content.Intent
import com.huobao.zdrama.ui.settings.SettingsActivity
```

Replace:

```kotlin
binding.settingsButton.setOnClickListener { showPlaceholder("Settings") }
```

with:

```kotlin
binding.settingsButton.setOnClickListener {
    startActivity(Intent(this, SettingsActivity::class.java))
}
```

Keep the Create and Projects placeholder toasts.

- [ ] **Step 6: Build verify**

Run:

```bash
cd ZdramaAndroid
JAVA_HOME=/opt/homebrew/opt/openjdk@11 ./gradlew assembleDebug
```

Expected: `BUILD SUCCESSFUL`.

---

## Self-Review

- Spec coverage: This plan implements the next Android plan steps for settings configuration and Agnes API client setup only. It does not implement the full generation pipeline, image/video polling, WorkManager orchestration, or player flow.
- Compatibility: The plan preserves AGP 4.2.2, Gradle 6.8.3-all, Kotlin 1.5.31, SDK 33, XML/ViewBinding, Media2, no Compose, no Room KAPT.
- Security: API Key is saved with `EncryptedSharedPreferences`; non-secret model/base URL values use regular SharedPreferences.
- Build verification: Every task ends with `JAVA_HOME=/opt/homebrew/opt/openjdk@11 ./gradlew assembleDebug` because Gradle 6.8.3 does not run on the default JDK 17.

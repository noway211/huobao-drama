package com.huobao.zdrama.domain.usecase

import android.util.Log
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.huobao.zdrama.data.repository.AgnesImageRepository
import com.huobao.zdrama.data.repository.DramaRepository
import com.huobao.zdrama.data.repository.MediaDownloadRepository
import com.huobao.zdrama.data.settings.AgnesSettings
import com.huobao.zdrama.domain.model.AssetStatus
import com.huobao.zdrama.domain.model.Character
import com.huobao.zdrama.domain.model.GenerationStage
import com.huobao.zdrama.domain.model.ProjectStatus
import com.huobao.zdrama.domain.model.StoryboardShot
import java.io.File

class GenerateStoryboardImagesUseCase(
    private val dramaRepository: DramaRepository,
    private val agnesImageRepository: AgnesImageRepository,
    private val mediaDownloadRepository: MediaDownloadRepository
) {
    private val gson = Gson()

    /** 角色参考信息（buildCharacterReferences 返回值）。 */
    private data class CharacterRefInfo(
        val referenceUrls: List<String>,
        val characterText: String
    )
    suspend fun execute(projectId: Long, settings: AgnesSettings): Result<Int> {
        val project = dramaRepository.getProject(projectId)
            ?: return Result.failure(IllegalArgumentException("Project not found"))
        val shots = dramaRepository.getStoryboards(projectId)
        if (shots.isEmpty()) {
            return Result.failure(IllegalArgumentException("Generate storyboards before images"))
        }

        // 自动修复触发内容审查的提示词（与 Harmony 端同步）
        patchSensitivePrompts(shots)

        dramaRepository.updateProjectTextResult(
            projectId = projectId,
            status = ProjectStatus.PROCESSING,
            currentStage = GenerationStage.IMAGE,
            generatedScript = project.generatedScript,
            errorMessage = null
        )

        var completed = 0
        var generated = 0
        var firstError: Throwable? = null
        for (shot in shots) {
            if (shot.imageStatus == AssetStatus.COMPLETED && isExistingLocalFile(shot.imageLocalPath)) {
                completed += 1
                continue
            }

            dramaRepository.updateShotImage(
                shotId = shot.id,
                imageStatus = AssetStatus.PROCESSING,
                imageUrl = shot.imageUrl,
                imageLocalPath = shot.imageLocalPath,
                imageErrorMessage = null
            )

            // 收集分镜绑定角色的参考图，并为其生成 "reference image N" 绑定前缀文本
            val charRef = buildCharacterReferences(projectId, shot)
            val enrichedPrompt = if (charRef.characterText.isNotEmpty()) {
                "${charRef.characterText}${shot.imagePrompt}"
            } else {
                shot.imagePrompt
            }
            Log.d(TAG, "shot #${shot.shotNumber} image: refs=${charRef.referenceUrls.size} enriched=${charRef.characterText.isNotEmpty()}")

            val imageResult = agnesImageRepository.generateImage(
                settings = settings,
                prompt = enrichedPrompt,
                referenceImages = charRef.referenceUrls
            )
            if (imageResult.isSuccess) {
                val imageUrl = imageResult.getOrThrow()
                val downloadResult = mediaDownloadRepository.downloadToGeneratedMedia(
                    projectId = projectId,
                    shotId = shot.id,
                    url = imageUrl,
                    mediaType = MediaDownloadRepository.MediaType.IMAGE
                )
                if (downloadResult.isSuccess) {
                    completed += 1
                    generated += 1
                    dramaRepository.updateShotImage(
                        shotId = shot.id,
                        imageStatus = AssetStatus.COMPLETED,
                        imageUrl = imageUrl,
                        imageLocalPath = downloadResult.getOrThrow(),
                        imageErrorMessage = null
                    )
                } else {
                    val throwable = downloadResult.exceptionOrNull() ?: IllegalStateException("Image download failed")
                    if (firstError == null) firstError = throwable
                    dramaRepository.updateShotImage(
                        shotId = shot.id,
                        imageStatus = AssetStatus.FAILED,
                        imageUrl = imageUrl,
                        imageLocalPath = shot.imageLocalPath,
                        imageErrorMessage = throwable.message
                    )
                }
            } else {
                val throwable = imageResult.exceptionOrNull() ?: IllegalStateException("Image generation failed")
                if (firstError == null) firstError = throwable
                dramaRepository.updateShotImage(
                    shotId = shot.id,
                    imageStatus = AssetStatus.FAILED,
                    imageUrl = shot.imageUrl,
                    imageLocalPath = shot.imageLocalPath,
                    imageErrorMessage = throwable.message
                )
            }
        }

        val finalStatus = if (completed == shots.size) ProjectStatus.COMPLETED else ProjectStatus.FAILED
        dramaRepository.updateProjectTextResult(
            projectId = projectId,
            status = finalStatus,
            currentStage = GenerationStage.IMAGE,
            generatedScript = project.generatedScript,
            errorMessage = firstError?.message
        )

        return if (completed > 0) Result.success(generated) else Result.failure(
            firstError ?: IllegalStateException("Image generation failed")
        )
    }

    private fun isExistingLocalFile(path: String?): Boolean {
        return !path.isNullOrBlank() && File(path).exists()
    }

    private fun isExistingNonEmptyFile(path: String?): Boolean {
        if (path.isNullOrBlank()) return false
        val file = File(path)
        return file.exists() && file.length() > 0
    }

    /**
     * 收集分镜关联角色的参考图，并为每张参考图生成 "reference image N" 绑定前缀。
     * characterText 中每条形如 "The person in reference image N is <Name> (<Appearance>)."
     * 与 referenceUrls[N-1] 一一对应，弥补 extra_body.image 不支持 per-image 标签的 API 限制。
     * 移植自 Harmony 端 UseCases.buildCharacterReferences。
     */
    private suspend fun buildCharacterReferences(projectId: Long, shot: StoryboardShot): CharacterRefInfo {
        val refs = mutableListOf<String>()
        val descLines = mutableListOf<String>()

        val allCharacters = dramaRepository.getCharacters(projectId)
        if (allCharacters.isEmpty()) {
            return CharacterRefInfo(emptyList(), "")
        }

        // 统一 ID / 名字两条路径：优先按数字 ID 查表，回退到字符串名查表
        val resolved = resolveCharacters(shot.characterIds, allCharacters)

        for (ch in resolved) {
            if (refs.size >= 3) break

            val refUrl = if (isExistingNonEmptyFile(ch.imageLocalPath)) ch.imageLocalPath else ch.imageUrl
            // Atomic：refUrl 与 appearance 缺一就跳过该角色，避免数组错位
            if (refUrl.isNullOrBlank() || ch.appearance.isBlank()) continue

            refs.add(refUrl)
            descLines.add("The person in reference image ${refs.size} is ${ch.name} (${ch.appearance}).")
        }

        val characterText = if (descLines.isNotEmpty()) descLines.joinToString(" ") + "\n" else ""
        return CharacterRefInfo(refs, characterText)
    }

    /**
     * 将 shot.characterIds 解析为 Character[]。优先按数字 ID 查表，回退到字符串名查表。
     * 未匹配的 ID/name 静默跳过。空输入返回空列表。移植自 Harmony 端 UseCases.resolveCharacters。
     */
    private fun resolveCharacters(characterIds: String?, allCharacters: List<Character>): List<Character> {
        if (allCharacters.isEmpty()) return emptyList()

        // 路径 1：按数字 ID 查表
        val numericIds = parseCharacterIds(characterIds)
        if (numericIds.isNotEmpty()) {
            val charMap = allCharacters.associateBy { it.id }
            val out = numericIds.mapNotNull { charMap[it] }
            if (out.isNotEmpty()) return out
        }

        // 路径 2：按字符串名查表（fallback）
        val names = parseCharacterNames(characterIds)
        if (names.isNullOrEmpty()) return emptyList()
        val nameMap = allCharacters.associateBy { it.name }
        return names.mapNotNull { nameMap[it] }
    }

    /** 从 characterIds JSON 中解析数字 ID 数组；混合/字符串数组返回空（走名字 fallback）。 */
    private fun parseCharacterIds(characterIds: String?): List<Long> {
        if (characterIds.isNullOrBlank()) return emptyList()
        val type = object : TypeToken<ArrayList<Long>>() {}.type
        return runCatching { gson.fromJson<ArrayList<Long>>(characterIds, type) }
            .getOrNull()?.toList() ?: emptyList()
    }

    /** 从 characterIds JSON 中解析名字字符串数组（非字符串内容返回 null）。 */
    private fun parseCharacterNames(characterIds: String?): List<String>? {
        if (characterIds.isNullOrBlank()) return null
        val type = object : TypeToken<ArrayList<String>>() {}.type
        return runCatching { gson.fromJson<ArrayList<String>>(characterIds, type) }
            .getOrNull()?.toList()
    }

    companion object {
        private const val TAG = "GenerateStoryboardImagesUseCase"
    }

    /** 自动替换触发内容审查的敏感词，对齐 Harmony 端 patchSensitivePrompts。 */
    private suspend fun patchSensitivePrompts(shots: List<StoryboardShot>) {
        for (shot in shots) {
            val old1 = "走廊尽头传来脚步声，老师快步走来，身后跟着校警，众人瞬间安静，学校走廊场景，写实风格"
            if (shot.imagePrompt == old1) {
                dramaRepository.updateShotImagePrompt(shot.id,
                    "走廊尽头传来脚步声，老师快步走来，严厉地扫视全场，霸凌者心虚地低下头，众人不敢出声，学校走廊场景，写实风格")
            }
            val old2 = "校警将霸凌者带离走廊"
            if (shot.imagePrompt.contains(old2)) {
                dramaRepository.updateShotImagePrompt(shot.id,
                    shot.imagePrompt.replace(old2, "老师带着霸凌者离开走廊"))
            }
            if (shot.videoPrompt.contains(old2)) {
                dramaRepository.updateShotVideoPrompt(shot.id,
                    shot.videoPrompt.replace(old2, "老师带着霸凌者离开走廊"))
            }
        }
    }
}

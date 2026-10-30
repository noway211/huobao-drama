package com.huobao.zdrama.data.local

import com.huobao.zdrama.domain.model.Scene

/**
 * 场景去重规则，和 SQLite 写入使用同一套判断：
 * 地点和时间都相同则更新氛围和提示词并保留 id；否则插入新行。
 */
object SceneDeduper {
    fun upsert(existing: List<Scene>, incoming: List<Scene>, now: Long): List<Scene> {
        val stored = existing.toMutableList()
        incoming.forEach { scene ->
            val index = stored.indexOfFirst { it.location == scene.location && it.time == scene.time }
            if (index >= 0) {
                val match = stored[index]
                stored[index] = match.copy(
                    atmosphere = scene.atmosphere,
                    prompt = scene.prompt,
                    updatedAt = now
                )
            } else {
                val nextId = (stored.maxOfOrNull { it.id } ?: 0L) + 1L
                stored.add(scene.copy(id = nextId, createdAt = now, updatedAt = now))
            }
        }
        return stored
    }
}

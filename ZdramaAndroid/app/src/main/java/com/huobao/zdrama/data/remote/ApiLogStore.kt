package com.huobao.zdrama.data.remote

/** 单条 API 调用记录。 */
data class ApiLogEntry(
    val timestamp: Long,
    val method: String,
    val url: String,
    val statusCode: Int?,
    val durationMs: Long,
    val requestBody: String?,
    val responseBody: String?,
    val errorMessage: String?,
    val isSuccess: Boolean
)

/**
 * 内存环形缓冲,记录最近的 API 调用(所有项目共享)。
 * 仅内存,App 重启后清空。线程安全。
 */
object ApiLogStore {
    private const val MAX_ENTRIES = 100
    private val entries = ArrayDeque<ApiLogEntry>()
    private val lock = Any()

    fun add(entry: ApiLogEntry) {
        synchronized(lock) {
            entries.addLast(entry)
            while (entries.size > MAX_ENTRIES) {
                entries.removeFirst()
            }
        }
    }

    /** 返回倒序副本(最新在前)。 */
    fun snapshot(): List<ApiLogEntry> {
        synchronized(lock) {
            return entries.reversed()
        }
    }

    fun clear() {
        synchronized(lock) {
            entries.clear()
        }
    }
}

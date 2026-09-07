package com.huobao.zdrama.data.media

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.util.Log
import java.io.File
import java.nio.ByteBuffer

class LocalMp4Composer {
    fun compose(inputPaths: List<String>, outputPath: String): Result<String> {
        val outputFile = File(outputPath)
        return runCatching {
            val inputFiles = validateInputFiles(inputPaths)
            val trackInfos = inputFiles.map { file -> readTrackInfo(file) }
            val firstInfo = trackInfos.first()
            trackInfos.drop(1).forEach { info -> validateCompatible(firstInfo, info) }

            outputFile.parentFile?.mkdirs()
            if (outputFile.exists()) outputFile.delete()

            var muxer: MediaMuxer? = null
            try {
                muxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                val outputVideoTrack = muxer.addTrack(firstInfo.video.format)
                val outputAudioTrack = firstInfo.audio?.let { muxer.addTrack(it.format) }
                muxer.setOrientationHint(firstInfo.rotationDegrees)
                muxer.start()

                copyTrackSamples(
                    inputFiles = inputFiles,
                    inputTrackType = TrackType.VIDEO,
                    outputTrackIndex = outputVideoTrack,
                    muxer = muxer
                )
                if (outputAudioTrack != null) {
                    copyTrackSamples(
                        inputFiles = inputFiles,
                        inputTrackType = TrackType.AUDIO,
                        outputTrackIndex = outputAudioTrack,
                        muxer = muxer
                    )
                }
            } catch (throwable: Throwable) {
                outputFile.delete()
                throw IllegalStateException(throwable.message ?: ERROR_WRITE_FAILED, throwable)
            } finally {
                runCatching { muxer?.stop() }.onFailure { Log.e(TAG, "muxer.stop() failed", it) }
                runCatching { muxer?.release() }
            }

            outputFile.absolutePath
        }
    }

    private fun validateInputFiles(inputPaths: List<String>): List<File> {
        if (inputPaths.isEmpty()) throw IllegalArgumentException("请先生成并下载全部分镜视频后再合成成片")
        return inputPaths.mapIndexed { index, path ->
            val file = File(path)
            if (path.isBlank() || !file.exists() || !file.canRead()) {
                throw IllegalArgumentException("分镜 #${index + 1} 的本地视频不存在，请重新生成视频")
            }
            file
        }
    }

    private fun readTrackInfo(file: File): SourceTrackInfo {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(file.absolutePath)
            var video: TrackInfo? = null
            var audio: TrackInfo? = null
            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(MediaFormat.KEY_MIME).orEmpty()
                when {
                    mime.startsWith("video/") && video == null -> video = TrackInfo(index, format)
                    mime.startsWith("audio/") && audio == null -> audio = TrackInfo(index, format)
                }
            }
            val videoTrack = video ?: throw IllegalArgumentException(ERROR_MISSING_VIDEO_TRACK)
            return SourceTrackInfo(
                video = videoTrack,
                audio = audio,
                rotationDegrees = getOptionalInteger(videoTrack.format, MediaFormat.KEY_ROTATION, 0)
            )
        } finally {
            extractor.release()
        }
    }

    private fun validateCompatible(reference: SourceTrackInfo, candidate: SourceTrackInfo) {
        if (!isVideoCompatible(reference.video.format, candidate.video.format)) {
            throw IllegalArgumentException(ERROR_INCOMPATIBLE_FORMAT)
        }
        val referenceAudio = reference.audio
        val candidateAudio = candidate.audio
        if ((referenceAudio == null) != (candidateAudio == null)) {
            throw IllegalArgumentException(ERROR_INCOMPATIBLE_FORMAT)
        }
        if (referenceAudio != null && candidateAudio != null && !isAudioCompatible(referenceAudio.format, candidateAudio.format)) {
            throw IllegalArgumentException(ERROR_INCOMPATIBLE_FORMAT)
        }
    }

    private fun isVideoCompatible(reference: MediaFormat, candidate: MediaFormat): Boolean {
        return reference.getString(MediaFormat.KEY_MIME) == candidate.getString(MediaFormat.KEY_MIME) &&
            getOptionalInteger(reference, MediaFormat.KEY_WIDTH, -1) == getOptionalInteger(candidate, MediaFormat.KEY_WIDTH, -2) &&
            getOptionalInteger(reference, MediaFormat.KEY_HEIGHT, -1) == getOptionalInteger(candidate, MediaFormat.KEY_HEIGHT, -2) &&
            getOptionalInteger(reference, MediaFormat.KEY_ROTATION, 0) == getOptionalInteger(candidate, MediaFormat.KEY_ROTATION, 0)
    }

    private fun isAudioCompatible(reference: MediaFormat, candidate: MediaFormat): Boolean {
        return reference.getString(MediaFormat.KEY_MIME) == candidate.getString(MediaFormat.KEY_MIME) &&
            getOptionalInteger(reference, MediaFormat.KEY_SAMPLE_RATE, -1) == getOptionalInteger(candidate, MediaFormat.KEY_SAMPLE_RATE, -2) &&
            getOptionalInteger(reference, MediaFormat.KEY_CHANNEL_COUNT, -1) == getOptionalInteger(candidate, MediaFormat.KEY_CHANNEL_COUNT, -2)
    }

    private fun copyTrackSamples(
        inputFiles: List<File>,
        inputTrackType: TrackType,
        outputTrackIndex: Int,
        muxer: MediaMuxer
    ) {
        var timeOffsetUs = 0L
        var lastOutputTimeUs = -1L
        inputFiles.forEach { file ->
            val extractor = MediaExtractor()
            try {
                extractor.setDataSource(file.absolutePath)
                val inputTrackIndex = findTrackIndex(extractor, inputTrackType)
                    ?: throw IllegalArgumentException(if (inputTrackType == TrackType.VIDEO) ERROR_MISSING_VIDEO_TRACK else ERROR_INCOMPATIBLE_FORMAT)
                val format = extractor.getTrackFormat(inputTrackIndex)
                val buffer = ByteBuffer.allocate(getOptionalInteger(format, MediaFormat.KEY_MAX_INPUT_SIZE, DEFAULT_BUFFER_SIZE))
                val bufferInfo = MediaCodec.BufferInfo()
                extractor.selectTrack(inputTrackIndex)

                var firstSampleTimeUs: Long? = null
                var previousNormalizedTimeUs: Long? = null
                var estimatedSampleDurationUs = DEFAULT_SAMPLE_DURATION_US
                var wroteSample = false
                var samplesRead = 0

                while (true) {
                    buffer.clear()
                    val sampleSize = extractor.readSampleData(buffer, 0)
                    if (sampleSize < 0) break
                    val sampleTimeUs = extractor.sampleTime
                    // 注意：AAC 编码器延迟会让音频首帧 PTS 为负（如 -21333µs = 1024 采样 @48kHz），
                    // 不能把负 PTS 当作结束，否则整条音频轨 0 样本输出（合并后无声音）。
                    // 通过 firstSampleTimeUs 归一化，首帧输出到 0。

                    val firstTime = firstSampleTimeUs ?: sampleTimeUs.also { firstSampleTimeUs = it }
                    var outputTimeUs = timeOffsetUs + (sampleTimeUs - firstTime)
                    if (outputTimeUs <= lastOutputTimeUs) {
                        outputTimeUs = lastOutputTimeUs + 1L
                    }

                    bufferInfo.set(0, sampleSize, outputTimeUs, extractor.sampleFlags)
                    muxer.writeSampleData(outputTrackIndex, buffer, bufferInfo)

                    previousNormalizedTimeUs?.let { previous ->
                        val delta = outputTimeUs - previous - timeOffsetUs
                        if (delta > 0L) estimatedSampleDurationUs = delta
                    }
                    previousNormalizedTimeUs = outputTimeUs - timeOffsetUs
                    lastOutputTimeUs = outputTimeUs
                    wroteSample = true
                    samplesRead++
                    extractor.advance()
                }

                Log.d(TAG, "pass=${inputTrackType} file=${file.name} wrote=$samplesRead samples")
                if (wroteSample) {
                    timeOffsetUs = lastOutputTimeUs + estimatedSampleDurationUs
                }
            } catch (throwable: Throwable) {
                throw IllegalStateException(ERROR_WRITE_FAILED, throwable)
            } finally {
                extractor.release()
            }
        }
    }

    private fun findTrackIndex(extractor: MediaExtractor, trackType: TrackType): Int? {
        val prefix = when (trackType) {
            TrackType.VIDEO -> "video/"
            TrackType.AUDIO -> "audio/"
        }
        for (index in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME).orEmpty()
            if (mime.startsWith(prefix)) return index
        }
        return null
    }

    private fun getOptionalInteger(format: MediaFormat, key: String, defaultValue: Int): Int {
        return if (format.containsKey(key)) runCatching { format.getInteger(key) }.getOrDefault(defaultValue) else defaultValue
    }

    private data class TrackInfo(
        val index: Int,
        val format: MediaFormat
    )

    private data class SourceTrackInfo(
        val video: TrackInfo,
        val audio: TrackInfo?,
        val rotationDegrees: Int
    )

    private enum class TrackType {
        VIDEO,
        AUDIO
    }

    companion object {
        private const val TAG = "LocalMp4Composer"
        private const val DEFAULT_BUFFER_SIZE = 1024 * 1024
        private const val DEFAULT_SAMPLE_DURATION_US = 33_333L
        private const val ERROR_MISSING_VIDEO_TRACK = "分镜视频缺少视频轨，无法合成 MP4"
        private const val ERROR_INCOMPATIBLE_FORMAT = "分镜视频参数不一致，无法在本机无转码合成 MP4"
        private const val ERROR_WRITE_FAILED = "成片 MP4 写入失败，请重试"
    }
}

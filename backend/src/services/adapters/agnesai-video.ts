import type {
  VideoProviderAdapter,
  ProviderRequest,
  AIConfig,
  VideoGenerationRecord,
  VideoGenResponse,
  VideoPollResponse,
} from './types'
import { joinProviderUrl } from './url'

/**
 * Agnes AI 视频生成 Adapter
 * 端点: POST /v1/videos
 * 轮询: GET /v1/videos/{taskId}
 * 响应: { status, remixed_from_video_id }
 *
 * 时长通过 num_frames + frame_rate 控制（num_frames ≤ 441 且满足 8n+1）
 * 首尾帧使用 mode=keyframes + extra_body.image 数组
 */
export class AgnesAIVideoAdapter implements VideoProviderAdapter {
  provider = 'agnesai'

  buildGenerateRequest(config: AIConfig, record: VideoGenerationRecord): ProviderRequest {
    const frameRate = 24
    const body: any = {
      model: record.model || 'agnes-video-v2.0',
      prompt: record.prompt,
      num_frames: this.durationToNumFrames(record.duration, frameRate),
      frame_rate: frameRate,
    }

    // 尺寸：默认 1152x768
    const [width, height] = this.parseSize(record.size)
    if (width) body.width = width
    if (height) body.height = height

    // 参考图
    if (record.referenceMode === 'first_last') {
      // 首尾帧使用 keyframes 模式
      const frames = [record.firstFrameUrl, record.lastFrameUrl].filter(Boolean) as string[]
      if (frames.length > 0) {
        body.mode = 'keyframes'
        body.extra_body = { mode: 'keyframes', image: frames }
      }
    } else if (record.referenceMode === 'single' && record.imageUrl) {
      body.image = record.imageUrl
      body.mode = 'ti2vid'
    } else if (record.referenceMode === 'multiple' && record.referenceImageUrls) {
      try {
        const refs = JSON.parse(record.referenceImageUrls) as string[]
        if (refs.length > 0) body.extra_body = { image: refs }
      } catch {}
    }

    return {
      url: joinProviderUrl(config.baseUrl, '/v1', '/videos'),
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.apiKey}`,
      },
      body,
    }
  }

  parseGenerateResponse(result: any): VideoGenResponse {
    if (result.status === 'completed' && result.video_id) {
      return { isAsync: false, videoUrl: result.remixed_from_video_id || result.video_id }
    }
    if (result.id || result.task_id) {
      return { isAsync: true, taskId: String(result.task_id || result.id) }
    }
    throw new Error('No task_id/id in response')
  }

  buildPollRequest(config: AIConfig, taskId: string): ProviderRequest {
    return {
      url: joinProviderUrl(config.baseUrl, '/v1', `/videos/${taskId}`),
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${config.apiKey}`,
      },
      body: undefined,
    }
  }

  parsePollResponse(result: any): VideoPollResponse {
    if (result.status === 'completed') {
      // remixed_from_video_id 是视频的下载 URL
      const videoUrl = result.remixed_from_video_id || result.video_url || result.url || undefined
      return { status: 'completed', videoUrl }
    }
    if (result.status === 'failed') {
      return { status: 'failed', error: result.error?.message || result.error || 'Generation failed' }
    }
    return { status: result.status || 'processing' }
  }

  extractVideoUrl(result: any): string | null {
    return result.remixed_from_video_id || result.video_url || result.url || null
  }

  /**
   * 将时长（秒）换算为 num_frames，满足 Agnes 约束：≤ 441 且为 8n+1
   */
  private durationToNumFrames(duration: number | null | undefined, frameRate: number): number {
    const seconds = Number(duration) > 0 ? Number(duration) : 10
    const rawFrames = Math.round(seconds * frameRate)
    // 向上取到最近的 8n+1
    const n = Math.round((rawFrames - 1) / 8)
    const frames = 8 * Math.max(1, n) + 1
    return Math.min(441, frames)
  }

  /**
   * 解析 "宽x高" 尺寸字符串，返回 [width, height]；无法解析时返回默认值
   */
  private parseSize(size: string | null | undefined): [number, number] {
    const match = String(size || '').match(/^(\d+)\s*[x×]\s*(\d+)$/)
    if (match) return [Number(match[1]), Number(match[2])]
    return [1152, 768]
  }
}

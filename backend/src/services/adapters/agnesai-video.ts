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
 */
export class AgnesAIVideoAdapter implements VideoProviderAdapter {
  provider = 'agnesai'

  buildGenerateRequest(config: AIConfig, record: VideoGenerationRecord): ProviderRequest {
    const body: any = {
      model: record.model || 'agnes-video-v2.0',
      prompt: record.prompt,
      size: record.size || '1280x768',
      seconds: String(record.duration || 10),
      n: 1,
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
      return {
        status: 'completed',
        videoUrl: result.remixed_from_video_id || undefined,
      }
    }
    if (result.status === 'failed') {
      return { status: 'failed', error: result.error?.message || result.error || 'Generation failed' }
    }
    return { status: result.status || 'processing' }
  }

  extractVideoUrl(result: any): string | null {
    return result.remixed_from_video_id || result.video_id || null
  }
}

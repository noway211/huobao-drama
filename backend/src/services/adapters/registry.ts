/**
 * Provider Adapter 注册表
 */
import { MiniMaxImageAdapter } from './minimax-image'
import { MiniMaxVideoAdapter } from './minimax-video'
import { MiniMaxTTSAdapter } from './minimax-tts'
import { OpenAIImageAdapter } from './openai-image'
import { GeminiImageAdapter } from './gemini-image'
import { VolcEngineImageAdapter } from './volcengine-image'
import { VolcEngineVideoAdapter } from './volcengine-video'
import { ViduVideoAdapter } from './vidu-video'
import { AliImageAdapter } from './ali-image'
import { AliVideoAdapter } from './ali-video'
import { AgnesAIVideoAdapter } from './agnesai-video'
import type { ImageProviderAdapter, VideoProviderAdapter, TTSProviderAdapter } from './types'
import { joinProviderUrl } from './url'

// Inline OpenAI Video Adapter (kept for backward compatibility)
class OpenAIVideoAdapter implements VideoProviderAdapter {
  provider = 'openai'

  buildGenerateRequest(config: any, record: any): any {
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

  parseGenerateResponse(result: any): any {
    if (result.status === 'completed' && result.video_id) {
      return { isAsync: false, videoUrl: result.video_id }
    }
    if (result.id || result.task_id) {
      return { isAsync: true, taskId: String(result.task_id || result.id) }
    }
    throw new Error('No task_id/id in response')
  }

  buildPollRequest(config: any, taskId: string): any {
    return {
      url: joinProviderUrl(config.baseUrl, '/v1', `/videos/${taskId}`),
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${config.apiKey}`,
      },
      body: undefined,
    }
  }

  parsePollResponse(result: any): any {
    if (result.status === 'completed') {
      return {
        status: 'completed',
        videoUrl: result.remixed_from_video_id || result.video_url || undefined,
      }
    }
    if (result.status === 'failed') {
      return { status: 'failed', error: result.error?.message || result.error || 'Generation failed' }
    }
    return { status: result.status || 'processing' }
  }

  extractVideoUrl(result: any): string | null {
    return result.video_id || null
  }
}

export const imageAdapters: Record<string, ImageProviderAdapter> = {
  minimax: new MiniMaxImageAdapter(),
  openai: new OpenAIImageAdapter(),
  agnesai: new OpenAIImageAdapter(),
  gemini: new GeminiImageAdapter(),
  volcengine: new VolcEngineImageAdapter(),
  ali: new AliImageAdapter(),
  chatfire: new OpenAIImageAdapter(),
}

export const videoAdapters: Record<string, VideoProviderAdapter> = {
  minimax: new MiniMaxVideoAdapter(),
  volcengine: new VolcEngineVideoAdapter(),
  vidu: new ViduVideoAdapter(),
  ali: new AliVideoAdapter(),
  openai: new OpenAIVideoAdapter(),
  agnesai: new AgnesAIVideoAdapter(),
}

export const ttsAdapters: Record<string, TTSProviderAdapter> = {
  minimax: new MiniMaxTTSAdapter(),
}

export function getTTSAdapter(provider: string): TTSProviderAdapter {
  return ttsAdapters[provider.toLowerCase()] || ttsAdapters['minimax']
}

export function getImageAdapter(provider: string): ImageProviderAdapter {
  return imageAdapters[provider.toLowerCase()] || imageAdapters['minimax']
}

export function getVideoAdapter(provider: string): VideoProviderAdapter {
  return videoAdapters[provider.toLowerCase()] || videoAdapters['minimax']
}

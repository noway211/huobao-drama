/**
 * Agnes AI 图片生成 Adapter
 * 端点: POST /v1/images/generations
 * 模型: agnes-image-2.0-flash
 * 文档: https://agnes-ai.com/zh-Hans/docs/agnes-image-20-flash
 *
 * 图生图: extra_body.image 数组，支持 URL 或 Data URI base64
 * 响应: { data: [{ url: "..." }] }
 */
import type {
  ImageProviderAdapter,
  ProviderRequest,
  AIConfig,
  ImageGenerationRecord,
  ImageGenResponse,
  ImagePollResponse,
} from './types'
import { joinProviderUrl } from './url'

export class AgnesAIImageAdapter implements ImageProviderAdapter {
  provider = 'agnesai'

  buildGenerateRequest(config: AIConfig, record: ImageGenerationRecord): ProviderRequest {
    const size = record.size || '1024x768'

    const body: any = {
      model: record.model || 'agnes-image-2.0-flash',
      prompt: record.prompt,
      size,
      n: 1,
      extra_body: {
        response_format: 'url',
      },
    }

    // 图生图：把参考图放入 extra_body.image
    if (record.referenceImages) {
      try {
        const refs: string[] = JSON.parse(record.referenceImages)
        if (refs.length > 0) {
          body.extra_body.image = refs
        }
      } catch {}
    }

    return {
      url: joinProviderUrl(config.baseUrl, '/v1', '/images/generations'),
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.apiKey}`,
      },
      body,
    }
  }

  parseGenerateResponse(result: any): ImageGenResponse {
    if (result.task_id || result.id) {
      return { isAsync: true, taskId: result.task_id || result.id }
    }
    const imageUrl = result.data?.[0]?.url || result.url
    if (imageUrl) {
      return { isAsync: false, imageUrl }
    }
    const b64 = result.data?.[0]?.b64_json
    if (b64) {
      return { isAsync: false, imageUrl: undefined }
    }
    throw new Error('No image URL in Agnes response')
  }

  buildPollRequest(config: AIConfig, taskId: string): ProviderRequest {
    return {
      url: joinProviderUrl(config.baseUrl, '/v1', `/images/task/${taskId}`),
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${config.apiKey}`,
      },
      body: undefined,
    }
  }

  parsePollResponse(result: any): ImagePollResponse {
    if (result.status === 'completed') {
      return {
        status: 'completed',
        imageUrl: result.image_url || result.data?.[0]?.url || null,
      }
    }
    if (result.status === 'failed') {
      return { status: 'failed', error: result.error?.message || 'Generation failed' }
    }
    return { status: result.status || 'processing' }
  }

  extractImageUrl(result: any): string | null {
    return result.data?.[0]?.url || result.image_url || null
  }

  extractImageBase64(result: any): { data: string; mimeType: string } | null {
    const b64 = result.data?.[0]?.b64_json
    if (b64) {
      return { data: b64, mimeType: 'image/png' }
    }
    return null
  }
}

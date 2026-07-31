import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AgnesSettings } from '../model/AgnesSettings';
import { StoryboardShot } from '../model/DramaModels';
import { ApiLogStore, ApiLogEntry } from './ApiLogStore';
import { TextResult } from './AgnesTextRepository';

const DOMAIN = 0x0001;
const TAG = 'AgnesImageRepository';

// 图片生成请求体
interface ImageExtraBody {
  response_format: string;
}

interface ImageGenerationRequest {
  model: string;
  prompt: string;
  size: string;
  n: number;
  extra_body: ImageExtraBody;
}

// 图片生成响应 — 单个数据条目
interface ImageData {
  url?: string;
  b64_json?: string;
}

// 图片生成响应
interface ImageResponse {
  id?: string;
  task_id?: string;
  data?: ImageData[];
  url?: string;
}

// 请求头
interface ImageRequestHeader {
  'Content-Type': string;
  'Authorization': string;
}

function joinBaseUrl(baseUrl: string, path: string): string {
  const base = baseUrl.endsWith('/') ? baseUrl : baseUrl + '/';
  return base + path;
}

function ok(value: string): TextResult {
  return { ok: true, value, error: '' } as TextResult;
}

function fail(error: string): TextResult {
  return { ok: false, value: '', error } as TextResult;
}

const IMAGE_SIZE = '1024x768';

/**
 * 移植自 com.huobao.zdrama.data.repository.AgnesImageRepository。
 * 调用 POST v1/images/generations 为某个分镜生成图片并返回远程 URL。
 */
export class AgnesImageRepository {
  async generateImage(settings: AgnesSettings, shot: StoryboardShot): Promise<TextResult> {
    if (settings.apiKey.trim().length === 0) {
      return fail('Agnes API Key is required');
    }
    if (settings.imageModel.trim().length === 0) {
      return fail('Image model is required');
    }
    if (shot.imagePrompt.trim().length === 0) {
      return fail('Image prompt is required');
    }

    const url = joinBaseUrl(settings.baseUrl, 'v1/images/generations');
    const extraBody: ImageExtraBody = { response_format: 'url' };
    const reqBody: ImageGenerationRequest = {
      model: settings.imageModel,
      prompt: shot.imagePrompt,
      size: IMAGE_SIZE,
      n: 1,
      extra_body: extraBody
    };
    const requestBody = JSON.stringify(reqBody);

    const request = http.createHttp();
    const startedAt = Date.now();
    try {
      const header: ImageRequestHeader = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${settings.apiKey}`
      };
      const response = await request.request(url, {
        method: http.RequestMethod.POST,
        header: header,
        connectTimeout: settings.requestTimeoutSeconds * 1000,
        readTimeout: settings.requestTimeoutSeconds * 1000,
        extraData: requestBody
      });

      const responseText = typeof response.result === 'string'
        ? response.result
        : JSON.stringify(response.result);

      hilog.info(DOMAIN, TAG, 'API response code=%{public}d', response.responseCode);
      const logEntry: ApiLogEntry = {
        timestamp: startedAt,
        method: 'POST',
        url: url,
        statusCode: response.responseCode,
        durationMs: Date.now() - startedAt,
        requestBody: requestBody,
        responseBody: responseText,
        errorMessage: null
      };
      ApiLogStore.add(logEntry);

      if (response.responseCode < 200 || response.responseCode >= 300) {
        return fail(`HTTP ${response.responseCode}: ${responseText}`);
      }

      let parsed: ImageResponse;
      try {
        parsed = JSON.parse(responseText) as ImageResponse;
      } catch (e) {
        return fail('无法解析图片响应 JSON');
      }

      // 优先从 data[0].url 提取，回退到顶层 url 字段
      const imageUrl =
        (parsed.data && parsed.data.length > 0 && parsed.data[0].url)
          ? parsed.data[0].url
          : (parsed.url ? parsed.url : null);

      if (!imageUrl || imageUrl.trim().length === 0) {
        return fail('Agnes 未返回图片 URL');
      }
      return ok(imageUrl);
    } catch (err) {
      const bizErr = err as BusinessError;
      const message = `${bizErr.code}: ${bizErr.message}`;
      hilog.error(DOMAIN, TAG, 'image request failed: %{public}s', message);
      const logEntry: ApiLogEntry = {
        timestamp: startedAt,
        method: 'POST',
        url: url,
        statusCode: -1,
        durationMs: Date.now() - startedAt,
        requestBody: requestBody,
        responseBody: '',
        errorMessage: message
      };
      ApiLogStore.add(logEntry);
      return fail(message);
    } finally {
      request.destroy();
    }
  }
}
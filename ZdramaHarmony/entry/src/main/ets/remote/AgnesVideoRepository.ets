import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AgnesSettings } from '../model/AgnesSettings';
import { StoryboardShot } from '../model/DramaModels';
import { ApiLogStore, ApiLogEntry } from './ApiLogStore';
import { TextResult } from './AgnesTextRepository';

const DOMAIN = 0x0001;
const TAG = 'AgnesVideoRepository';

// 视频生成请求体
interface VideoGenerationRequest {
  model: string;
  prompt: string;
  num_frames: number;
  frame_rate: number;
  width: number;
  height: number;
  image?: string;
  mode?: string;
}

// 视频生成响应（初始）
interface VideoGenerationResponse {
  id?: string;
  task_id?: string;
  status?: string;
  video_url?: string;
  url?: string;
  metadata?: VideoMetadata;
  error?: string;
}

// 轮询响应
interface VideoPollResponse {
  status?: string;
  video_url?: string;
  url?: string;
  metadata?: VideoMetadata;
  error?: string;
}

interface VideoMetadata {
  url?: string;
}

interface RequestHeader {
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

const FRAME_RATE = 24;
const MAX_NUM_FRAMES = 441;
const DEFAULT_WIDTH = 768;
const DEFAULT_HEIGHT = 1152;
const POLL_INTERVAL_MS = 10_000; // 10 秒
const MAX_POLL_COUNT = 60;      // 最多轮询 60 次（10 分钟）

/**
 * 移植自 com.huobao.zdrama.data.repository.AgnesVideoRepository。
 * 调用 POST v1/videos 生成视频并轮询 GET v1/videos/{taskId} 获取结果。
 */
export class AgnesVideoRepository {
  async generateVideo(settings: AgnesSettings, shot: StoryboardShot): Promise<TextResult> {
    if (settings.apiKey.trim().length === 0) {
      return fail('Agnes API Key is required');
    }
    if (settings.videoModel.trim().length === 0) {
      return fail('Video model is required');
    }
    if (!shot.imageUrl || shot.imageUrl.trim().length === 0) {
      return fail('请先生成图片再生成视频');
    }

    const prompt = this.buildPrompt(shot);
    const numFrames = this.durationToNumFrames(shot.durationSeconds);
    const requestBodyObj: VideoGenerationRequest = {
      model: settings.videoModel,
      prompt: prompt,
      num_frames: numFrames,
      frame_rate: FRAME_RATE,
      width: DEFAULT_WIDTH,
      height: DEFAULT_HEIGHT,
      image: shot.imageUrl,
      mode: 'ti2vid'
    };
    const requestBody = JSON.stringify(requestBodyObj);

    const url = joinBaseUrl(settings.baseUrl, 'v1/videos');
    const startedAt = Date.now();

    // ── 第 1 步：POST v1/videos ──
    const request = http.createHttp();
    try {
      const header: RequestHeader = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${settings.apiKey}`
      };
      const httpResponse = await request.request(url, {
        method: http.RequestMethod.POST,
        header: header,
        connectTimeout: settings.requestTimeoutSeconds * 1000,
        readTimeout: settings.requestTimeoutSeconds * 1000,
        extraData: requestBody
      });

      const responseText = typeof httpResponse.result === 'string'
        ? httpResponse.result
        : JSON.stringify(httpResponse.result);

      hilog.info(DOMAIN, TAG, 'POST response code=%{public}d', httpResponse.responseCode);
      const logEntry: ApiLogEntry = {
        timestamp: startedAt,
        method: 'POST',
        url: url,
        statusCode: httpResponse.responseCode,
        durationMs: Date.now() - startedAt,
        requestBody: requestBody,
        responseBody: responseText,
        errorMessage: null
      };
      ApiLogStore.add(logEntry);

      if (httpResponse.responseCode < 200 || httpResponse.responseCode >= 300) {
        return fail(`HTTP ${httpResponse.responseCode}: ${responseText}`);
      }

      let parsed: VideoGenerationResponse;
      try {
        parsed = JSON.parse(responseText) as VideoGenerationResponse;
      } catch (e) {
        return fail('无法解析视频响应 JSON');
      }

      // 如果立即返回 completed 且有 URL 则直接返回
      const immediateUrl = parsed.metadata?.url || parsed.video_url || parsed.url || '';
      if (parsed.status === 'completed' && immediateUrl.length > 0) {
        return ok(immediateUrl);
      }

      const taskId = parsed.task_id || parsed.id || '';
      if (taskId.length === 0) {
        return fail('Agnes 未返回 task_id');
      }

      // ── 第 2 步：轮询 GET v1/videos/{taskId} ──
      return this.pollVideo(settings, taskId, startedAt);
    } catch (err) {
      const bizErr = err as BusinessError;
      const message = `${bizErr.code}: ${bizErr.message}`;
      hilog.error(DOMAIN, TAG, 'video request failed: %{public}s', message);
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

  /** 轮询视频生成结果 */
  private async pollVideo(settings: AgnesSettings, taskId: string, startedAt: number): Promise<TextResult> {
    const pollUrl = joinBaseUrl(settings.baseUrl, `v1/videos/${taskId}`);

    const createPollLog = (statusCode: number, durationMs: number, responseBody: string, errorMessage: string | null): ApiLogEntry => ({
      timestamp: startedAt,
      method: 'GET',
      url: pollUrl,
      statusCode: statusCode,
      durationMs: durationMs,
      requestBody: `poll task=${taskId}`,
      responseBody: responseBody,
      errorMessage: errorMessage
    });

    for (let i = 0; i < MAX_POLL_COUNT; i++) {
      // 等待
      await sleep(POLL_INTERVAL_MS);

      const pollRequest = http.createHttp();
      try {
        const pollStarted = Date.now();
        const header: RequestHeader = {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${settings.apiKey}`
        };
        const pollResponse = await pollRequest.request(pollUrl, {
          method: http.RequestMethod.GET,
          header: header,
          connectTimeout: settings.requestTimeoutSeconds * 1000,
          readTimeout: settings.requestTimeoutSeconds * 1000
        });

        const responseText = typeof pollResponse.result === 'string'
          ? pollResponse.result
          : JSON.stringify(pollResponse.result);

        hilog.info(DOMAIN, TAG, 'poll[%{public}d] code=%{public}d', i, pollResponse.responseCode);

        if (pollResponse.responseCode < 200 || pollResponse.responseCode >= 300) {
          ApiLogStore.add(
            createPollLog(pollResponse.responseCode, Date.now() - startedAt, responseText, `HTTP ${pollResponse.responseCode}`));
          return fail(`轮询失败：HTTP ${pollResponse.responseCode}`);
        }

        let parsed: VideoPollResponse;
        try {
          parsed = JSON.parse(responseText) as VideoPollResponse;
        } catch (e) {
          ApiLogStore.add(createPollLog(-1, Date.now() - startedAt, responseText, 'JSON 解析失败'));
          return fail('无法解析轮询响应 JSON');
        }

        const status = parsed.status || '';
        if (status === 'completed') {
          const videoUrl = parsed.metadata?.url || parsed.video_url || parsed.url || '';
          if (videoUrl.length === 0) {
            return fail('视频生成完成但无 URL');
          }
          ApiLogStore.add(createPollLog(pollResponse.responseCode, Date.now() - pollStarted, responseText, null));
          return ok(videoUrl);
        } else if (status === 'failed') {
          const errorText = typeof parsed.error === 'string' ? parsed.error : JSON.stringify(parsed.error || '视频生成失败');
          ApiLogStore.add(createPollLog(pollResponse.responseCode, Date.now() - startedAt, responseText, errorText));
          return fail(`视频生成失败：${errorText}`);
        }
        // pending / processing 继续轮询
        ApiLogStore.add(createPollLog(pollResponse.responseCode, Date.now() - pollStarted, responseText, null));
      } catch (err) {
        const bizErr = err as BusinessError;
        hilog.warn(DOMAIN, TAG, 'poll attempt %{public}d failed: %{public}s', i, `${bizErr.code}: ${bizErr.message}`);
      } finally {
        pollRequest.destroy();
      }
    }

    return fail(`视频生成超时（已等待 ${(MAX_POLL_COUNT * POLL_INTERVAL_MS) / 1000} 秒）`);
  }

  /** 构建视频提示词：视频提示词 + 动作 + 镜头，拼接为完整描述 */
  private buildPrompt(shot: StoryboardShot): string {
    const parts: string[] = [];
    if (shot.videoPrompt && shot.videoPrompt.trim().length > 0) {
      parts.push(shot.videoPrompt.trim());
    }
    if (shot.action && shot.action.trim().length > 0) {
      parts.push(shot.action.trim());
    }
    if (shot.camera && shot.camera.trim().length > 0) {
      parts.push(shot.camera.trim());
    }
    if (parts.length === 0) {
      return '请生成视频';
    }
    return parts.join('。') + '。请使用中文对白与中文旁白。';
  }

  /** 将分镜时长转换为帧数（与 Android 对齐） */
  private durationToNumFrames(durationSeconds: number): number {
    const requested = Math.max(durationSeconds, 1) * FRAME_RATE;
    const capped = Math.min(requested, MAX_NUM_FRAMES);
    const n = Math.max(Math.floor((capped - 1) / 8), 1);
    return n * 8 + 1;
  }
}

/** 简易 sleep 工具 */
function sleep(ms: number): Promise<void> {
  return new Promise<void>(resolve => setTimeout(resolve, ms));
}
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AgnesSettings } from '../model/AgnesSettings';
import { DramaProject, StoryboardShot, AssetStatus } from '../model/DramaModels';
import { ChatResponseTextExtractor, ChatResponse } from './ChatResponseTextExtractor';
import { TextResult } from './AgnesTextRepository';
import { ApiLogStore } from './ApiLogStore';

const DOMAIN = 0x0001;
const TAG = 'AgnesStoryboardRepository';

// 单条聊天消息
interface ChatMessage {
  role: string;
  content: string;
}

// chat/completions 请求体
interface ChatCompletionRequest {
  model: string;
  messages: ChatMessage[];
  temperature: number;
  max_tokens: number;
}

// 请求头
interface ChatRequestHeader {
  'Content-Type': string;
  'Authorization': string;
}

// 结果封装 — 复用 AgnesTextRepository 的 TextResult 接口
// (TextResult is imported from AgnesTextRepository above)

function ok(value: string): TextResult {
  return { ok: true, value, error: '' };
}

function fail(error: string): TextResult {
  return { ok: false, value: '', error };
}

function joinBaseUrl(baseUrl: string, path: string): string {
  const base = baseUrl.endsWith('/') ? baseUrl : baseUrl + '/';
  return base + path;
}

// 匹配场景头（## S01 / ## S02 等）的正则
const SCENE_HEADER_REGEX = /^##\s*S\d+\b/gm;

// 从 JSON.parse 的 unknown 对象中安全提取字段
function extractString(obj: Record<string, Object | undefined>, key: string): string | undefined {
  const v = obj[key];
  return typeof v === 'string' ? v : undefined;
}

function extractNumber(obj: Record<string, Object | undefined>, key: string): number | undefined {
  const v = obj[key];
  return typeof v === 'number' ? v : undefined;
}

/**
 * 移植自 com.huobao.zdrama.data.repository.AgnesStoryboardRepository。
 * 将剧本文本提交给 LLM，解析返回的 JSON 数组生成 StoryboardShot 列表。
 */
export class AgnesStoryboardRepository {
  // 调用 LLM 生成分镜 JSON 列表，成功后返回 JSON 序列化的分镜列表
  async generateStoryboards(
    settings: AgnesSettings,
    project: DramaProject,
    script: string
  ): Promise<TextResult> {
    if (settings.apiKey.trim().length === 0) {
      return fail('Agnes API Key is required');
    }
    if (settings.textModel.trim().length === 0) {
      return fail('Text model is required');
    }
    if (script.trim().length === 0) {
      return fail('Generate script before storyboard');
    }

    const messages: ChatMessage[] = [
      { role: 'system', content: AgnesStoryboardRepository.SYSTEM_PROMPT },
      { role: 'user', content: this.buildUserPrompt(project, script) }
    ];
    const raw = await this.postChat(settings, messages, 0.3, 6000);
    if (!raw.ok) {
      return fail(raw.error);
    }

    let parsed: ChatResponse;
    try {
      parsed = JSON.parse(raw.value) as ChatResponse;
    } catch (e) {
      return fail('无法解析响应 JSON');
    }

    const content = ChatResponseTextExtractor.extractFinalContent(parsed);
    if (content.trim().length === 0) {
      return fail('Agnes 未返回分镜内容');
    }

    const items = this.parseStoryboardJson(content);
    if (items.length === 0) {
      return fail('Agnes 未返回分镜内容');
    }

    const shots = this.buildShots(project, items);
    // 返回序列化后的分镜 JSON，供 UseCase 存入数据库
    return ok(JSON.stringify(shots));
  }

  // 将 JSON 字符串解析为 StoryboardShot 列表（供 UseCase 从 ok.value 解析）
  parseShots(json: string): StoryboardShot[] {
    try {
      return JSON.parse(json) as StoryboardShot[];
    } catch (e) {
      return [];
    }
  }

  // 提取 JSON 数组并解析为 StoryboardRawItem 列表
  private parseStoryboardJson(content: string): StoryboardRawItem[] {
    let jsonStr = content.trim();
    if (!jsonStr.startsWith('[')) {
      const start = jsonStr.indexOf('[');
      const end = jsonStr.lastIndexOf(']');
      if (start >= 0 && end > start) {
        jsonStr = jsonStr.substring(start, end + 1);
      } else {
        return [];
      }
    }

    try {
      const result = JSON.parse(jsonStr) as Array<Record<string, Object>>;
      if (!Array.isArray(result)) {
        return [];
      }
      const parsed: StoryboardRawItem[] = [];
      for (const item of result) {
        const raw = item as Record<string, Object>;
        parsed.push({
          shot_number: extractNumber(raw, 'shot_number'),
          scene: extractString(raw, 'scene'),
          action: extractString(raw, 'action'),
          dialogue: extractString(raw, 'dialogue'),
          camera: extractString(raw, 'camera'),
          image_prompt: extractString(raw, 'image_prompt'),
          video_prompt: extractString(raw, 'video_prompt'),
          duration_seconds: extractNumber(raw, 'duration_seconds')
        });
      }
      return parsed;
    } catch (e) {
      return [];
    }
  }

  // 将 LLM 返回的条目列表转为 StoryboardShot 实体列表
  private buildShots(project: DramaProject, items: StoryboardRawItem[]): StoryboardShot[] {
    const now = Date.now();
    const result: StoryboardShot[] = [];
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      result.push({
        id: 0,
        projectId: project.id,
        episodeId: null,
        shotNumber: item.shot_number ?? i + 1,
        scene: item.scene ?? '',
        action: item.action ?? '',
        dialogue: item.dialogue ?? '',
        camera: item.camera ?? '',
        imagePrompt: item.image_prompt ?? '',
        videoPrompt: item.video_prompt ?? '',
        durationSeconds: item.duration_seconds ?? project.shotDurationSeconds,
        imageStatus: AssetStatus.PENDING,
        imageUrl: null,
        imageLocalPath: null,
        imageErrorMessage: null,
        videoStatus: AssetStatus.PENDING,
        videoTaskId: null,
        videoUrl: null,
        videoLocalPath: null,
        videoErrorMessage: null,
        createdAt: now,
        updatedAt: now
      });
    }
    return result;
  }

  // 计算场景头数量，用于决定按场景还是按 shotCount 生成
  private countScenes(script: string): number {
    const matches = script.match(SCENE_HEADER_REGEX);
    return matches ? matches.length : 0;
  }

  // 构建用户提示词
  private buildUserPrompt(project: DramaProject, script: string): string {
    const sceneCount = this.countScenes(script);
    const shotCountHint = sceneCount > 0
      ? `剧本中包含 ${sceneCount} 个场景（## S01, ## S02 ...）。请按场景顺序为每个场景生成恰好一个分镜。`
      : `目标分镜数：${project.shotCount}`;
    return `项目标题：${project.title}
画面比例：${project.aspectRatio}
${shotCountHint}
默认分镜时长：${project.shotDurationSeconds} 秒

剧本：
${script}

只返回 JSON 数组。每个条目必须包含以下字段：shot_number, scene, action, dialogue, camera, image_prompt, video_prompt, duration_seconds。`;
  }

  // 底层 HTTP POST 请求
  private async postChat(
    settings: AgnesSettings,
    messages: ChatMessage[],
    temperature: number,
    maxTokens: number
  ): Promise<TextResult> {
    const url = joinBaseUrl(settings.baseUrl, 'v1/chat/completions');
    const body: ChatCompletionRequest = {
      model: settings.textModel,
      messages: messages,
      temperature: temperature,
      max_tokens: maxTokens
    };
    const requestBody = JSON.stringify(body);

    const request = http.createHttp();
    const startedAt = Date.now();
    try {
      const header: ChatRequestHeader = {
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

      ApiLogStore.add({
        timestamp: startedAt,
        method: 'POST',
        url: url,
        statusCode: response.responseCode,
        durationMs: Date.now() - startedAt,
        requestBody: requestBody,
        responseBody: responseText,
        errorMessage: null
      });

      if (response.responseCode < 200 || response.responseCode >= 300) {
        return fail(`HTTP ${response.responseCode}: ${responseText}`);
      }
      return ok(responseText);
    } catch (err) {
      const bizErr = err as BusinessError;
      const message = `${bizErr.code}: ${bizErr.message}`;
      hilog.error(DOMAIN, TAG, 'request failed: %{public}s', message);
      ApiLogStore.add({
        timestamp: startedAt,
        method: 'POST',
        url: url,
        statusCode: -1,
        durationMs: Date.now() - startedAt,
        requestBody: requestBody,
        responseBody: '',
        errorMessage: message
      });
      return fail(message);
    } finally {
      request.destroy();
    }
  }

  private static readonly SYSTEM_PROMPT = 'You convert short-drama scripts into production storyboard JSON for mobile vertical video. Return JSON only.';
}

// LLM 返回的原始 JSON 条目结构
interface StoryboardRawItem {
  shot_number?: number;
  scene?: string;
  action?: string;
  dialogue?: string;
  camera?: string;
  image_prompt?: string;
  video_prompt?: string;
  duration_seconds?: number;
}
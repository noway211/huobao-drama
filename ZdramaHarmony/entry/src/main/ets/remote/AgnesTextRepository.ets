import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AgnesSettings } from '../model/AgnesSettings';
import { DramaProject } from '../model/DramaModels';
import { ChatResponseTextExtractor, ChatResponse } from './ChatResponseTextExtractor';
import { ApiLogStore } from './ApiLogStore';

const DOMAIN = 0x0001;
const TAG = 'AgnesTextRepository';

const SYSTEM_PROMPT = 'You are an expert short-drama writer for mobile vertical video production.';

const REWRITE_SYSTEM_PROMPT = `你是一位专业的短剧编剧。请将用户提供的原始内容改写为格式化短剧剧本。

格式规范：
- 场景头：## S编号 | 内景/外景 · 地点 | 时间段
- 动作描写：自然段落，增强画面感，不包含镜头语言
- 对白格式：角色名：（状态/表情）台词内容
- 每个场景控制在 30-60 秒内容
- 场景编号连续递增（S01, S02, S03...）

改写原则：
- 保留核心情节，不改变主线故事和角色关系
- 将叙述性文字转化为可视化的场景描写
- 用对白推动情节，减少旁白
- 心理描写转化为角色表情/动作
- 长段叙述拆分为多个短场景`;

interface ChatMessage {
  role: string;
  content: string;
}

interface ChatCompletionRequest {
  model: string;
  messages: ChatMessage[];
  temperature: number;
  max_tokens: number;
}

interface ChatRequestHeader {
  'Content-Type': string;
  'Authorization': string;
}

/**
 * Result wrapper mirroring Kotlin's Result<String>: either ok text or an error.
 */
export interface TextResult {
  ok: boolean;
  value: string;
  error: string;
}

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

/**
 * Ports com.huobao.zdrama.data.repository.AgnesTextRepository.
 * Uses @ohos.net.http instead of Retrofit; auth + api-logging done inline
 * (equivalent to AgnesAuthInterceptor + ApiLogInterceptor).
 */
export class AgnesTextRepository {
  async generateScript(settings: AgnesSettings, project: DramaProject): Promise<TextResult> {
    if (settings.apiKey.trim().length === 0) {
      return fail('Agnes API Key is required');
    }
    if (settings.textModel.trim().length === 0) {
      return fail('Text model is required');
    }
    const messages: ChatMessage[] = [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: this.buildUserPrompt(project) }
    ];
    return this.chatCompletion(settings, messages, 0.7, 4000, '未返回脚本文本');
  }

  async rewriteScript(settings: AgnesSettings, rawContent: string): Promise<TextResult> {
    if (settings.apiKey.trim().length === 0) {
      return fail('Agnes API Key is required');
    }
    if (settings.textModel.trim().length === 0) {
      return fail('Text model is required');
    }
    if (rawContent.trim().length === 0) {
      return fail('Raw content is empty');
    }
    const messages: ChatMessage[] = [
      { role: 'system', content: REWRITE_SYSTEM_PROMPT },
      { role: 'user', content: this.buildRewriteUserPrompt(rawContent) }
    ];
    return this.chatCompletion(settings, messages, 0.7, 6000, '未返回改写内容');
  }

  private buildUserPrompt(project: DramaProject): string {
    return `Title: ${project.title}
Story prompt: ${project.prompt}
Style: ${project.style}
Target audience: ${project.targetAudience}
Aspect ratio: ${project.aspectRatio}
Shot count: ${project.shotCount}
Shot duration seconds: ${project.shotDurationSeconds}

Generate a concise mobile short-drama script. Return numbered shots. For each shot include scene, character action, dialogue, camera direction, and image/video generation notes.`;
  }

  private buildRewriteUserPrompt(rawContent: string): string {
    return `请将以下内容改写为格式化短剧剧本。

【原始内容】
${rawContent}`;
  }

  /**
   * Ports AgnesConnectionRepository.testTextModel — a lightweight ping.
   * Single "ping" user message, no system prompt, temp 0, max_tokens 8.
   * Succeeds on any 2xx HTTP response (does not require non-blank content).
   */
  async testTextModel(settings: AgnesSettings): Promise<TextResult> {
    if (settings.apiKey.trim().length === 0) {
      return fail('Agnes API Key is required');
    }
    if (settings.textModel.trim().length === 0) {
      return fail('Text model is required');
    }
    const messages: ChatMessage[] = [
      { role: 'user', content: 'ping' }
    ];
    const raw = await this.postChat(settings, messages, 0.0, 8);
    if (!raw.ok) {
      return fail(raw.error);
    }
    return ok('ok');
  }

  private async chatCompletion(
    settings: AgnesSettings,
    messages: ChatMessage[],
    temperature: number,
    maxTokens: number,
    blankErrorHint: string
  ): Promise<TextResult> {
    const raw = await this.postChat(settings, messages, temperature, maxTokens);
    if (!raw.ok) {
      return fail(raw.error);
    }

    let parsed: ChatResponse;
    try {
      parsed = JSON.parse(raw.value) as ChatResponse;
    } catch (e) {
      return fail('无法解析响应 JSON');
    }

    const text = ChatResponseTextExtractor.extract(parsed);
    if (text.trim().length === 0) {
      return fail(`Agnes ${blankErrorHint}，请检查文本模型是否支持 chat/completions`);
    }
    return ok(text);
  }

  /** Low-level POST v1/chat/completions. On success `value` is the raw body. */
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
}

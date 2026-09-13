import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AgnesSettings } from '../model/AgnesSettings';
import { SCRIPT_CREATE_PROMPT, SCRIPT_REWRITE_PROMPT } from '../model/PromptDefaults';
import { DramaProject } from '../model/DramaModels';
import { ChatResponseTextExtractor, ChatResponse } from './ChatResponseTextExtractor';
import { ApiLogStore } from './ApiLogStore';

const DOMAIN = 0x0001;
const TAG = 'AgnesTextRepository';

// 系统提示词默认值已迁出到 model/PromptDefaults.ets；
// 这里只负责取 effective prompt (settings.custom* || default)。
// 调用侧 (UseCases) 在拿到 settings 后注入 effective prompt，避免 repo 耦合持久化。

// 单条聊天消息：角色（system/user/assistant）与内容文本
interface ChatMessage {
  role: string;
  content: string;
}

// chat/completions 接口的请求体结构
interface ChatCompletionRequest {
  model: string;
  messages: ChatMessage[];
  temperature: number;
  max_tokens: number;
}

// chat/completions 请求头结构（内容类型与鉴权）
interface ChatRequestHeader {
  'Content-Type': string;
  'Authorization': string;
}

/**
 * 结果封装，对应 Kotlin 的 Result<String>：要么返回成功文本，要么返回错误信息。
 */
export interface TextResult {
  ok: boolean;
  value: string;
  error: string;
}

// 构造成功结果
function ok(value: string): TextResult {
  return { ok: true, value, error: '' };
}

// 构造失败结果
function fail(error: string): TextResult {
  return { ok: false, value: '', error };
}

// 拼接基础 URL 与路径，确保二者之间只有一个斜杠
function joinBaseUrl(baseUrl: string, path: string): string {
  const base = baseUrl.endsWith('/') ? baseUrl : baseUrl + '/';
  return base + path;
}

/**
 * 移植自 com.huobao.zdrama.data.repository.AgnesTextRepository。
 * 使用 @ohos.net.http 代替 Retrofit；鉴权与 API 日志记录在方法内内联完成
 *（等价于 AgnesAuthInterceptor + ApiLogInterceptor）。
 */
export class AgnesTextRepository {
  /**
   * 按当前集原文创作短剧剧本（使用 ## S 场景格式）。
   * storyPrompt 优先用 episode.content，空则回退 project.prompt。
   */
  async generateScript(
    settings: AgnesSettings,
    project: DramaProject,
    storyPrompt: string
  ): Promise<TextResult> {
    if (settings.apiKey.trim().length === 0) {
      return fail('Agnes API Key is required');
    }
    if (settings.textModel.trim().length === 0) {
      return fail('Text model is required');
    }
    const systemPrompt = (settings.customScriptCreatePrompt ?? '').trim() || SCRIPT_CREATE_PROMPT;
    const messages: ChatMessage[] = [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: this.buildUserPrompt(project, storyPrompt) }
    ];
    return this.chatCompletion(settings, messages, 0.7, 4000, '未返回脚本文本');
  }

  // 将原始内容改写为格式化短剧剧本
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
    const systemPrompt = (settings.customScriptRewritePrompt ?? '').trim() || SCRIPT_REWRITE_PROMPT;
    const messages: ChatMessage[] = [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: this.buildRewriteUserPrompt(rawContent) }
    ];
    return this.chatCompletion(settings, messages, 0.7, 6000, '未返回改写内容');
  }

  // 根据项目信息 + 当前集故事提示词构建生成剧本的用户提示词
  private buildUserPrompt(project: DramaProject, storyPrompt: string): string {
    return `请根据以下项目信息创作一部短视频短剧剧本。

项目标题：${project.title}
故事提示词：${storyPrompt}
风格：${project.style}
目标受众：${project.targetAudience}
画幅比例：${project.aspectRatio}
镜头数量：${project.shotCount}
单镜头时长：${project.shotDurationSeconds}秒`;
  }

  // 根据原始内容构建改写剧本的用户提示词
  private buildRewriteUserPrompt(rawContent: string): string {
    return `请将以下内容改写为格式化短剧剧本。

【原始内容】
${rawContent}`;
  }

  /**
   * 移植自 AgnesConnectionRepository.testTextModel —— 一个轻量级连通性检测。
   * 仅发送单条 "ping" 用户消息，无系统提示词，temperature 为 0，max_tokens 为 8。
   * 只要 HTTP 返回任意 2xx 即视为成功（不要求返回非空内容）。
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

  // 发起聊天补全请求并解析出文本内容，内容为空时返回带提示的错误
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

  /** 底层 POST v1/chat/completions 请求。成功时 `value` 为原始响应体，并记录 API 日志。 */
  async postChat(
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

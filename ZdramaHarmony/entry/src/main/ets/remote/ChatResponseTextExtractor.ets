/**
 * 移植自 com.huobao.zdrama.data.remote.ChatResponseTextExtractor。
 *
 * ArkTS 禁止索引签名和 `any`，因此不使用通用 JSON 遍历，而是将 Agnes 可能返回的
 * OpenAI 兼容响应结构建模为具体的可选字段接口并逐层导航。`content` /
 * `reasoning_content` 可能是纯字符串，也可能是内容片段数组 —— 两者都做处理。
 */

// 内容片段：文本可能出现在 text / output_text / content 任一字段
export interface ContentItem {
  text?: string;
  output_text?: string;
  content?: string;
}

// 消息对象：内容、文本、推理内容（content/reasoning_content 可为字符串或数组）
export interface MessageObj {
  content?: string | ContentItem[];
  text?: string;
  reasoning_content?: string | ContentItem[];
}

// 增量对象：流式响应中的 delta 内容
export interface DeltaObj {
  content?: string | ContentItem[];
}

// 选择项：可能包含直接文本、完整消息或流式增量
export interface ChoiceObj {
  text?: string;
  message?: MessageObj;
  delta?: DeltaObj;
}

// 输出项：Responses 风格接口的输出条目
export interface OutputItem {
  text?: string;
  output_text?: string;
  content?: string | ContentItem[];
}

// 聊天响应根结构：兼容 output_text / choices / output 多种返回形态
export interface ChatResponse {
  output_text?: string;
  choices?: ChoiceObj[];
  output?: OutputItem[];
}

// 将内容（字符串或片段数组）归一化为纯文本，多个片段用换行拼接
function contentToText(content: string | ContentItem[] | undefined): string {
  if (content === undefined) {
    return '';
  }
  if (typeof content === 'string') {
    return content;
  }
  const parts: string[] = [];
  for (const item of content) {
    const text = item.text ?? item.output_text ?? item.content ?? '';
    if (text.trim().length > 0) {
      parts.push(text);
    }
  }
  return parts.join('\n');
}

// 返回列表中第一个非空白的字符串（已 trim），都为空则返回空串
function firstNonBlank(values: string[]): string {
  for (const value of values) {
    if (value.trim().length > 0) {
      return value.trim();
    }
  }
  return '';
}

export class ChatResponseTextExtractor {
  // 从响应的各正式内容字段（output_text/choices/output）收集候选，取第一个非空文本
  static extractFinalContent(response: ChatResponse): string {
    const candidates: string[] = [];

    if (response.output_text !== undefined) {
      candidates.push(response.output_text);
    }

    if (response.choices !== undefined) {
      for (const choice of response.choices) {
        if (choice.text !== undefined) {
          candidates.push(choice.text);
        }
        const message = choice.message;
        if (message !== undefined) {
          candidates.push(contentToText(message.content));
          if (message.text !== undefined) {
            candidates.push(message.text);
          }
        }
        const delta = choice.delta;
        if (delta !== undefined) {
          candidates.push(contentToText(delta.content));
        }
      }
    }

    if (response.output !== undefined) {
      for (const item of response.output) {
        const text = item.text ?? item.output_text ?? contentToText(item.content);
        candidates.push(text);
      }
    }

    return firstNonBlank(candidates);
  }

  // 提取响应文本：优先取正式内容，为空时回退到 reasoning_content 推理内容
  static extract(response: ChatResponse): string {
    const finalContent = ChatResponseTextExtractor.extractFinalContent(response);
    if (finalContent.trim().length > 0) {
      return finalContent;
    }
    const candidates: string[] = [];
    if (response.choices !== undefined) {
      for (const choice of response.choices) {
        const message = choice.message;
        if (message !== undefined && message.reasoning_content !== undefined) {
          candidates.push(contentToText(message.reasoning_content));
        }
      }
    }
    return firstNonBlank(candidates);
  }
}

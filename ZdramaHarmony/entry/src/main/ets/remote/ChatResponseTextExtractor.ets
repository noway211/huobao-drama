/**
 * Ports com.huobao.zdrama.data.remote.ChatResponseTextExtractor.
 *
 * ArkTS forbids index signatures / `any`, so instead of a generic JSON walker we
 * model the OpenAI-compatible response shapes Agnes can return as concrete
 * optional-field interfaces and navigate those. `content` / `reasoning_content`
 * may be a plain string or an array of content parts — both are handled.
 */

export interface ContentItem {
  text?: string;
  output_text?: string;
  content?: string;
}

export interface MessageObj {
  content?: string | ContentItem[];
  text?: string;
  reasoning_content?: string | ContentItem[];
}

export interface DeltaObj {
  content?: string | ContentItem[];
}

export interface ChoiceObj {
  text?: string;
  message?: MessageObj;
  delta?: DeltaObj;
}

export interface OutputItem {
  text?: string;
  output_text?: string;
  content?: string | ContentItem[];
}

export interface ChatResponse {
  output_text?: string;
  choices?: ChoiceObj[];
  output?: OutputItem[];
}

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

function firstNonBlank(values: string[]): string {
  for (const value of values) {
    if (value.trim().length > 0) {
      return value.trim();
    }
  }
  return '';
}

export class ChatResponseTextExtractor {
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

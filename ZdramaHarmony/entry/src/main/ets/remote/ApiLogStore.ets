/**
 * 移植自 com.huobao.zdrama.data.remote.ApiLogStore + ApiLogInterceptor 的行为。
 * 内存环形缓冲区（100 条），供 API 日志视图展示请求/响应。
 * 请求/响应体会被截断，且 base64 data-URI 内容会被脱敏，
 * 以避免密钥和超大图片数据撑爆日志。
 */

// 单条 API 日志记录：时间、方法、URL、状态码、耗时、请求体、响应体、错误信息
export interface ApiLogEntry {
  timestamp: number;
  method: string;
  url: string;
  statusCode: number;
  durationMs: number;
  requestBody: string;
  responseBody: string;
  errorMessage: string | null;
}

const MAX_ENTRIES = 100;
const MAX_BODY_BYTES = 32 * 1024;
const BASE64_DATA_URI = /data:[^;]*;base64,[A-Za-z0-9+/=]+/g;

// 脱敏并截断日志体：替换 base64 data-URI，超出最大字节数时截断
function sanitize(body: string): string {
  if (!body) {
    return '';
  }
  let result = body.replace(BASE64_DATA_URI, (m) => `<base64:${m.length} bytes>`);
  if (result.length > MAX_BODY_BYTES) {
    result = result.substring(0, MAX_BODY_BYTES) + `…<truncated ${result.length - MAX_BODY_BYTES} chars>`;
  }
  return result;
}

export class ApiLogStore {
  private static entries: ApiLogEntry[] = [];

  // 新增一条日志（脱敏后插入队首，超出上限则丢弃最旧记录）
  static add(entry: ApiLogEntry): void {
    entry.requestBody = sanitize(entry.requestBody);
    entry.responseBody = sanitize(entry.responseBody);
    ApiLogStore.entries.unshift(entry);
    if (ApiLogStore.entries.length > MAX_ENTRIES) {
      ApiLogStore.entries.length = MAX_ENTRIES;
    }
  }

  // 返回当前日志列表的副本快照
  static snapshot(): ApiLogEntry[] {
    return ApiLogStore.entries.slice();
  }

  // 清空所有日志
  static clear(): void {
    ApiLogStore.entries = [];
  }
}

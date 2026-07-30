/**
 * Ports com.huobao.zdrama.data.remote.ApiLogStore + ApiLogInterceptor behavior.
 * In-memory ring buffer (100 entries) of request/response for the API-log view.
 * Bodies are capped and base64 data-URI payloads are redacted so the key and
 * huge image blobs never bloat the log.
 */

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

  static add(entry: ApiLogEntry): void {
    entry.requestBody = sanitize(entry.requestBody);
    entry.responseBody = sanitize(entry.responseBody);
    ApiLogStore.entries.unshift(entry);
    if (ApiLogStore.entries.length > MAX_ENTRIES) {
      ApiLogStore.entries.length = MAX_ENTRIES;
    }
  }

  static snapshot(): ApiLogEntry[] {
    return ApiLogStore.entries.slice();
  }

  static clear(): void {
    ApiLogStore.entries = [];
  }
}

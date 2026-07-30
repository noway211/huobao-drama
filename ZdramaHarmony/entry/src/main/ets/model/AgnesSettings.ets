/**
 * Agnes AI 服务配置项，移植自 com.huobao.zdrama.data.settings.AgnesSettings。
 */
export interface AgnesSettings {
  apiKey: string;
  baseUrl: string;
  textModel: string;
  imageModel: string;
  videoModel: string;
  requestTimeoutSeconds: number;
}

export const DEFAULT_BASE_URL = 'https://apihub.agnes-ai.com/';
export const DEFAULT_TEXT_MODEL = 'agnes-2.0-flash';
export const DEFAULT_IMAGE_MODEL = 'agnes-image-2.0-flash';
export const DEFAULT_VIDEO_MODEL = 'agnes-video-v2.0';
export const DEFAULT_APIKEY = 'sk-E70jByuP5GZCryJ1Sa0nvw3G7yRn1v1oNqpmCp0sdnIZGOXc'
export const DEFAULT_TIMEOUT_SECONDS = 120;

// 返回一份使用默认值填充的 AgnesSettings 配置
export function defaultSettings(): AgnesSettings {
  return {
    apiKey: DEFAULT_APIKEY,
    baseUrl: DEFAULT_BASE_URL,
    textModel: DEFAULT_TEXT_MODEL,
    imageModel: DEFAULT_IMAGE_MODEL,
    videoModel: DEFAULT_VIDEO_MODEL,
    requestTimeoutSeconds: DEFAULT_TIMEOUT_SECONDS
  };
}

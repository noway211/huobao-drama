import { preferences } from '@kit.ArkData';
import { AppContext } from '../common/AppContext';
import {
  AgnesSettings,
  defaultSettings,
  DEFAULT_BASE_URL,
  DEFAULT_IMAGE_MODEL,
  DEFAULT_VIDEO_MODEL,
  DEFAULT_TIMEOUT_SECONDS
} from '../model/AgnesSettings';

/**
 * Ports com.huobao.zdrama.data.settings.AgnesSettingsStore.
 *
 * Android split the API key into EncryptedSharedPreferences and everything else
 * into plain SharedPreferences. HarmonyOS app-sandbox Preferences files are
 * already private to the app; the API key is kept in a separate store so a later
 * phase can wrap it with Huks-backed encryption without touching call sites.
 */

// 普通设置存储文件名（明文）
const PLAIN_STORE = 'agnes_plain_settings';
// 敏感设置存储文件名（用于隔离 API Key，便于后续接入加密）
const SECURE_STORE = 'agnes_secure_settings';

// 各配置项在 Preferences 中的键名
const KEY_API = 'api_key';
const KEY_BASE_URL = 'base_url';
const KEY_TEXT_MODEL = 'text_model';
const KEY_IMAGE_MODEL = 'image_model';
const KEY_VIDEO_MODEL = 'video_model';
const KEY_TIMEOUT = 'timeout_seconds';
// 4 个 LLM 流程的自定义系统提示词（与 PromptDefaults 对应；空串 = 用户主动清空 → fallback 默认）
const KEY_PROMPT_SCRIPT_CREATE = 'prompt_script_create';
const KEY_PROMPT_SCRIPT_REWRITE = 'prompt_script_rewrite';
const KEY_PROMPT_CHARACTER_EXTRACT = 'prompt_character_extract';
const KEY_PROMPT_STORYBOARD = 'prompt_storyboard';

// 规范化 baseUrl：去除首尾空格，空则用默认值，并确保以 '/' 结尾
function normalizeBaseUrl(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed.length === 0) {
    return DEFAULT_BASE_URL;
  }
  return trimmed.endsWith('/') ? trimmed : trimmed + '/';
}

export class SettingsStore {
  private static plain: preferences.Preferences | null = null;
  private static secure: preferences.Preferences | null = null;

  // 懒加载获取明文 Preferences 实例
  private static async plainStore(): Promise<preferences.Preferences> {
    if (!SettingsStore.plain) {
      SettingsStore.plain = await preferences.getPreferences(AppContext.get(), PLAIN_STORE);
    }
    return SettingsStore.plain;
  }

  // 懒加载获取敏感（API Key）Preferences 实例
  private static async secureStore(): Promise<preferences.Preferences> {
    if (!SettingsStore.secure) {
      SettingsStore.secure = await preferences.getPreferences(AppContext.get(), SECURE_STORE);
    }
    return SettingsStore.secure;
  }

  // 读取全部设置，缺省项回退默认值（空值也回退），返回完整 AgnesSettings
  static async load(): Promise<AgnesSettings> {
    const defaults = defaultSettings();
    const plain = await SettingsStore.plainStore();
    const secure = await SettingsStore.secureStore();

    const apiKey = secure.getSync(KEY_API, defaults.apiKey) as string;
    const baseUrl = plain.getSync(KEY_BASE_URL, defaults.baseUrl) as string;
    const textModel = plain.getSync(KEY_TEXT_MODEL, defaults.textModel) as string;
    const imageModel = plain.getSync(KEY_IMAGE_MODEL, defaults.imageModel) as string;
    const videoModel = plain.getSync(KEY_VIDEO_MODEL, defaults.videoModel) as string;
    const timeout = plain.getSync(KEY_TIMEOUT, defaults.requestTimeoutSeconds) as number;
    // 自定义提示词：未保存的 key 返回 undefined（与"用户编辑为空串"语义区分）
    const scriptCreatePrompt = plain.getSync(KEY_PROMPT_SCRIPT_CREATE, '') as string;
    const scriptRewritePrompt = plain.getSync(KEY_PROMPT_SCRIPT_REWRITE, '') as string;
    const characterExtractPrompt = plain.getSync(KEY_PROMPT_CHARACTER_EXTRACT, '') as string;
    const storyboardPrompt = plain.getSync(KEY_PROMPT_STORYBOARD, '') as string;

    return {
      apiKey: apiKey,
      baseUrl: baseUrl.length > 0 ? baseUrl : DEFAULT_BASE_URL,
      textModel: textModel,
      imageModel: imageModel.length > 0 ? imageModel : DEFAULT_IMAGE_MODEL,
      videoModel: videoModel.length > 0 ? videoModel : DEFAULT_VIDEO_MODEL,
      requestTimeoutSeconds: timeout > 0 ? timeout : DEFAULT_TIMEOUT_SECONDS,
      customScriptCreatePrompt: scriptCreatePrompt.length > 0 ? scriptCreatePrompt : undefined,
      customScriptRewritePrompt: scriptRewritePrompt.length > 0 ? scriptRewritePrompt : undefined,
      customCharacterExtractPrompt: characterExtractPrompt.length > 0 ? characterExtractPrompt : undefined,
      customStoryboardPrompt: storyboardPrompt.length > 0 ? storyboardPrompt : undefined
    };
  }

  // 保存全部设置（写入前做 trim / baseUrl 规范化），分别刷盘明文与敏感存储
  static async save(settings: AgnesSettings): Promise<void> {
    const plain = await SettingsStore.plainStore();
    const secure = await SettingsStore.secureStore();

    await secure.put(KEY_API, settings.apiKey.trim());
    await plain.put(KEY_BASE_URL, normalizeBaseUrl(settings.baseUrl));
    await plain.put(KEY_TEXT_MODEL, settings.textModel.trim());
    await plain.put(KEY_IMAGE_MODEL, settings.imageModel.trim());
    await plain.put(KEY_VIDEO_MODEL, settings.videoModel.trim());
    await plain.put(KEY_TIMEOUT, settings.requestTimeoutSeconds);
    // 4 个自定义提示词：trim 后写回；undefined 视为"未设置" → 删 key 避免污染
    await SettingsStore.putPromptOrDelete(plain, KEY_PROMPT_SCRIPT_CREATE, settings.customScriptCreatePrompt);
    await SettingsStore.putPromptOrDelete(plain, KEY_PROMPT_SCRIPT_REWRITE, settings.customScriptRewritePrompt);
    await SettingsStore.putPromptOrDelete(plain, KEY_PROMPT_CHARACTER_EXTRACT, settings.customCharacterExtractPrompt);
    await SettingsStore.putPromptOrDelete(plain, KEY_PROMPT_STORYBOARD, settings.customStoryboardPrompt);

    await secure.flush();
    await plain.flush();
  }

  // 写自定义提示词：undefined/空 → 删 key 保持 store 干净；非空 → trim 后写回
  private static async putPromptOrDelete(
    store: preferences.Preferences,
    key: string,
    value: string | undefined
  ): Promise<void> {
    if (value === undefined || value.trim().length === 0) {
      await store.delete(key);
    } else {
      await store.put(key, value.trim());
    }
  }

  // 判断是否已配置非空 API Key
  static async hasApiKey(): Promise<boolean> {
    const secure = await SettingsStore.secureStore();
    const apiKey = secure.getSync(KEY_API, '') as string;
    return apiKey.trim().length > 0;
  }
}

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

const PLAIN_STORE = 'agnes_plain_settings';
const SECURE_STORE = 'agnes_secure_settings';

const KEY_API = 'api_key';
const KEY_BASE_URL = 'base_url';
const KEY_TEXT_MODEL = 'text_model';
const KEY_IMAGE_MODEL = 'image_model';
const KEY_VIDEO_MODEL = 'video_model';
const KEY_TIMEOUT = 'timeout_seconds';

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

  private static async plainStore(): Promise<preferences.Preferences> {
    if (!SettingsStore.plain) {
      SettingsStore.plain = await preferences.getPreferences(AppContext.get(), PLAIN_STORE);
    }
    return SettingsStore.plain;
  }

  private static async secureStore(): Promise<preferences.Preferences> {
    if (!SettingsStore.secure) {
      SettingsStore.secure = await preferences.getPreferences(AppContext.get(), SECURE_STORE);
    }
    return SettingsStore.secure;
  }

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

    return {
      apiKey: apiKey,
      baseUrl: baseUrl.length > 0 ? baseUrl : DEFAULT_BASE_URL,
      textModel: textModel,
      imageModel: imageModel.length > 0 ? imageModel : DEFAULT_IMAGE_MODEL,
      videoModel: videoModel.length > 0 ? videoModel : DEFAULT_VIDEO_MODEL,
      requestTimeoutSeconds: timeout > 0 ? timeout : DEFAULT_TIMEOUT_SECONDS
    };
  }

  static async save(settings: AgnesSettings): Promise<void> {
    const plain = await SettingsStore.plainStore();
    const secure = await SettingsStore.secureStore();

    await secure.put(KEY_API, settings.apiKey.trim());
    await plain.put(KEY_BASE_URL, normalizeBaseUrl(settings.baseUrl));
    await plain.put(KEY_TEXT_MODEL, settings.textModel.trim());
    await plain.put(KEY_IMAGE_MODEL, settings.imageModel.trim());
    await plain.put(KEY_VIDEO_MODEL, settings.videoModel.trim());
    await plain.put(KEY_TIMEOUT, settings.requestTimeoutSeconds);

    await secure.flush();
    await plain.flush();
  }

  static async hasApiKey(): Promise<boolean> {
    const secure = await SettingsStore.secureStore();
    const apiKey = secure.getSync(KEY_API, '') as string;
    return apiKey.trim().length > 0;
  }
}

import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0001;
const TAG = 'AlbumSaver';

// 错误码：用户拒绝授权 (photoAccessHelper 抛 14000011 / 201 等都归为权限类)
const PERMISSION_DENIED_HINTS: string[] = [
  'permission',
  'denied',
  '拒绝',
  '未授权',
  'forbidden'
];

// 保存结果
export interface SaveResult {
  ok: boolean;
  error: string;
  uri: string;
}

function okResult(uri: string): SaveResult {
  return { ok: true, error: '', uri };
}
function failResult(error: string): SaveResult {
  return { ok: false, error, uri: '' };
}

// 判断错误是否属于"用户拒绝授权"
function isPermissionDenied(msg: string): boolean {
  const lower: string = msg.toLowerCase();
  for (const hint of PERMISSION_DENIED_HINTS) {
    if (lower.indexOf(hint.toLowerCase()) >= 0) {
      return true;
    }
  }
  return false;
}

// 把中文/带空格的标题清洗成安全的文件名（去特殊字符，保留中文/数字/字母）
export function sanitizeFileName(raw: string): string {
  if (!raw || raw.length === 0) {
    return 'final';
  }
  // 去掉文件系统非法字符：\/:*?"<>|
  let s: string = raw.replace(/[\\/:*?"<>|]/g, '_');
  s = s.trim();
  if (s.length === 0) {
    return 'final';
  }
  if (s.length > 80) {
    s = s.substring(0, 80);
  }
  return s;
}

// 生成唯一文件名：{sanitized}_{timestamp}.mp4
export function buildVideoFileName(title: string, projectId: number, ts: number): string {
  const base: string = sanitizeFileName(title);
  // 时间戳格式：YYYYMMDD_HHmmss
  const d: Date = new Date(ts);
  const pad = (n: number): string => n < 10 ? '0' + n.toString() : n.toString();
  const stamp: string = `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}_${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
  return `${base}_p${projectId}_${stamp}.mp4`;
}

// 把异常收敛成 "code: message" 字符串（沿用项目里 MediaDownloadRepository 的 cast 模式）
function errToMessage(err: Error): string {
  const be = err as BusinessError;
  const code: number = typeof be.code === 'number' ? be.code : -1;
  return `${code}: ${err.message ?? ''}`;
}

/**
 * 将本地 mp4 视频保存到系统视频相册（默认「相机胶卷/视频」相册）。
 *
 * 不需要 WRITE_MEDIA 权限：photoAccessHelper 在用户首次保存时自动弹系统授权框；
 * 用户拒绝则返回 ok=false，error 含 'permission'/'denied'/'拒绝' 等关键字。
 *
 * 移植自 Android 的 MediaStore.Video 保存流程。
 */
export class AlbumSaver {
  /**
   * 保存本地 mp4 到默认视频相册。
   * @param localPath 应用沙箱内绝对路径 (如 filesDir/generated/{projectId}/final_video.mp4)
   * @param _fileName 保留参数：早期 API 需要 fileName，Harmony 5.0.4 上 createVideoAssetRequest 不再需要，保留便于后续兼容
   */
  static async saveVideo(localPath: string, _fileName: string): Promise<SaveResult> {
    if (localPath.trim().length === 0) {
      return failResult('本地路径为空');
    }

    // 前置校验：文件必须存在且非空
    let size: number = 0;
    try {
      fileIo.accessSync(localPath);
      size = fileIo.statSync(localPath).size;
    } catch (_ignore) {
      return failResult('本地文件不存在或已删除');
    }
    if (size <= 0) {
      return failResult('本地文件为空');
    }

    // 调用 photoAccessHelper
    try {
      const context: common.UIAbilityContext = getContext() as common.UIAbilityContext;
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      // 源 URI 必须带 file:// 前缀
      const srcUri: string = localPath.startsWith('file://') ? localPath : `file://${localPath}`;
      const request: photoAccessHelper.MediaAssetChangeRequest =
        photoAccessHelper.MediaAssetChangeRequest.createVideoAssetRequest(context, srcUri);
      await helper.applyChanges(request);
      // applyChanges 完成后从 request.getAsset().uri 拿 MediaLibrary 返回的 uri
      const asset = request.getAsset();
      const resultUri: string = asset.uri;
      hilog.info(DOMAIN, TAG, 'saveVideo ok: local=%{public}s uri=%{public}s',
        localPath, resultUri);
      return okResult(resultUri);
    } catch (err) {
      const msg: string = errToMessage(err as Error);
      hilog.error(DOMAIN, TAG, 'saveVideo failed: %{public}s', msg);
      if (isPermissionDenied(msg)) {
        return failResult(`未授权访问相册：${msg}`);
      }
      return failResult(msg);
    }
  }
}

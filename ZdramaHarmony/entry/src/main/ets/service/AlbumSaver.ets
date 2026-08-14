import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0001;
const TAG = 'AlbumSaver';

// 错误码：用户拒绝授权（photoAccessHelper 抛 14000011 / 201 等都归为权限类）
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

// 把异常收敛成 "code: message" 字符串（沿用项目里 MediaDownloadRepository 的 cast 模式）
function errToMessage(err: Error): string {
  const be = err as BusinessError;
  const code: number = typeof be.code === 'number' ? be.code : -1;
  return `${code}: ${err.message ?? ''}`;
}

// 把中文/带空格的标题清洗成相册里能显示的名字（去特殊字符，保留中文/数字/字母）
export function sanitizeDisplayTitle(raw: string): string {
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

// 把 srcFile 内容写到 destFile（直接走 fileIo.copyFile，系统底层负责拷贝）
async function copyAsset(srcFile: fileIo.File, destFile: fileIo.File): Promise<void> {
  // fileIo.copyFile 接受 string|number 两种入参；这里传 fd（number）让系统直接复用已打开的句柄
  await fileIo.copyFile(srcFile.fd, destFile.fd);
}

/**
 * 把沙盒内 mp4 视频保存到系统视频相册。
 *
 * 流程：photoAccessHelper.createAsset → fileIo.copyFile（按 fd 复用已打开的句柄）
 *
 * **关键约束**：
 * - 必须在 {@link SaveButton} 安全控件的 onClick 回调里调用此方法
 * - 系统会在 SaveButton 触发时自动授予本次写权限
 * - **不需要**在 module.json5 声明 `ohos.permission.WRITE_IMAGEVIDEO`
 *   （该权限 `availableLevel: system_basic`，三方 App 装不上）
 *
 * @param localPath 沙盒内绝对路径（例如 `filesDir/generated/{projectId}/final_video.mp4`）
 * @param displayTitle 相册里显示的标题（系统会自动追加时间戳和 .mp4 后缀）
 * @returns SaveResult { ok, error, uri }
 */
export class AlbumSaver {
  static async saveVideo(localPath: string, displayTitle: string): Promise<SaveResult> {
    if (localPath.trim().length === 0) {
      return failResult('本地路径为空');
    }
    if (displayTitle.trim().length === 0) {
      return failResult('显示标题为空');
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

    let srcFile: fileIo.File | null = null;
    let destFile: fileIo.File | null = null;
    try {
      const context: common.UIAbilityContext = getContext() as common.UIAbilityContext;
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      // 1. 在系统媒体库创建一个空的 video 资产 → 返回其 content URI
      const uri: string = await helper.createAsset(
        photoAccessHelper.PhotoType.VIDEO,
        'mp4',
        { title: sanitizeDisplayTitle(displayTitle) }
      );
      // 2. 打开源文件和目标 URI（参照 codelab 用 READ_WRITE）
      srcFile = await fileIo.open(localPath, fileIo.OpenMode.READ_ONLY);
      destFile = await fileIo.open(uri, fileIo.OpenMode.READ_WRITE);
      // 3. 拷贝内容（系统底层 copyFile，按 fd 复用已打开的句柄，避免再开一次）
      await copyAsset(srcFile, destFile);
      hilog.info(DOMAIN, TAG, 'saveVideo ok: local=%{public}s uri=%{public}s size=%{public}d',
        localPath, uri, size);
      return okResult(uri);
    } catch (err) {
      const msg: string = errToMessage(err as Error);
      hilog.error(DOMAIN, TAG, 'saveVideo failed: %{public}s', msg);
      if (isPermissionDenied(msg)) {
        return failResult(`未授权访问相册：${msg}`);
      }
      return failResult(msg);
    } finally {
      // 4. 关闭两个 file 句柄（即使拷贝抛错也要关）
      if (destFile !== null) {
        try { await fileIo.close(destFile); } catch (_ignore) { /* ignore */ }
      }
      if (srcFile !== null) {
        try { await fileIo.close(srcFile); } catch (_ignore) { /* ignore */ }
      }
    }
  }
}

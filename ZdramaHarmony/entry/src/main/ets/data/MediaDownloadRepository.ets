import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from '../common/AppContext';
import { ApiLogStore, ApiLogEntry } from '../remote/ApiLogStore';

const DOMAIN = 0x0001;
const TAG = 'MediaDownloadRepository';

// 媒体类型枚举
export enum MediaType {
  IMAGE = 'IMAGE',
  VIDEO = 'VIDEO'
}

// 下载结果封装
interface DownloadResult {
  ok: boolean;
  value: string;
  error: string;
}

function ok(value: string): DownloadResult {
  return { ok: true, value, error: '' } as DownloadResult;
}

function fail(error: string): DownloadResult {
  return { ok: false, value: '', error } as DownloadResult;
}

/**
 * 从远程 URL 下载媒体文件并存入应用沙箱。
 * 移植自 com.huobao.zdrama.data.repository.MediaDownloadRepository。
 */
export class MediaDownloadRepository {
  /**
   * 下载远程资源到本地应用沙箱目录。
   * 格式：{filesDir}/generated/{projectId}/shot_{shotId}_image.{ext}
   */
  async downloadToGeneratedMedia(
    projectId: number,
    shotId: number,
    url: string,
    mediaType: MediaType
  ): Promise<DownloadResult> {
    if (url.trim().length === 0) {
      return fail('下载 URL 为空');
    }

    let ext = 'jpg';
    if (mediaType === MediaType.VIDEO) {
      ext = 'mp4';
    }
    const extFromUrl = this.extensionFromUrl(url);
    if (extFromUrl.length > 0) {
      ext = extFromUrl;
    }

    const label = mediaType === MediaType.IMAGE ? 'image' : 'video';
    const filesDir = AppContext.get().filesDir;
    const targetDirStr = `${filesDir}/generated/${projectId}`;
    const targetFileStr = `${targetDirStr}/shot_${shotId}_${label}.${ext}`;

    // 确保目标目录存在
    try {
      fileIo.mkdirSync(targetDirStr, true);
    } catch (_ignore) {
      // 目录可能已存在，忽略
    }

    const request = http.createHttp();
    const startedAt = Date.now();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET
      });

      const responseCode = response.responseCode;
      const logEntry: ApiLogEntry = {
        timestamp: startedAt,
        method: 'GET',
        url: url,
        statusCode: responseCode,
        durationMs: Date.now() - startedAt,
        requestBody: `download ${mediaType} -> project=${projectId} shot=${shotId}`,
        responseBody: '',
        errorMessage: null
      };
      ApiLogStore.add(logEntry);

      if (responseCode < 200 || responseCode >= 300) {
        return fail(`下载失败：HTTP ${responseCode}`);
      }

      // 写入文件
      let file: fileIo.File | null = null;
      try {
        file = fileIo.openSync(targetFileStr, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
        const buf = response.result as ArrayBuffer;
        fileIo.writeSync(file.fd, buf);
      } catch (writeErr) {
        const msg = `写入文件失败：${(writeErr as BusinessError).message}`;
        hilog.error(DOMAIN, TAG, '%{public}s', msg);
        return fail(msg);
      } finally {
        if (file) {
          fileIo.closeSync(file);
        }
      }

      return ok(targetFileStr);
    } catch (err) {
      const bizErr = err as BusinessError;
      const msg = `${bizErr.code}: ${bizErr.message}`;
      hilog.error(DOMAIN, TAG, 'download failed: %{public}s', msg);
      const logEntry: ApiLogEntry = {
        timestamp: startedAt,
        method: 'GET',
        url: url,
        statusCode: -1,
        durationMs: Date.now() - startedAt,
        requestBody: '',
        responseBody: '',
        errorMessage: msg
      };
      ApiLogStore.add(logEntry);
      return fail(msg);
    } finally {
      request.destroy();
    }
  }

  // 从 URL 路径中提取文件扩展名（不含点号），取不到返回空字符串
  private extensionFromUrl(url: string): string {
    const cleanPath = url.split('?')[0].split('#')[0];
    const lastDot = cleanPath.lastIndexOf('.');
    if (lastDot >= 0) {
      const ext = cleanPath.substring(lastDot + 1).toLowerCase();
      if (ext.length >= 2 && ext.length <= 5 && /^[a-zA-Z0-9]+$/.test(ext)) {
        return ext;
      }
    }
    return '';
  }

  // 删除项目生成的所有媒体文件目录
  async deleteGeneratedMedia(projectId: number): Promise<boolean> {
    try {
      const filesDir = AppContext.get().filesDir;
      const targetDirStr = `${filesDir}/generated/${projectId}`;
      fileIo.rmdirSync(targetDirStr);
      return true;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'deleteGeneratedMedia failed: %{public}s', (e as BusinessError).message);
      return false;
    }
  }
}
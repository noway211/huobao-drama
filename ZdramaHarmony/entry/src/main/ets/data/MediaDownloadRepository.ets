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
    mediaType: MediaType,
    timeoutMs: number
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
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs
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

      if (!(response.result instanceof ArrayBuffer)) {
        const msg = `下载响应不是二进制数据：${typeof response.result}`;
        hilog.error(DOMAIN, TAG, '%{public}s', msg);
        return fail(msg);
      }

      const bytes = new Uint8Array(response.result);
      if (!this.looksLikeMedia(bytes, mediaType)) {
        const msg = `下载文件格式异常：${mediaType}`;
        hilog.error(DOMAIN, TAG, '%{public}s', msg);
        return fail(msg);
      }

      // 写入文件
      let file: fileIo.File | null = null;
      try {
        file = fileIo.openSync(targetFileStr, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
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

      const stat = fileIo.statSync(targetFileStr);
      if (stat.size <= 0) {
        const msg = `下载文件为空：${targetFileStr}`;
        hilog.error(DOMAIN, TAG, '%{public}s', msg);
        return fail(msg);
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

  /**
   * 下载角色图片到本地目录。
   * 格式：{filesDir}/generated/{projectId}/char_{characterId}_image.{ext}
   */
  async downloadCharImage(
    projectId: number,
    characterId: number,
    url: string,
    timeoutMs: number
  ): Promise<DownloadResult> {
    if (url.trim().length === 0) {
      return fail('下载 URL 为空');
    }

    let ext = 'jpg';
    const extFromUrl = this.extensionFromUrl(url);
    if (extFromUrl.length > 0) {
      ext = extFromUrl;
    }

    const filesDir = AppContext.get().filesDir;
    const targetDirStr = `${filesDir}/generated/${projectId}`;
    const targetFileStr = `${targetDirStr}/char_${characterId}_image.${ext}`;

    try {
      fileIo.mkdirSync(targetDirStr, true);
    } catch (_ignore) {
      // 目录可能已存在，忽略
    }

    const request = http.createHttp();
    const startedAt = Date.now();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs
      });

      const responseCode = response.responseCode;
      const logEntry: ApiLogEntry = {
        timestamp: startedAt,
        method: 'GET',
        url: url,
        statusCode: responseCode,
        durationMs: Date.now() - startedAt,
        requestBody: `download char image -> project=${projectId} char=${characterId}`,
        responseBody: '',
        errorMessage: null
      };
      ApiLogStore.add(logEntry);

      if (responseCode < 200 || responseCode >= 300) {
        return fail(`下载失败：HTTP ${responseCode}`);
      }

      if (!(response.result instanceof ArrayBuffer)) {
        const msg = `下载响应不是二进制数据：${typeof response.result}`;
        hilog.error(DOMAIN, TAG, '%{public}s', msg);
        return fail(msg);
      }

      const bytes = new Uint8Array(response.result);
      if (!this.looksLikeMedia(bytes, MediaType.IMAGE)) {
        const msg = '下载文件格式异常：IMAGE';
        hilog.error(DOMAIN, TAG, '%{public}s', msg);
        return fail(msg);
      }

      let file: fileIo.File | null = null;
      try {
        file = fileIo.openSync(targetFileStr, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
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

      const stat = fileIo.statSync(targetFileStr);
      if (stat.size <= 0) {
        const msg = `下载文件为空：${targetFileStr}`;
        hilog.error(DOMAIN, TAG, '%{public}s', msg);
        return fail(msg);
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

  // 基于文件头做轻量媒体格式校验，避免把空响应或 JSON/HTML 错误页保存为媒体文件。
  private looksLikeMedia(bytes: Uint8Array, mediaType: MediaType): boolean {
    if (bytes.length === 0) {
      return false;
    }

    if (mediaType === MediaType.VIDEO) {
      if (bytes.length < 12) {
        return false;
      }
      return bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70;
    }

    if (bytes.length >= 8 &&
      bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47 &&
      bytes[4] === 0x0D && bytes[5] === 0x0A && bytes[6] === 0x1A && bytes[7] === 0x0A) {
      return true;
    }
    if (bytes.length >= 3 && bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) {
      return true;
    }
    if (bytes.length >= 12 &&
      bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
      bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) {
      return true;
    }
    if (bytes.length >= 6 &&
      bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x38) {
      return true;
    }
    return false;
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
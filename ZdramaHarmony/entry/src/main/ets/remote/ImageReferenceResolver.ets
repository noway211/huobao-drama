// ZdramaHarmony/entry/src/main/ets/remote/ImageReferenceResolver.ets
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { Base64Helper } from '@ohos.util';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0001;
const TAG = 'AgnesImageRepository';

// 压缩参数（与后端 image-generation.ts:206-209 对齐）
const MAX_WIDTH = 768;
const MAX_HEIGHT = 768;
const JPEG_QUALITY = 68;

interface ResolveOptions {
  // 预留：未来若要支持自定义压缩参数，从这里传入
}

// 包装 imagePacker.packing（callback 风格 → Promise 风格）
function imagePackerApi(pixelMap: image.PixelMap): Promise<ArrayBuffer> {
  return new Promise((resolve, reject) => {
    try {
      image.createImagePacker().packing(pixelMap, {
        format: 'image/jpeg',
        quality: JPEG_QUALITY,
      }, (err: BusinessError | null, data: ArrayBuffer) => {
        if (err) {
          reject(err);
        } else {
          resolve(data);
        }
      });
    } catch (syncErr) {
      reject(syncErr);
    }
  });
}

export async function resolveImageReference(
  value: string,
  _options?: ResolveOptions
): Promise<string | null> {
  const trimmed = (value ?? '').trim();
  if (trimmed.length === 0) {
    hilog.warn(DOMAIN, TAG, 'reference resolve failed | value=<empty> stage=trim error=empty');
    return null;
  }

  if (trimmed.startsWith('data:')) {
    // 已经是 data URI，透传
    return trimmed;
  }
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    // 远程 URL，Agnes 支持，透传
    return trimmed;
  }

  // 下一步：本地路径处理
  // 1) 文件存在性 + 非空
  let stat: fileIo.Stat;
  try {
    stat = fileIo.statSync(trimmed);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'reference resolve failed | path=%{public}s stage=statSync error=%{public}s',
      trimmed, (err as BusinessError).message);
    return null;
  }
  if (stat.size <= 0) {
    hilog.warn(DOMAIN, TAG, 'reference resolve failed | path=%{public}s stage=statSync error=empty file',
      trimmed);
    return null;
  }

  // 2) 读文件
  let buffer: ArrayBuffer;
  let file: fileIo.File | null = null;
  try {
    file = fileIo.openSync(trimmed, fileIo.OpenMode.READ_ONLY);
    buffer = fileIo.readSync(file.fd, stat.size);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'reference resolve failed | path=%{public}s stage=readSync error=%{public}s',
      trimmed, (err as BusinessError).message);
    return null;
  } finally {
    if (file) {
      try { fileIo.closeSync(file); } catch (_ignore) {}
    }
  }

  if (buffer.byteLength <= 0) {
    hilog.warn(DOMAIN, TAG, 'reference resolve failed | path=%{public}s stage=readSync error=read 0 bytes',
      trimmed);
    return null;
  }

  // 下一步：解码 + 编码
  // 3) 解码 → PixelMap（desiredSize + INSIDE + ignoreAlpha + EXIF 旋转）
  let pixelMap: image.PixelMap;
  try {
    const imageSource = image.createImageSource(buffer);
    pixelMap = await imageSource.createPixelMap({
      desiredSize: { width: MAX_WIDTH, height: MAX_HEIGHT },
      fit: 'INSIDE',
      ignoreAlpha: true,
    });
    imageSource.release();
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'reference resolve failed | path=%{public}s stage=createPixelMap error=%{public}s',
      trimmed, (err as BusinessError).message);
    return null;
  }

  // 4) JPEG 编码
  let jpegBuffer: ArrayBuffer;
  try {
    jpegBuffer = await new Promise<ArrayBuffer>((resolve, reject) => {
      imagePackerApi(pixelMap)
        .then(resolve)
        .catch(reject);
    });
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'reference resolve failed | path=%{public}s stage=imagePacker error=%{public}s',
      trimmed, (err as BusinessError).message);
    pixelMap.release();
    return null;
  }
  pixelMap.release();

  if (!jpegBuffer || jpegBuffer.byteLength <= 0) {
    hilog.warn(DOMAIN, TAG, 'reference resolve failed | path=%{public}s stage=imagePacker error=empty output',
      trimmed);
    return null;
  }

  // 5) base64 编码
  let base64: string;
  try {
    base64 = Base64Helper.encodeToStr(new Uint8Array(jpegBuffer));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'reference resolve failed | path=%{public}s stage=Base64Helper error=%{public}s',
      trimmed, (err as BusinessError).message);
    return null;
  }

  const sizeKB = Math.round((jpegBuffer.byteLength) / 1024);
  hilog.info(DOMAIN, TAG, 'reference resolved | path=%{public}s jpegSizeKB=%{public}d base64LenKB=%{public}d',
    trimmed, sizeKB, Math.round(base64.length / 1024));
  return `data:image/jpeg;base64,${base64}`;
}

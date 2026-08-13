// ZdramaHarmony/entry/src/main/ets/remote/ImageReferenceResolver.ets
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import util from '@ohos.util';
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
    buffer = new ArrayBuffer(stat.size);
    fileIo.readSync(file.fd, buffer, { offset: 0, length: stat.size });
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
  // 4) JPEG 编码
  //    sentinel 模式 + finally 安全网：try 块覆盖 createPixelMap + imagePacker 两步，
  //    happy path 末尾显式 release 两个 native handle 并置 null；finally 仅在异常路径兜底。
  //    stage 变量在每个高风险操作前更新，catch 块据此精确报告失败点。
  //    关键：finally 在 try 块**完成**（无论正常或抛错）时**立即**执行，不等 try 块之后的代码。
  //    本轮把 step 4 移入 outer try 块，让 finally 真正在 step 4 之后才执行。
  let imageSource: image.ImageSource | null = null;
  let pixelMap: image.PixelMap | null = null;
  let jpegBuffer: ArrayBuffer | null = null;
  let stage: string = 'createImageSource';
  try {
    imageSource = image.createImageSource(buffer);
    stage = 'createPixelMap';
    const options: image.DecodingOptions = {
      desiredSize: { width: MAX_WIDTH, height: MAX_HEIGHT },
    };
    const pm: image.PixelMap = await imageSource.createPixelMap(options);
    pixelMap = pm;
    stage = 'createPixelMap.release';
    imageSource.release();
    imageSource = null;
    stage = 'imagePacker.packing';
    jpegBuffer = await imagePackerApi(pm);
    stage = 'pixelMap.release';
    pm.release();
    pixelMap = null;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'reference resolve failed | path=%{public}s stage=%{public}s error=%{public}s',
      trimmed, stage, (err as BusinessError).message);
    return null;
  } finally {
    if (imageSource) {
      try { imageSource.release(); } catch (_ignore) {}
    }
    if (pixelMap) {
      try { pixelMap.release(); } catch (_ignore) {}
    }
  }

  if (!jpegBuffer || jpegBuffer.byteLength <= 0) {
    hilog.warn(DOMAIN, TAG, 'reference resolve failed | path=%{public}s stage=imagePacker error=empty output',
      trimmed);
    return null;
  }

  // 5) base64 编码
  let base64: string;
  try {
    base64 = new util.Base64Helper().encodeToStringSync(new Uint8Array(jpegBuffer));
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

/**
 * 本地分镜视频合成器：调用 NAPI native 模块 `libmp4concat.so` 把若干个分镜 mp4
 * 无损拼接成一个 final_video.mp4。Native 模块内部用鸿蒙的 OH_AVMuxer / OH_AVDemuxer
 * 走 sample 级直抽直写。
 *
 * 失败时抛 Error，由调用方（UseCases.composeFinalVideo）落库到 FAILED 状态。
 */

import mp4concat from 'libmp4concat.so';

export class LocalMp4Composer {
  /**
   * 把若干 mp4 顺序拼成一个 mp4。
   * @param inputPaths 输入文件绝对路径列表（按顺序拼接）
   * @param outputPath 输出文件绝对路径
   * @returns Promise，resolve 为 outputPath
   */
  async compose(inputPaths: string[], outputPath: string): Promise<string> {
    if (!inputPaths || inputPaths.length === 0) {
      throw new Error('LocalMp4Composer: 至少需要一个输入文件');
    }
    const ok: boolean = await mp4concat.concat(inputPaths, outputPath);
    if (!ok) {
      throw new Error('视频合成失败：本地合成器返回 false');
    }
    return outputPath;
  }
}

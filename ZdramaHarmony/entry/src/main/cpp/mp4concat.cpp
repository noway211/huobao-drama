/*
 * mp4concat — Harmony native MP4 lossless concatenator.
 *
 * 调用流程（与 Android LocalMp4Composer 一一对应）：
 *   1) 对每个输入文件：open → OH_AVSource_CreateWithFD → OH_AVDemuxer_CreateWithSource
 *   2) 找第一个 video track，记录其 mime/width/height
 *   3) 创建 OH_AVMuxer（mp4 容器），AddTrack 时用第一个 video track 的 format
 *      （用 OH_AVFormat_Copy 直接复用其元数据）
 *   4) 循环：对每个 demuxer 选 video track → OH_AVDemuxer_ReadSample 读 sample →
 *      将 pts 加上累计 timeOffsetUs → OH_AVMuxer_WriteSample
 *   5) 写完 Stop + Destroy 全部资源
 *   6) 任何一步失败：delete 输出文件，return false
 *
 * 使用的是 API 10 的 OH_AVMemory / OH_AVDemuxer_ReadSample / OH_AVMuxer_WriteSample
 * 路径（API 11+ 有 OH_AVBuffer / ReadSampleBuffer / WriteSampleBuffer，但 OH_AVBuffer
 * 需要预知 capacity，且 ReadSampleBuffer 在容量不足时只返 AV_ERR_NO_MEMORY，
 * 没办法 grow 内存；OH_AVMemory_Create(size) 只要 size 够一帧就够用，最稳）。
 */

#include "napi/native_api.h"

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <string>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <vector>

// 鸿蒙媒体 NDK
extern "C" {
#include "multimedia/player_framework/native_avformat.h"
#include "multimedia/player_framework/native_averrors.h"
#include "multimedia/player_framework/native_avmuxer.h"
#include "multimedia/player_framework/native_avdemuxer.h"
#include "multimedia/player_framework/native_avsource.h"
#include "multimedia/player_framework/native_avbuffer_info.h"
#include "multimedia/player_framework/native_avmemory.h"
}

namespace {

// 单帧最大预算：8MB。鸿蒙 API 10 的 OH_AVMemory_Create 一次分配这块足够
// 任何分镜视频单帧（NAPI 4K 高码率下也极不可能超过 8MB）。
constexpr int32_t kSampleBufferSize = 8 * 1024 * 1024;

void SafeDestroyFormat(OH_AVFormat *&fmt) {
  if (fmt != nullptr) {
    OH_AVFormat_Destroy(fmt);
    fmt = nullptr;
  }
}

void SafeDestroySource(OH_AVSource *&source) {
  if (source != nullptr) {
    OH_AVSource_Destroy(source);
    source = nullptr;
  }
}

void SafeDestroyDemuxer(OH_AVDemuxer *&demuxer) {
  if (demuxer != nullptr) {
    OH_AVDemuxer_Destroy(demuxer);
    demuxer = nullptr;
  }
}

void SafeDestroyMuxer(OH_AVMuxer *&muxer) {
  if (muxer != nullptr) {
    OH_AVMuxer_Destroy(muxer);
    muxer = nullptr;
  }
}

void SafeDestroyMemory(OH_AVMemory *&mem) {
  if (mem != nullptr) {
    OH_AVMemory_Destroy(mem);
    mem = nullptr;
  }
}

// 释放一个 source + demuxer + fd 组合
void TearDownSource(OH_AVSource *&source, OH_AVDemuxer *&demuxer, int &fd) {
  SafeDestroyDemuxer(demuxer);
  SafeDestroySource(source);
  if (fd >= 0) {
    close(fd);
    fd = -1;
  }
}

// 释放 muxer + 输出 fd。fd 引用置 -1，避免后续 cleanup 重复 close。
void TearDownMuxer(OH_AVMuxer *&muxer, int &fd) {
  SafeDestroyMuxer(muxer);
  if (fd >= 0) {
    close(fd);
    fd = -1;
  }
}

// 打开文件 + OH_AVSource + OH_AVDemuxer，并选第一个 video track
bool OpenInput(const std::string &path, int &fd, OH_AVSource *&source,
              OH_AVDemuxer *&demuxer, int32_t &videoTrack) {
  fd = open(path.c_str(), O_RDONLY);
  if (fd < 0) return false;
  struct stat st{};
  if (fstat(fd, &st) != 0) {
    close(fd);
    fd = -1;
    return false;
  }
  source = OH_AVSource_CreateWithFD(fd, 0, st.st_size);
  if (source == nullptr) {
    close(fd);
    fd = -1;
    return false;
  }
  demuxer = OH_AVDemuxer_CreateWithSource(source);
  if (demuxer == nullptr) {
    OH_AVSource_Destroy(source);
    source = nullptr;
    close(fd);
    fd = -1;
    return false;
  }
  // 通过 source format 找 track_count
  OH_AVFormat *srcFmt = OH_AVSource_GetSourceFormat(source);
  int32_t trackCount = 0;
  if (srcFmt != nullptr) {
    if (!OH_AVFormat_GetIntValue(srcFmt, "track_count", &trackCount) ||
        trackCount < 0) {
      trackCount = 0;
    }
  }
  if (trackCount == 0) trackCount = 32;  // 兜底
  // 找 video track：track_type == 1
  videoTrack = -1;
  for (int32_t i = 0; i < trackCount; i++) {
    OH_AVFormat *t = OH_AVSource_GetTrackFormat(source, i);
    if (t == nullptr) continue;
    int32_t type = 0;
    OH_AVFormat_GetIntValue(t, "track_type", &type);
    if (type == 1) {
      videoTrack = i;
      break;
    }
  }
  if (videoTrack < 0) {
    SafeDestroyDemuxer(demuxer);
    SafeDestroySource(source);
    close(fd);
    fd = -1;
    return false;
  }
  if (OH_AVDemuxer_SelectTrackByID(demuxer, videoTrack) != AV_ERR_OK) {
    SafeDestroyDemuxer(demuxer);
    SafeDestroySource(source);
    close(fd);
    fd = -1;
    return false;
  }
  return true;
}

// 从一个 demuxer 抽 video sample 写到 muxer
// pts 平移：outputPts = timeOffsetUs + (sample.pts - firstPtsUs)
bool AppendDemuxerToMuxer(OH_AVDemuxer *demuxer, OH_AVMuxer *muxer,
                          int32_t sourceTrack, int32_t muxerTrack,
                          int64_t &timeOffsetUs, int64_t &lastOutputTimeUs) {
  // 给 sample buffer 分配 kSampleBufferSize 字节。
  // demuxer 写入时如果 frame 实际更大，会失败（AV_ERR_NO_MEMORY），
  // 这时我们没办法扩容，false 返回。
  OH_AVMemory *mem = OH_AVMemory_Create(kSampleBufferSize);
  if (mem == nullptr) return false;

  int64_t firstPtsUs = 0;
  bool firstPtsSet = false;
  bool reachedEnd = false;
  int32_t emptySampleCount = 0;
  while (true) {
    OH_AVCodecBufferAttr info{};
    OH_AVErrCode r = OH_AVDemuxer_ReadSample(demuxer, sourceTrack, mem, &info);
    if (r == AV_ERR_OK) {
      if (info.size <= 0) {
        emptySampleCount++;
        if (emptySampleCount >= 8) {
          reachedEnd = true;
          break;
        }
        continue;
      }
      emptySampleCount = 0;
      if (!firstPtsSet) {
        firstPtsSet = true;
        firstPtsUs = info.pts;
      }
      int64_t outPts = timeOffsetUs + (info.pts - firstPtsUs);
      if (outPts <= lastOutputTimeUs) {
        // 单调性保险：理论上 demuxer 给出单调 PTS，但不同来源 PTS 起点不同，
        // 这里强制单调，避免 muxer 抛错
        outPts = lastOutputTimeUs + 1;
      }
      info.pts = outPts;
      if (OH_AVMuxer_WriteSample(muxer, muxerTrack, mem, info) != AV_ERR_OK) {
        SafeDestroyMemory(mem);
        return false;
      }
      lastOutputTimeUs = outPts;
    } else {
      // AV_ERR_EOF 或读错误：以"读完"处理。无法区分 EOF 和其它错误，
      // 但如果下一帧还是错误就会被外部调用者抓到（不是这里）。
      reachedEnd = true;
      break;
    }
  }
  SafeDestroyMemory(mem);
  return reachedEnd;
}

// 真正干活的拼接函数
bool ConcatMp4Files(const std::string &outputPath,
                   const std::vector<std::string> &inputPaths) {
  if (inputPaths.empty()) return false;

  // 单文件场景：直接拷贝即可，省得走 muxer
  if (inputPaths.size() == 1) {
    int srcFd = open(inputPaths[0].c_str(), O_RDONLY);
    if (srcFd < 0) return false;
    struct stat st{};
    if (fstat(srcFd, &st) != 0) {
      close(srcFd);
      return false;
    }
    int dstFd = open(outputPath.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (dstFd < 0) {
      close(srcFd);
      return false;
    }
    const size_t bufSize = 64 * 1024;
    std::vector<char> buf(bufSize);
    bool ok = true;
    while (true) {
      ssize_t n = read(srcFd, buf.data(), bufSize);
      if (n == 0) break;
      if (n < 0) {
        if (errno == EINTR) continue;
        ok = false;
        break;
      }
      ssize_t written = 0;
      while (written < n) {
        ssize_t w = write(dstFd, buf.data() + written, n - written);
        if (w < 0) {
          if (errno == EINTR) continue;
          ok = false;
          break;
        }
        written += w;
      }
      if (!ok) break;
    }
    close(srcFd);
    close(dstFd);
    if (!ok) {
      unlink(outputPath.c_str());
      return false;
    }
    return true;
  }

  // 多文件场景：建立 muxer，逐个 demuxer 写入
  int firstFd = -1;
  OH_AVSource *firstSource = nullptr;
  OH_AVDemuxer *firstDemuxer = nullptr;
  int32_t firstVideoTrack = -1;
  if (!OpenInput(inputPaths[0], firstFd, firstSource, firstDemuxer, firstVideoTrack)) {
    return false;
  }

  // 拷贝第一个 video track 的 format 给 muxer
  OH_AVFormat *trackFmt = OH_AVSource_GetTrackFormat(firstSource, firstVideoTrack);
  if (trackFmt == nullptr) {
    TearDownSource(firstSource, firstDemuxer, firstFd);
    return false;
  }
  OH_AVFormat *outTrackFmt = OH_AVFormat_Create();
  if (outTrackFmt == nullptr) {
    SafeDestroyFormat(trackFmt);
    TearDownSource(firstSource, firstDemuxer, firstFd);
    return false;
  }
  if (!OH_AVFormat_Copy(outTrackFmt, trackFmt)) {
    SafeDestroyFormat(outTrackFmt);
    SafeDestroyFormat(trackFmt);
    TearDownSource(firstSource, firstDemuxer, firstFd);
    return false;
  }
  SafeDestroyFormat(trackFmt);

  // 准备输出 fd 和 muxer
  unlink(outputPath.c_str());
  int outFd = open(outputPath.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (outFd < 0) {
    SafeDestroyFormat(outTrackFmt);
    TearDownSource(firstSource, firstDemuxer, firstFd);
    return false;
  }
  OH_AVMuxer *muxer = OH_AVMuxer_Create(outFd, AV_OUTPUT_FORMAT_MPEG_4);
  if (muxer == nullptr) {
    close(outFd);
    SafeDestroyFormat(outTrackFmt);
    TearDownSource(firstSource, firstDemuxer, firstFd);
    unlink(outputPath.c_str());
    return false;
  }
  int32_t muxerTrack = -1;
  if (OH_AVMuxer_AddTrack(muxer, &muxerTrack, outTrackFmt) != AV_ERR_OK ||
      muxerTrack < 0) {
    SafeDestroyMuxer(muxer);
    close(outFd);
    unlink(outputPath.c_str());
    SafeDestroyFormat(outTrackFmt);
    TearDownSource(firstSource, firstDemuxer, firstFd);
    return false;
  }
  SafeDestroyFormat(outTrackFmt);
  if (OH_AVMuxer_Start(muxer) != AV_ERR_OK) {
    TearDownMuxer(muxer, outFd);
    unlink(outputPath.c_str());
    TearDownSource(firstSource, firstDemuxer, firstFd);
    return false;
  }

  // 把第一个文件追加进去
  int64_t timeOffsetUs = 0;
  int64_t lastOutputTimeUs = -1;
  if (!AppendDemuxerToMuxer(firstDemuxer, muxer, firstVideoTrack, muxerTrack,
                             timeOffsetUs, lastOutputTimeUs)) {
    TearDownMuxer(muxer, outFd);
    unlink(outputPath.c_str());
    TearDownSource(firstSource, firstDemuxer, firstFd);
    return false;
  }
  // 累计偏移到下一段起点
  timeOffsetUs = lastOutputTimeUs + 1;

  // 追加剩余文件
  for (size_t i = 1; i < inputPaths.size(); i++) {
    int fd = -1;
    OH_AVSource *src = nullptr;
    OH_AVDemuxer *dem = nullptr;
    int32_t vt = -1;
    if (!OpenInput(inputPaths[i], fd, src, dem, vt)) {
      TearDownMuxer(muxer, outFd);
      unlink(outputPath.c_str());
      TearDownSource(firstSource, firstDemuxer, firstFd);
      return false;
    }
    if (!AppendDemuxerToMuxer(dem, muxer, vt, muxerTrack,
                               timeOffsetUs, lastOutputTimeUs)) {
      TearDownSource(src, dem, fd);
      TearDownMuxer(muxer, outFd);
      unlink(outputPath.c_str());
      TearDownSource(firstSource, firstDemuxer, firstFd);
      return false;
    }
    timeOffsetUs = lastOutputTimeUs + 1;
    TearDownSource(src, dem, fd);
  }

  // 收尾
  bool stopOk = (OH_AVMuxer_Stop(muxer) == AV_ERR_OK);
  TearDownMuxer(muxer, outFd);
  TearDownSource(firstSource, firstDemuxer, firstFd);
  if (!stopOk) {
    unlink(outputPath.c_str());
    return false;
  }
  return true;
}

struct Mp4ConcatAsyncWork {
  napi_env env;
  napi_deferred deferred;
  napi_async_work work;
  std::vector<std::string> inputPaths;
  std::string outputPath;
  bool ok;
};

static void RejectDeferredWithMessage(napi_env env, napi_deferred deferred,
                                      const char* message) {
  napi_value msg = nullptr;
  if (napi_create_string_utf8(env, message, NAPI_AUTO_LENGTH, &msg) != napi_ok) {
    return;
  }
  napi_value err = nullptr;
  if (napi_create_error(env, nullptr, msg, &err) != napi_ok) {
    return;
  }
  napi_reject_deferred(env, deferred, err);
}

static void Mp4ConcatExecute(napi_env env, void* data) {
  (void)env;
  auto* work = static_cast<Mp4ConcatAsyncWork*>(data);
  work->ok = ConcatMp4Files(work->outputPath, work->inputPaths);
}

static void Mp4ConcatComplete(napi_env env, napi_status status, void* data) {
  auto* work = static_cast<Mp4ConcatAsyncWork*>(data);
  if (status != napi_ok) {
    RejectDeferredWithMessage(env, work->deferred, "mp4concat async work failed");
  } else {
    napi_value result = nullptr;
    if (napi_get_boolean(env, work->ok, &result) == napi_ok) {
      napi_resolve_deferred(env, work->deferred, result);
    } else {
      RejectDeferredWithMessage(env, work->deferred, "mp4concat failed to return result");
    }
  }
  if (work->work != nullptr) {
    napi_delete_async_work(env, work->work);
  }
  delete work;
}

// NAPI 入口
napi_value Mp4ConcatConcat(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2] = {nullptr, nullptr};
  if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok) {
    return nullptr;
  }
  if (argc < 2) {
    napi_throw_error(env, nullptr, "mp4concat.concat expects 2 arguments");
    return nullptr;
  }

  // 第一个参数：string[]（输入文件绝对路径）
  napi_valuetype arrType = napi_undefined;
  if (napi_typeof(env, args[0], &arrType) != napi_ok || arrType != napi_object) {
    napi_throw_error(env, nullptr, "mp4concat.concat: first arg must be string[]");
    return nullptr;
  }
  bool isArray = false;
  if (napi_is_array(env, args[0], &isArray) != napi_ok || !isArray) {
    napi_throw_error(env, nullptr, "mp4concat.concat: first arg must be array");
    return nullptr;
  }
  uint32_t len = 0;
  if (napi_get_array_length(env, args[0], &len) != napi_ok) {
    napi_throw_error(env, nullptr, "mp4concat.concat: cannot get array length");
    return nullptr;
  }
  std::vector<std::string> inputPaths;
  inputPaths.reserve(len);
  for (uint32_t i = 0; i < len; i++) {
    napi_value el = nullptr;
    if (napi_get_element(env, args[0], i, &el) != napi_ok) {
      napi_throw_error(env, nullptr, "mp4concat.concat: cannot read element");
      return nullptr;
    }
    size_t strLen = 0;
    if (napi_get_value_string_utf8(env, el, nullptr, 0, &strLen) != napi_ok) {
      napi_throw_error(env, nullptr, "mp4concat.concat: element not a string");
      return nullptr;
    }
    std::string s;
    s.resize(strLen);
    if (napi_get_value_string_utf8(env, el, &s[0], strLen + 1, &strLen) !=
        napi_ok) {
      napi_throw_error(env, nullptr, "mp4concat.concat: cannot read string");
      return nullptr;
    }
    s.resize(strLen);
    inputPaths.push_back(s);
  }

  // 第二个参数：string（输出绝对路径）
  size_t outLen = 0;
  if (napi_get_value_string_utf8(env, args[1], nullptr, 0, &outLen) != napi_ok) {
    napi_throw_error(env, nullptr, "mp4concat.concat: second arg not a string");
    return nullptr;
  }
  std::string outPath;
  outPath.resize(outLen);
  if (napi_get_value_string_utf8(env, args[1], &outPath[0], outLen + 1, &outLen) !=
      napi_ok) {
    napi_throw_error(env, nullptr, "mp4concat.concat: cannot read output path");
    return nullptr;
  }
  outPath.resize(outLen);

  napi_value promise = nullptr;
  napi_deferred deferred = nullptr;
  if (napi_create_promise(env, &deferred, &promise) != napi_ok) {
    return nullptr;
  }

  auto* work = new Mp4ConcatAsyncWork{
      env, deferred, nullptr, inputPaths, outPath, false};

  napi_value asyncResource = nullptr;
  if (napi_get_undefined(env, &asyncResource) != napi_ok) {
    RejectDeferredWithMessage(env, deferred, "mp4concat failed to prepare async resource");
    delete work;
    return promise;
  }
  napi_value resourceName = nullptr;
  if (napi_create_string_utf8(env, "mp4concat.concat", NAPI_AUTO_LENGTH,
                              &resourceName) != napi_ok) {
    RejectDeferredWithMessage(env, deferred, "mp4concat failed to create async resource name");
    delete work;
    return promise;
  }

  if (napi_create_async_work(env, asyncResource, resourceName, Mp4ConcatExecute,
                             Mp4ConcatComplete, work, &work->work) != napi_ok) {
    RejectDeferredWithMessage(env, deferred, "mp4concat failed to create async work");
    delete work;
    return promise;
  }

  if (napi_queue_async_work(env, work->work) != napi_ok) {
    napi_delete_async_work(env, work->work);
    work->work = nullptr;
    RejectDeferredWithMessage(env, deferred, "mp4concat failed to queue async work");
    delete work;
    return promise;
  }
  return promise;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor desc = {
      "concat",
      nullptr,
      Mp4ConcatConcat,
      nullptr,
      nullptr,
      nullptr,
      napi_default,
      nullptr};
  if (napi_define_properties(env, exports, 1, &desc) != napi_ok) {
    return nullptr;
  }
  return exports;
}

}  // namespace

// 鸿蒙 NAPI 模块标准入口
NAPI_MODULE_INIT() {
  return Init(env, exports);
}

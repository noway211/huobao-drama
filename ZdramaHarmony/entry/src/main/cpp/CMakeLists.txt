# CMakeLists.txt — mp4concat native module
#
# 产出：libmp4concat.so
# 链接：鸿蒙媒体 NDK（muxer / demuxer / source / core / format / buffer / memory）

cmake_minimum_required(VERSION 3.20)

project(mp4concat CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# 鸿蒙 NDK 头文件路径
include_directories(
  ${CMAKE_CURRENT_SOURCE_DIR}
)

# 鸿蒙 NDK sysroot 头
include_directories(/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/sysroot/usr/include)

# 实际链接的 sysroot 库目录（用变量方便在 CI 环境覆盖）
set(OHOS_NDK_SYSROOT_LIB
  /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/sysroot/usr/lib/${OHOS_ARCH})

link_directories(${OHOS_NDK_SYSROOT_LIB})

add_library(mp4concat SHARED
  mp4concat.cpp
)

# 只暴露 mp4concat.concat 入口，不暴露 C++ 符号
target_link_options(mp4concat PRIVATE -Wl,--exclude-libs,ALL)

# 链接鸿蒙媒体 NDK（运行时 dlopen 这些 so 即可，无需 link 死）
# 用 --no-as-needed 强制链接，确保 NAPI 入口被导出
target_link_libraries(mp4concat
  PRIVATE
  native_media_avmuxer.so
  native_media_avdemuxer.so
  native_media_avsource.so
  native_media_core.so
  ace_napi.z.so
)

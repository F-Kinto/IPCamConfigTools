cmake_minimum_required(VERSION 3.14)

project(IPCamConfigTools VERSION 3.2.5 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# Qt 5.15.2 (通过 CMAKE_PREFIX_PATH 指定 Qt 安装目录)
# Concurrent：RTSP 模块的 init/recv 线程使用 QtConcurrent
find_package(Qt5 5.15.2 REQUIRED COMPONENTS Core Gui Quick QuickControls2 Network Multimedia Concurrent)

set(PUBLIC_SOURCES
    src/Public/GlobalEnum.h
    src/Public/screentools.h
    src/Public/screentools.cpp
    src/Public/ConfigureManager.h
    src/Public/ConfigureManager.cpp
    src/Public/BatchSettingsTask.h
    src/Public/BatchSettingsTask.cpp
    src/Public/TranslatorManager.h
    src/Public/TranslatorManager.cpp
    src/Public/AppLogger.h
    src/Public/AppLogger.cpp
    src/Public/common_global.h
    src/Public/WifiBroadcast.h
    src/Public/WifiBroadcast.cpp
    src/Public/DeviceScanner.h
    src/Public/DeviceScanner.cpp
    src/Public/DeviceManager.h
    src/Public/DeviceManager.cpp
    src/Public/DeviceApiClient.h
    src/Public/DeviceApiClient.cpp
    src/Public/DeviceUpgradeTask.h
    src/Public/DeviceUpgradeTask.cpp
)

# HTTP 请求库（同步自 VmsTools_v2/common）：
# SynRequestBlock（QEventLoop 阻塞收包，须在工作线程使用）
# AsynRequest（异步收包，主线程直接调用，结果经 signalResponseRequest 回调）
#   -> BaseRequest（QNetworkAccessManager + QTimer 超时封装）
#   -> RequestMessageData（请求数据结构）-> BaseDataStruct（基类）
set(NETWORK_SOURCES
    src/Network/BaseDataStruct.h
    src/Network/BaseDataStruct.cpp
    src/Network/RequestMessageData.h
    src/Network/RequestMessageData.cpp
    src/Network/BaseRequest.h
    src/Network/BaseRequest.cpp
    src/Network/SynRequestBlock.h
    src/Network/SynRequestBlock.cpp
    src/Network/AsynRequest.h
    src/Network/AsynRequest.cpp
)

# RTSP 直播模块（同步自 VmsTools：Live555 收流 + FFmpeg 解码 + YUV 渲染）
# decodevideo/videohardwareaccel/g711 保持 VmsTools 原文件名（内部相对 include 不变）
set(RTSP_SOURCES
    src/Rtsp/RtspLiveTask.h
    src/Rtsp/RtspLiveTask.cpp
    src/Rtsp/RtspVideoItem.h
    src/Rtsp/RtspVideoItem.cpp
    src/Rtsp/VideoInformation.h
    src/Rtsp/decodevideo.h
    src/Rtsp/decodevideo.cpp
    src/Rtsp/g711.h
    src/Rtsp/g711.c
    src/Rtsp/videohardwareaccel.h
    src/Rtsp/videohardwareaccel.cpp
)

set(PROJECT_SOURCES
    src/main.cpp
    ${PUBLIC_SOURCES}
    ${NETWORK_SOURCES}
    ${RTSP_SOURCES}
    qml/qml.qrc
    translate/translations.qrc
)

# x86 链接 FFmpeg/Live555 预编译库时，其 obj 无 SAFESEH 记录，
# 必须关闭 SAFESEH 校验才能通过（同 VmsTools 根 CMake 的处理）；
# 顺带开 LARGEADDRESSAWARE 让 32 位进程可寻址 4GB，缓解解码内存压力。
# x64 无此概念，不受影响。必须在 add_executable 之前设置。
if(WIN32 AND CMAKE_SIZEOF_VOID_P EQUAL 4)
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} /SAFESEH:NO /LARGEADDRESSAWARE")
endif()

if(WIN32)
    add_executable(${PROJECT_NAME} WIN32 ${PROJECT_SOURCES})
else()
    add_executable(${PROJECT_NAME} ${PROJECT_SOURCES})
endif()

target_include_directories(${PROJECT_NAME} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src/Public
    ${CMAKE_CURRENT_SOURCE_DIR}/src/Network
    ${CMAKE_CURRENT_SOURCE_DIR}/src/Rtsp
    # Live555（MultiRtspClient 预编译库，PIMPL 封装）
    ${CMAKE_CURRENT_SOURCE_DIR}/3rdParty/Live555/include
    # FFmpeg 5（C 接口，decodevideo/videohardwareaccel 引用）
    ${CMAKE_CURRENT_SOURCE_DIR}/3rdParty/FFmpeg/include
)

# WifiBroadcast 来自 common 库（COMMON_EXPORT），本项目直接编进可执行文件，
# 定义 BUILD_STATIC 让 COMMON_EXPORT 展开为空，避免出现 dllimport 符号
# 注意：必须在 add_executable 之后调用，否则目标还不存在会报 "not built by this project"
target_compile_definitions(${PROJECT_NAME} PRIVATE BUILD_STATIC)

# MSVC 默认按本地代码页(GBK)解码源码，会把 UTF-8 中文注释后的换行符吞掉（C4819/行号错位）
# 强制以 UTF-8 读取源码与生成字符串常量
if(MSVC)
    target_compile_options(${PROJECT_NAME} PRIVATE /utf-8)
endif()

target_link_libraries(${PROJECT_NAME} PRIVATE
    Qt5::Core
    Qt5::Gui
    Qt5::Quick
    Qt5::QuickControls2
    Qt5::Network
    Qt5::Multimedia
    Qt5::Concurrent
    # Live555（收流，RTP over TCP）
    liveMedia
    groupsock
    BasicUsageEnvironment
    UsageEnvironment
    # FFmpeg（解码 + 像素格式转换 + 音频重采样）
    avcodec
    avformat
    avutil
    swscale
    swresample
)

# Live555 + FFmpeg 预编译库（同步自 VmsTools_v2/3rdParty）：
#   Live555: lib/x64|x86/debug|release（debug 版带 pdb，链接期自动匹配 $<CONFIG>）
#   FFmpeg : lib/x64|x86（官方预编译库一套通用，不分 debug/release）
# 按构建架构与配置自动选择，方便后续切换 x64/x86、Debug/Release 编译环境
if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(RTSP_ARCH_DIR x64)
else()
    set(RTSP_ARCH_DIR x86)
endif()

target_link_directories(${PROJECT_NAME} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/3rdParty/Live555/lib/${RTSP_ARCH_DIR}/$<IF:$<CONFIG:Debug>,debug,release>
    ${CMAKE_CURRENT_SOURCE_DIR}/3rdParty/FFmpeg/lib/${RTSP_ARCH_DIR}
)

# FFmpeg 运行时 DLL 拷到输出目录，保证 exe 直接可跑
# （遍历当前架构目录下全部 dll，x86 版含其独有的 libx264-164.dll）
file(GLOB FFMPEG_RUNTIME_DLLS "${CMAKE_CURRENT_SOURCE_DIR}/3rdParty/FFmpeg/lib/${RTSP_ARCH_DIR}/*.dll")
add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${FFMPEG_RUNTIME_DLLS}
        $<TARGET_FILE_DIR:${PROJECT_NAME}>
)

# ConfigureManager 使用了 Windows 版本信息 API (GetFileVersionInfoA / VerQueryValueA)
# ScreenTools 使用 IP Helper API (GetAdaptersAddresses) 获取网关
if(WIN32)
    target_link_libraries(${PROJECT_NAME} PRIVATE version.lib iphlpapi.lib ws2_32.lib)
endif()

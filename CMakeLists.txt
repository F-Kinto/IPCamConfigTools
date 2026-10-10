cmake_minimum_required(VERSION 3.14)

project(IPCamConfigTools VERSION 3.2.5 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# Qt 5.15.2 (通过 CMAKE_PREFIX_PATH 指定 Qt 安装目录)
find_package(Qt5 5.15.2 REQUIRED COMPONENTS Core Gui Quick QuickControls2 Network Multimedia)

set(PUBLIC_SOURCES
    src/Public/GlobalEnum.h
    src/Public/screentools.h
    src/Public/screentools.cpp
    src/Public/ConfigureManager.h
    src/Public/ConfigureManager.cpp
    src/Public/TranslatorManager.h
    src/Public/TranslatorManager.cpp
    src/Public/AppLogger.h
    src/Public/AppLogger.cpp
)

set(PROJECT_SOURCES
    src/main.cpp
    ${PUBLIC_SOURCES}
    qml/qml.qrc
)

if(WIN32)
    add_executable(${PROJECT_NAME} WIN32 ${PROJECT_SOURCES})
else()
    add_executable(${PROJECT_NAME} ${PROJECT_SOURCES})
endif()

target_include_directories(${PROJECT_NAME} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src/Public
)

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
)

# ConfigureManager 使用了 Windows 版本信息 API (GetFileVersionInfoA / VerQueryValueA)
# ScreenTools 使用 IP Helper API (GetAdaptersAddresses) 获取网关
if(WIN32)
    target_link_libraries(${PROJECT_NAME} PRIVATE version.lib iphlpapi.lib ws2_32.lib)
endif()

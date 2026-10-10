#pragma once

#include <QtCore/qglobal.h>
#pragma execution_character_set("utf-8")

/*
 * 定义 COMMON_EXPORT 宏，用于控制动态链接库的符号导出与导入。
 *
 * 逻辑说明：
 * 1. 如果未定义 BUILD_STATIC（即构建动态库模式）：
 *    - 若定义了 COMMON_LIB（表示当前正在编译该库本身），则使用 Q_DECL_EXPORT 导出符号。
 *    - 否则（表示用户正在使用该库），使用 Q_DECL_IMPORT 导入符号。
 * 2. 如果定义了 BUILD_STATIC（即构建静态库模式）：
 *    - COMMON_EXPORT 定义为空，因为静态链接不需要导出/导入声明。
 */
#ifndef BUILD_STATIC
#if defined(COMMON_LIB)
#define COMMON_EXPORT Q_DECL_EXPORT
#else
#define COMMON_EXPORT Q_DECL_IMPORT
#endif
#else
#define COMMON_EXPORT
#endif
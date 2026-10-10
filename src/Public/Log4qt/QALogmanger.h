#pragma once

#include <QDebug>

// 轻量日志输出（原工程的 Log4qt 模块未纳入本仓库，这里用 Qt 自带分类日志替代）
#define QADebug() qDebug()
#define QAInfo() qInfo()
#define QAWarning() qWarning()
#define QACritical() qCritical()
#define QAFatal() qFatal()

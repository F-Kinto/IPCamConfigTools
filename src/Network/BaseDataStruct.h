/*********************************************************************
File : BaseDataStruct.h
Module : common
Authors: guangnan
date : 2023/03/06 16:00
Ver : 1.0.0
History:
guangnan 2023/03/06 1.0.0 build this module
********************************************************************/
#pragma once
#include "common_global.h"
#include <QObject>
#include <QSharedPointer>
#include <QVariant>

/**
 * @class BaseDataStruct
 * @brief 基础数据结构基类，用于定义统一的数据接口和类型标识。
 *        所有具体的业务数据结构应继承此类并实现相应的虚函数。
 */
class COMMON_EXPORT BaseDataStruct {

  public:
    /**
     * @typedef DataStructPointer
     * @brief BaseDataStruct的智能指针类型别名，用于内存管理。
     */
    using DataStructPointer = QSharedPointer<BaseDataStruct>;

    /**
     * @enum DataStructType
     * @brief 定义支持的数据结构类型枚举，用于区分不同的业务消息或数据对象。
     */
    enum class DataStructType {
        eBaseDataStructType,       /**< 基础数据类型 */
        eNotifyMessageType,        /**< 通知消息类型 */
        eRequestMessageDataType,   /**< 请求消息数据类型 */
        eVideoOperateType,         /**< 视频操作类型 */
        eVideoPageType,            /**< 视频分页类型 */
        eVideoInformationType,     /**< 视频信息类型 */
        eDeviceMessageType,        /**< 设备消息类型 */
        eDeviceTreeItemType,       /**< 设备树节点类型 */
        ePlayBackDataType,         /**< 回放数据类型 */
        eCloudDeviceMsgType,       /**< 云设备消息类型 */
        eDeviceWranMsgType,        /**< 设备告警消息类型 */
        eVipMessageType,           /**< VIP消息类型 */
        eCalendarMsgType,          /**< 日历消息类型 */
        eCardVideoInformation,     /**< 卡片视频信息类型 */
        eDownLoadInformation,      /**< 下载信息类型 */
        eDeviceMessageWrapperType, /**< 设备消息包装类型 */
        eRtspMessageType,          /**< RTSP消息类型 */
        eCmdRequestType,           /**< 命令请求类型 */
    };

    /**
     * @brief 构造函数
     * @details 初始化BaseDataStruct实例。
     */
    explicit BaseDataStruct();

    /**
     * @brief 析构函数
     * @details 清理BaseDataStruct实例资源。
     */
    ~BaseDataStruct();

    /**
     * @brief 获取当前数据结构的类型
     * @return DataStructType 返回当前实例对应的数据类型枚举值
     * @note 纯虚函数，子类必须实现此方法以标识具体类型
     */
    virtual inline BaseDataStruct::DataStructType dataStructType() const = 0;

    /**
     * @brief 重置数据状态
     * @details 将数据成员恢复至初始默认状态。
     *          默认实现为空，子类可根据需要重写此方法。
     */
    virtual void reset(){

    };
};

/**
 * @brief 注册BaseDataStruct*指针类型为Qt元类型系统
 * @details 允许该指针类型在Qt的信号槽机制、QVariant等场景中使用
 */
Q_DECLARE_METATYPE(BaseDataStruct*)

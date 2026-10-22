QT       += core gui

greaterThan(QT_MAJOR_VERSION, 4): QT += widgets

CONFIG += c++11

TRANSLATIONS += ./VmsTsFile/VmsTranslator_EN.ts\

CODECFORTR = GBK
#//CODECFORTR = UTF-8
#QMAKE_CXXFLAGS += -finput-charset=GBK

# You can make your code fail to compile if it uses deprecated APIs.
# In order to do so, uncomment the following line.
#DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000    # disables all the APIs deprecated before Qt 6.0.0

SOURCES += \
    ../src/main.cpp \
    ../src/Network/AsynRequest.cpp \
    ../src/Network/BaseDataStruct.cpp \
    ../src/Network/BaseRequest.cpp \
    ../src/Network/RequestMessageData.cpp \
    ../src/Network/SynRequestBlock.cpp \
    ../src/Public/AppLogger.cpp \
    ../src/Public/BatchSettingsTask.cpp \
    ../src/Public/ConfigureManager.cpp \
    ../src/Public/DeviceApiClient.cpp \
    ../src/Public/DeviceManager.cpp \
    ../src/Public/DeviceScanner.cpp \
    ../src/Public/screentools.cpp \
    ../src/Public/TranslatorManager.cpp \
    ../src/Public/WifiBroadcast.cpp \
    ../src/Rtsp/decodevideo.cpp \
    ../src/Rtsp/g711.c \
    ../src/Rtsp/RtspLiveTask.cpp \
    ../src/Rtsp/RtspVideoItem.cpp \
    ../src/Rtsp/videohardwareaccel.cpp

HEADERS += \
    ../src/Network/AsynRequest.h \
    ../src/Network/BaseDataStruct.h \
    ../src/Network/BaseRequest.h \
    ../src/Network/RequestMessageData.h \
    ../src/Network/SynRequestBlock.h \
    ../src/Public/AppLogger.h \
    ../src/Public/BatchSettingsTask.h \
    ../src/Public/common_global.h \
    ../src/Public/ConfigureManager.h \
    ../src/Public/DeviceApiClient.h \
    ../src/Public/DeviceManager.h \
    ../src/Public/DeviceScanner.h \
    ../src/Public/GlobalEnum.h \
    ../src/Public/Log4qt/QALogmanger.h \
    ../src/Public/screentools.h \
    ../src/Public/TranslatorManager.h \
    ../src/Public/WifiBroadcast.h \
    ../src/Rtsp/decodevideo.h \
    ../src/Rtsp/g711.h \
    ../src/Rtsp/RtspLiveTask.h \
    ../src/Rtsp/RtspVideoItem.h \
    ../src/Rtsp/videohardwareaccel.h \
    ../src/Rtsp/VideoInformation.h

# Default rules for deployment.
qnx: target.path = /tmp/$${TARGET}/bin
else: unix:!android: target.path = /opt/$${TARGET}/bin
!isEmpty(target.path): INSTALLS += target

DISTFILES += \
    ../qml/main.qml \
    ../qml/CommandPanel.qml \
    ../qml/LivePreviewPage.qml \
    ../qml/OtherSettingsDialog.qml \
    ../qml/SetIpDialog.qml \
    ../qml/SetOsdDialog.qml \
    ../qml/Controls/AppBusyMask.qml \
    ../qml/Controls/AppButton.qml \
    ../qml/Controls/AppCheckBox.qml \
    ../qml/Controls/AppCloseButton.qml \
    ../qml/Controls/AppComboBox.qml \
    ../qml/Controls/AppContentDialog.qml \
    ../qml/Controls/AppContextMenu.qml \
    ../qml/Controls/AppDialogHeader.qml \
    ../qml/Controls/AppIpInput.qml \
    ../qml/Controls/AppMenuItem.qml \
    ../qml/Controls/AppMessageBox.qml \
    ../qml/Controls/AppPanel.qml \
    ../qml/Controls/AppPasswordField.qml \
    ../qml/Controls/AppSpinner.qml \
    ../qml/Controls/AppTextField.qml \
    ../qml/Controls/AppTimePicker.qml \
    ../qml/Controls/AppTitleBar.qml \
    ../qml/Controls/AppToast.qml \
    ../qml/Controls/BatchProgressMask.qml \
    ../qml/Controls/BatchResultDialog.qml \
    ../qml/Controls/DeviceTable.qml \
    ../qml/image/appIcon.png

RESOURCES += \
    ../qml/qml.qrc

SUBDIRS += \
    ../transltor/VmsTranslate.pro

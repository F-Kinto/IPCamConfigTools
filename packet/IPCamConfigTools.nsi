; ============================================================================
; IPCamConfigTools NSIS 安装脚本
; 用法: makensis -DVERSION=3.2.5 -DSTAGING_DIR=... installer\IPCamConfigTools.nsi
; 或直接用 scripts\build-installer.ps1 驱动（自动准备 staging 并解析版本）
; ============================================================================

!ifndef VERSION
    !define VERSION "0.0.0"
!endif

!ifndef STAGING_DIR
    !define STAGING_DIR "..\build\installer-staging"
!endif

Unicode true
ManifestDPIAware true

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "x64.nsh"

; ----------------------------------------------------------------------------
; 基本信息
; ----------------------------------------------------------------------------
!define PRODUCT_NAME "IPC 批量配置工具"
!define PRODUCT_EXE "IPCamConfigTools.exe"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\IPCamConfigTools"
!define INST_KEY "Software\IPCamConfigTools"

Name "${PRODUCT_NAME} ${VERSION}"
OutFile "dist\IPCamConfigTools-Setup-x64-${VERSION}.exe"
InstallDir "$PROGRAMFILES64\IPCamConfigTools"
InstallDirRegKey HKLM "${INST_KEY}" "InstallLocation"
RequestExecutionLevel admin

SetCompressor /SOLID lzma

; ----------------------------------------------------------------------------
; MUI2 界面配置
; ----------------------------------------------------------------------------
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\${PRODUCT_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "运行 ${PRODUCT_NAME}"
!define MUI_UNFINISHPAGE_NOQUERY

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "English"

; ----------------------------------------------------------------------------
; 安装
; ----------------------------------------------------------------------------
Section "主程序（必需）" SecMain
    SectionIn RO

    ; NSIS 是 32 位进程，默认写 HKLM 会被 WOW64 重定向到 WOW6432Node；
    ; x64 程序的注册表应写入 64 位视图。
    SetRegView 64

    ; 升级清理：删除早期全量包遗留、现已排除出包的文件（全新安装时为空操作）
    Delete "$INSTDIR\avfilter-8.dll"
    Delete "$INSTDIR\avdevice-59.dll"
    Delete "$INSTDIR\postproc-56.dll"
    Delete "$INSTDIR\opengl32sw.dll"
    Delete "$INSTDIR\Qt5Svg.dll"
    Delete "$INSTDIR\imageformats\qsvg.dll"
    Delete "$INSTDIR\imageformats\qtiff.dll"
    Delete "$INSTDIR\imageformats\qwebp.dll"
    Delete "$INSTDIR\imageformats\qtga.dll"
    Delete "$INSTDIR\imageformats\qwbmp.dll"
    Delete "$INSTDIR\imageformats\qicns.dll"
    RMDir "$INSTDIR\imageformats"
    RMDir /r "$INSTDIR\translations"
    RMDir /r "$INSTDIR\virtualkeyboard"
    RMDir /r "$INSTDIR\qmltooling"
    RMDir /r "$INSTDIR\bearer"
    RMDir /r "$INSTDIR\iconengines"
    RMDir /r "$INSTDIR\QtGraphicalEffects"
    RMDir /r "$INSTDIR\QtQuick\Extras"
    RMDir /r "$INSTDIR\QtQuick\Controls.2\Imagine"
    RMDir /r "$INSTDIR\QtQuick\Controls.2\Material"
    RMDir /r "$INSTDIR\QtQuick\Controls.2\Universal"

    SetOutPath "$INSTDIR"
    File /r "${STAGING_DIR}\*.*"

    ; 写出卸载程序
    WriteUninstaller "$INSTDIR\Uninstall.exe"

    ; 开始菜单快捷方式
    CreateDirectory "$SMPROGRAMS\${PRODUCT_NAME}"
    CreateShortcut "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk" "$INSTDIR\${PRODUCT_EXE}" "" "$INSTDIR\${PRODUCT_EXE}" 0
    CreateShortcut "$SMPROGRAMS\${PRODUCT_NAME}\卸载 ${PRODUCT_NAME}.lnk" "$INSTDIR\Uninstall.exe" "" "$INSTDIR\Uninstall.exe" 0

    ; 写卸载注册表（控制面板"应用与功能"）
    WriteRegStr HKLM "${INST_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKLM "${UNINST_KEY}" "DisplayName" "${PRODUCT_NAME}"
    WriteRegStr HKLM "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
    WriteRegStr HKLM "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKLM "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\${PRODUCT_EXE}"
    WriteRegStr HKLM "${UNINST_KEY}" "Publisher" "IPC Tool"
    WriteRegStr HKLM "${UNINST_KEY}" "UninstallString" "$INSTDIR\Uninstall.exe"
    WriteRegDWORD HKLM "${UNINST_KEY}" "NoModify" 1
    WriteRegDWORD HKLM "${UNINST_KEY}" "NoRepair" 1

    ; 计算安装体积
    ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
    IntFmt $0 "0x%08X" $0
    WriteRegDWORD HKLM "${UNINST_KEY}" "EstimatedSize" "$0"
SectionEnd

Section "桌面快捷方式" SecDesktop
    CreateShortcut "$DESKTOP\${PRODUCT_NAME}.lnk" "$INSTDIR\${PRODUCT_EXE}" "" "$INSTDIR\${PRODUCT_EXE}" 0
SectionEnd

; ----------------------------------------------------------------------------
; 卸载
; ----------------------------------------------------------------------------
Section "Uninstall"
    SetRegView 64

    ; 结束运行中的程序，避免文件占用
    nsExec::ExecToLog 'taskkill /IM "${PRODUCT_EXE}" /F'

    Delete "$DESKTOP\${PRODUCT_NAME}.lnk"
    Delete "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk"
    Delete "$SMPROGRAMS\${PRODUCT_NAME}\卸载 ${PRODUCT_NAME}.lnk"
    RMDir "$SMPROGRAMS\${PRODUCT_NAME}"

    RMDir /r "$INSTDIR"
    DeleteRegKey HKLM "${UNINST_KEY}"
    DeleteRegKey HKLM "${INST_KEY}"
SectionEnd

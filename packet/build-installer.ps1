# Build NSIS installer for IPCamConfigTools (x64 Release).
# Usage: powershell -File packet\build-installer.ps1
# Steps: parse version -> ensure Qt deploy -> clean staging -> makensis -> packet\dist\
$root = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $root 'build\Release'
$staging = Join-Path $root 'build\installer-staging'
$dist = Join-Path $PSScriptRoot 'dist'

# 1) Parse version from CMakeLists.txt (single source of truth)
$cmake = Get-Content (Join-Path $root 'CMakeLists.txt') -Raw
if ($cmake -notmatch 'project\(\s*\w+\s+VERSION\s+(\d+\.\d+\.\d+)') {
    Write-Host 'ERROR: cannot parse project VERSION from CMakeLists.txt'
    exit 1
}
$version = $Matches[1]
Write-Host "Version: $version"

# 2) Ensure build/Release exists and Qt runtime is deployed correctly (x64).
#    deploy-release.ps1 self-heals: missing/bad-arch Qt -> force redeploy (with PATH sanitizing).
$exe = Join-Path $releaseDir 'IPCamConfigTools.exe'
if (-not (Test-Path $exe)) {
    Write-Host "ERROR: $exe not found. Build Release first (F5 or cmake --build build --config Release)"
    exit 1
}
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'deploy-release.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 3) Clean staging: copy everything except runtime-generated files and unused deps.
#    - LogText.txt = session log, config.ini = auto-generated on first run
#    - avfilter-8 / avdevice-59 / postproc-56: not in exe import table and not
#      imported by any deployed FFmpeg DLL (verified with dumpbin /DEPENDENTS)
#    - opengl32sw.dll: software-GL fallback (~20 MB); desktop PCs have a GPU,
#      ANGLE chain (D3DCompiler_47 + libEGL/libGLESv2) is kept as fallback
#    - translations: no QTranslator in code, Qt's own .qm are never loaded
#    - virtualkeyboard / qmltooling / bearer: touch keyboard, QML debugger and
#      legacy network plugin - none used by a desktop app
#    - QtGraphicalEffects / QtQuick\Extras: no matching QML import
#    - Controls.2 Imagine/Material/Universal styles: QQuickStyle uses "Default"
#    - Qt5Svg + qsvg.dll + qsvgicon.dll: no .svg asset in qml/src, exe does
#      not import Qt5Svg, imageIsSvgSource() has zero callers (dead VmsTools code)
#    - qtiff/qwebp/qtga/qwbmp/qicns image plugins: only in-app image is PNG
#      (Qt built-in codec); qjpeg/qgif/qico kept for camera snapshots
$excludeFiles = 'LogText.txt', 'config.ini', 'avfilter-8.dll', 'avdevice-59.dll',
                'postproc-56.dll', 'opengl32sw.dll', 'Qt5Svg.dll',
                'qsvg.dll', 'qtiff.dll', 'qwebp.dll', 'qtga.dll', 'qwbmp.dll', 'qicns.dll'
$excludeDirs = 'translations', 'virtualkeyboard', 'qmltooling', 'bearer',
               'QtGraphicalEffects', 'Extras', 'Imagine', 'Material', 'Universal',
               'iconengines'
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
robocopy $releaseDir $staging /E /NFL /NDL /NJH /NJS /NP /XF @excludeFiles /XD @excludeDirs | Out-Null
if ($LASTEXITCODE -ge 8) {
    Write-Host "ERROR: robocopy staging failed (code $LASTEXITCODE)"
    exit 1
}
$files = (Get-ChildItem $staging -Recurse -File).Count
$sizeMB = [math]::Round(((Get-ChildItem $staging -Recurse -File | Measure-Object Length -Sum).Sum / 1MB), 1)
Write-Host "Staging: $files files, $sizeMB MB (source: 196.3 MB)"

# 4) Locate makensis
$makensis = (Get-Command makensis -ErrorAction SilentlyContinue).Source
if (-not $makensis) {
    foreach ($p in @("${env:ProgramFiles(x86)}\NSIS\makensis.exe", "$env:ProgramFiles\NSIS\makensis.exe")) {
        if (Test-Path $p) { $makensis = $p; break }
    }
}
if (-not $makensis) {
    Write-Host 'ERROR: makensis.exe not found. Install NSIS: winget install NSIS.NSIS'
    exit 1
}

# 5) Compile installer
New-Item -ItemType Directory -Force -Path $dist | Out-Null
Push-Location $PSScriptRoot
& $makensis /INPUTCHARSET UTF8 "-DVERSION=$version" "-DSTAGING_DIR=$staging" 'IPCamConfigTools.nsi'
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { exit $code }
Get-ChildItem $dist -Filter "IPCamConfigTools-Setup-*.exe" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 |
    ForEach-Object { Write-Host ("Installer: {0}  ({1:N1} MB)" -f $_.FullName, ($_.Length / 1MB)) }

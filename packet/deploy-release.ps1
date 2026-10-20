# Deploy Qt runtime to build/Release when missing OR wrong architecture (self-healing).
# Called by VSCode task "windeployqt-release" AFTER cmake-build-release.
$root = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $root 'build\Release\IPCamConfigTools.exe'
$qml = Join-Path $root 'qml'
$qtCore = Join-Path $root 'build\Release\Qt5Core.dll'
$qmlPlugin = Join-Path $root 'build\Release\QtQuick.2\qtquick2plugin.dll'
$windeployqt = 'C:\Qt\Qt5.15.2\5.15.2\msvc2019_64\bin\windeployqt.exe'

# Sanitize PATH before calling windeployqt: the system PATH leaks 32-bit Qt kits
# (msvc2019, msvc2017) while msvc2019_64 is NOT in it. windeployqt resolves QML
# modules & binaries against PATH, which deployed 32-bit DLLs into a x64 package
# and made the app die with "plugin cannot be loaded ... error 0x000000c1".
$env:PATH = "C:\Qt\Qt5.15.2\5.15.2\msvc2019_64\bin;" + (($env:PATH -split ';' |
    Where-Object { $_ -and $_ -notmatch 'C:\\Qt\\Qt5\.15\.2\\5\.15\.2\\msvc2019(\\bin)?$' -and $_ -notmatch 'C:\\Qt\\Qt5\.12\.12' }) -join ';')

function Test-IsX64([string]$path) {
    if (-not (Test-Path $path)) { return $false }
    try {
        $fs = [System.IO.File]::OpenRead($path)
        $br = New-Object System.IO.BinaryReader($fs)
        $fs.Seek(0x3C, 'Begin') | Out-Null
        $peOff = $br.ReadInt32()
        $fs.Seek($peOff + 4, 'Begin') | Out-Null
        $machine = $br.ReadUInt16()
        $br.Close(); $fs.Close()
        return ($machine -eq 0x8664)
    } catch { return $false }
}

if ((Test-IsX64 $qtCore) -and (Test-IsX64 $qmlPlugin)) {
    Write-Host 'Qt runtime (x64) present, skip windeployqt'
} else {
    if (-not (Test-Path $exe)) {
        Write-Host "ERROR: $exe not found, build Release first"
        exit 1
    }
    if (Test-Path $qtCore) {
        Write-Host 'Qt runtime architecture mismatch (32-bit?), force redeploy'
    } else {
        Write-Host 'Qt runtime missing, deploying...'
    }
    # --force: overwrite existing files (windeployqt skips existing ones by default,
    # which once left 32-bit DLLs from a wrong-kit deploy untouched -> error 0xc1).
    & $windeployqt --release --force --qmldir $qml $exe
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# Trim unused runtime deps that windeployqt --force re-deploys.
# Same exclusion list as packet\build-installer.ps1 (staging) - evidence:
# dumpbin /DEPENDENTS shows avfilter-8/avdevice-59/postproc-56/Qt5Svg are not
# imported by the exe nor by any kept FFmpeg DLL; no .svg asset in qml/src;
# no QTranslator in code (translations never loaded); QQuickStyle fixed to
# "Default" in main.cpp (Imagine/Material/Universal styles unused).
$trimRoot = Join-Path $root 'build\Release'
$trimFiles = 'avfilter-8.dll', 'avdevice-59.dll', 'postproc-56.dll',
             'opengl32sw.dll', 'Qt5Svg.dll',
             'imageformats\qsvg.dll', 'imageformats\qtiff.dll',
             'imageformats\qwebp.dll', 'imageformats\qtga.dll',
             'imageformats\qwbmp.dll', 'imageformats\qicns.dll'
$trimDirs = 'translations', 'virtualkeyboard', 'qmltooling', 'bearer',
            'iconengines', 'QtGraphicalEffects', 'QtQuick\Extras',
            'QtQuick\Controls.2\Imagine', 'QtQuick\Controls.2\Material',
            'QtQuick\Controls.2\Universal'
foreach ($f in $trimFiles) { Remove-Item (Join-Path $trimRoot $f) -Force -ErrorAction SilentlyContinue }
foreach ($d in $trimDirs) { Remove-Item (Join-Path $trimRoot $d) -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host 'Trimmed unused runtime deps (avfilter/avdevice/postproc/opengl32sw/Qt5Svg/svg-img-plugins/styles)'

# Deploy MSVC runtime (app-local) matching the build toolset (v143 / 14.44).
# Field crash evidence: a Win7 machine loaded system-wide MSVCP140.dll 14.32
# while the exe is built by toolset 14.44 - running a newer-toolset binary on an
# older runtime is unsupported by MSVC and crashed during live streaming
# (APPCRASH, c0000005, faulting module MSVCP140.dll). App-local DLLs load before
# System32, pinning the runtime version on every machine. Update the path when
# the VS toolset is upgraded.
$vcRedistCrt = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Redist\MSVC\14.44.35112\x64\Microsoft.VC143.CRT'
if (Test-Path $vcRedistCrt) {
    $vcNames = 'msvcp140.dll', 'msvcp140_1.dll', 'msvcp140_2.dll',
               'concrt140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll'
    $vcCopied = 0
    foreach ($n in $vcNames) {
        $src = Join-Path $vcRedistCrt $n
        if (-not (Test-Path $src)) { continue }
        $dst = Join-Path $trimRoot $n
        $upToDate = $false
        if (Test-Path $dst) {
            $upToDate = ((Get-Item $src).VersionInfo.FileVersion -eq (Get-Item $dst).VersionInfo.FileVersion)
        }
        if (-not $upToDate) { Copy-Item $src $dst -Force; $vcCopied++ }
    }
    if ($vcCopied -gt 0) { Write-Host "Deployed MSVC runtime app-local ($vcCopied files updated)" }
    else { Write-Host 'MSVC runtime app-local up to date, skip' }
} else {
    Write-Host "WARNING: VC redist CRT not found at $vcRedistCrt (update path after VS upgrade?)"
}

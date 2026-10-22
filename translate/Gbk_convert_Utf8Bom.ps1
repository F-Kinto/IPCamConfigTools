# Gbk_convert_Utf8Bom.ps1
# lupdate 后执行：UTF-8-BOM->UTF-16 + GBK->UTF-8-BOM
# 将源码文件转为 lupdate 友好的编码

$gbkEncoding = [System.Text.Encoding]::GetEncoding("GBK")
$utf8BomEncoding = New-Object System.Text.UTF8Encoding($true)
$utf16Encoding = [System.Text.Encoding]::Unicode
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)

function Convert-GbkToUtf8Sig {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Host "[Warning] Path not found: $Path, skipped."
        return
    }

    $files = Get-ChildItem -Path $Path -Recurse -Include *.cpp,*.h -File
    foreach ($file in $files) {
        if ($file.Length -eq 0) {
            Write-Host "[Skip] Empty file: $($file.FullName)"
            continue
        }

        # Check if file is already valid UTF-8 (no BOM) - skip it
        try {
            $content = [System.IO.File]::ReadAllText($file.FullName, $strictUtf8)
            Write-Host "[Skip] Not GBK (already UTF-8): $($file.FullName)"
            continue
        } catch {
            # Not valid UTF-8, try GBK
        }

        try {
            $content = [System.IO.File]::ReadAllText($file.FullName, $gbkEncoding)
            [System.IO.File]::WriteAllText($file.FullName, $content, $utf8BomEncoding)
            Write-Host "[OK] GBK->UTF8BOM: $($file.FullName)"
        } catch {
            Write-Host "[Skip] Not GBK: $($file.FullName)"
        }
    }
}

function Convert-Utf8SigToUtf16 {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Host "[Warning] Path not found: $Path, skipped."
        return
    }

    $files = Get-ChildItem -Path $Path -Recurse -Include *.cpp,*.h -File
    foreach ($file in $files) {
        if ($file.Length -eq 0) {
            Write-Host "[Skip] Empty file: $($file.FullName)"
            continue
        }

        try {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $isUtf8Bom = ($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)

            if ($isUtf8Bom) {
                $content = [System.IO.File]::ReadAllText($file.FullName, $utf8BomEncoding)
                [System.IO.File]::WriteAllText($file.FullName, $content, $utf16Encoding)
                Write-Host "[OK] UTF8BOM->UTF16: $($file.FullName)"
            } else {
                Write-Host "[Skip] Not UTF-8-BOM: $($file.FullName)"
            }
        } catch {
            Write-Host "[FAIL] $($file.FullName): $_"
        }
    }
}

# First convert UTF-8-BOM to UTF-16, then GBK to UTF-8-BOM
# common dir is not scanned
Convert-Utf8SigToUtf16 "../qml"
Convert-Utf8SigToUtf16 "../src"
Convert-GbkToUtf8Sig "../qml"
Convert-GbkToUtf8Sig "../src"

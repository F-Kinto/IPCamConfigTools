# Convert_To_Gbk.ps1
# lupdate 前执行：UTF-8-BOM->GBK + UTF-16->UTF-8-BOM
# 还原源码文件原始编码，让 lupdate 能正确读取

$gbkEncoding = [System.Text.Encoding]::GetEncoding("GBK")
$utf8BomEncoding = New-Object System.Text.UTF8Encoding($true)
$utf16Encoding = [System.Text.Encoding]::Unicode

function Convert-Utf8BomToGbk {
    param([string]$Directory)

    if (-not (Test-Path $Directory)) {
        Write-Host "[Warning] Path not found: $Directory, skipped."
        return
    }

    $files = Get-ChildItem -Path $Directory -Recurse -Include *.cpp,*.h -File
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
                [System.IO.File]::WriteAllText($file.FullName, $content, $gbkEncoding)
                Write-Host "[OK] UTF8BOM->GBK: $($file.FullName)"
            } else {
                Write-Host "[Skip] Not UTF-8-BOM: $($file.FullName)"
            }
        } catch {
            Write-Host "[FAIL] $($file.FullName): $_"
        }
    }
}

function Convert-Utf16ToUtf8Sig {
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
            $isUtf16Le = ($bytes.Length -ge 2) -and ($bytes[0] -eq 0xFF) -and ($bytes[1] -eq 0xFE)

            if ($isUtf16Le) {
                $content = [System.IO.File]::ReadAllText($file.FullName, $utf16Encoding)
                [System.IO.File]::WriteAllText($file.FullName, $content, $utf8BomEncoding)
                Write-Host "[OK] UTF16->UTF8BOM: $($file.FullName)"
            } else {
                Write-Host "[Skip] Not UTF-16: $($file.FullName)"
            }
        } catch {
            Write-Host "[Skip] Not UTF-16: $($file.FullName)"
        }
    }
}

# Must convert UTF-8-BOM to GBK first, then UTF-16 to UTF-8-BOM
# common dir is not scanned
Convert-Utf8BomToGbk "../qml"
Convert-Utf8BomToGbk "../src"
Convert-Utf16ToUtf8Sig "../qml"
Convert-Utf16ToUtf8Sig "../src"

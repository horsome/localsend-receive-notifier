<#
.SYNOPSIS
    LocalSend 通知点击处理器
.DESCRIPTION
    由自定义协议 localsendfolder:// 调起，解析目标路径并用资源管理器打开。

    格式：
      localsendfolder://select/?p=<URL编码的完整文件路径>   打开所在目录并选中该文件
      localsendfolder://open/?p=<URL编码的目录路径>         直接打开该目录

    目标不存在时自动降级：单文件 -> 打开其父目录；目录也不存在则直接退出。
.NOTES
    本脚本不面向用户手动执行，由系统在点击通知时调用。
#>
param([string]$Uri)

$logPath = "$env:LOCALAPPDATA\LocalSendToast\open.log"

function Write-Log {
    param([string]$Msg)
    try {
        $dir = Split-Path -Parent $logPath
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -LiteralPath $logPath -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg) -Encoding UTF8
    } catch { }
}

if ([string]::IsNullOrWhiteSpace($Uri)) {
    Write-Log '未收到 URI 参数'
    exit
}

# ---- 解析 URI ----
$action  = 'open'
$encoded = ''

if ($Uri -match '^localsendfolder://([A-Za-z]+)/?\?(.*)$') {
    $action = $Matches[1].ToLower()
    $query  = $Matches[2]
    foreach ($pair in ($query -split '&')) {
        $kv = $pair -split '=', 2
        if ($kv.Length -eq 2 -and $kv[0] -eq 'p') {
            $encoded = $kv[1]
        }
    }
} else {
    $encoded = $Uri
}

if ([string]::IsNullOrWhiteSpace($encoded)) {
    Write-Log "无法解析目标路径: $Uri"
    exit
}

$target = ''
try { $target = [System.Uri]::UnescapeDataString($encoded) } catch { $target = $encoded }
$target = $target.Trim('"').Trim()

# ---- 路径校验与降级 ----
if (-not (Test-Path -LiteralPath $target)) {
    $parent = Split-Path -Parent $target
    if ($parent -and (Test-Path -LiteralPath $parent)) {
        Write-Log "目标不存在，降级到父目录: $target -> $parent"
        $target = $parent
        $action = 'open'
    } else {
        Write-Log "目标与父目录均不存在: $target"
        exit
    }
}

$isFile = Test-Path -LiteralPath $target -PathType Leaf

# ---- 打开 ----
try {
    if ($action -eq 'select' -and $isFile) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$target`""
        Write-Log "已定位文件: $target"
    } else {
        $dirPath = if ($isFile) { Split-Path -Parent $target } else { $target }
        Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$dirPath`""
        Write-Log "已打开目录: $dirPath"
    }
} catch {
    Write-Log "打开失败: $($_.Exception.Message)"
}

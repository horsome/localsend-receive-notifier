<#
.SYNOPSIS
    LocalSend 接收完成提醒 —— 卸载器
.DESCRIPTION
    停止监控进程、删除登录自启任务、移除自定义协议。
    可选删除安装目录与日志。属于破坏性操作，每步都会询问确认。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Uninstall.ps1
#>
[CmdletBinding()]
param(
    [switch]$Force
)

$InstallDir = Join-Path $env:LOCALAPPDATA 'LocalSendToast'
$TaskName   = 'LocalSendToastMonitor'
$Scheme     = 'localsendfolder'

Write-Host ''
Write-Host '==============================================' -ForegroundColor Yellow
Write-Host '  LocalSend 接收完成提醒 - 卸载程序' -ForegroundColor Yellow
Write-Host '==============================================' -ForegroundColor Yellow
Write-Host ''

# ---- 1. 停止进程 ----
$running = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
           Where-Object { $_.CommandLine -like '*LocalSendToast.ps1*' }
if ($running) {
    foreach ($p in $running) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] 已停止监控进程 PID $($p.ProcessId)" -ForegroundColor Green
    }
} else {
    Write-Host '  [--] 未发现运行中的监控进程' -ForegroundColor DarkGray
}

# ---- 2. 删除自启任务 ----
$q = schtasks /Query /TN $TaskName 2>&1
if ($LASTEXITCODE -eq 0) {
    $r = schtasks /Delete /TN $TaskName /F 2>&1
    if ($LASTEXITCODE -eq 0) { Write-Host "  [OK] 已删除自启任务 $TaskName" -ForegroundColor Green }
    else { Write-Host "  [失败] 任务删除失败: $r" -ForegroundColor Red }
} else {
    Write-Host '  [--] 未发现自启任务' -ForegroundColor DarkGray
}

# ---- 3. 移除协议 ----
$base = "HKCU:\Software\Classes\$Scheme"
if (Test-Path -LiteralPath $base) {
    try {
        Remove-Item -LiteralPath $base -Recurse -Force
        Write-Host "  [OK] 已移除协议 $($Scheme)://" -ForegroundColor Green
    } catch {
        Write-Host "  [失败] 协议移除失败: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host '  [--] 未发现协议注册项' -ForegroundColor DarkGray
}

# ---- 4. 删除安装目录 ----
if (Test-Path -LiteralPath $InstallDir) {
    $answer = 'N'
    if (-not $Force) {
        Write-Host ''
        Write-Host "  安装目录: $InstallDir" -ForegroundColor Cyan
        $answer = Read-Host '  是否一并删除该目录及日志？[y/N]'
    }
    if ($Force -or $answer -match '^[Yy]') {
        try {
            Remove-Item -LiteralPath $InstallDir -Recurse -Force
            Write-Host "  [OK] 已删除 $InstallDir" -ForegroundColor Green
        } catch {
            Write-Host "  [失败] 目录删除失败: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host '  [--] 保留安装目录' -ForegroundColor DarkGray
    }
} else {
    Write-Host '  [--] 未发现安装目录' -ForegroundColor DarkGray
}

Write-Host ''
Write-Host '  卸载完成。' -ForegroundColor Cyan
Write-Host ''

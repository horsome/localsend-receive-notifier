<#
.SYNOPSIS
    LocalSend 接收完成提醒 —— 一键安装器
.DESCRIPTION
    在本机完成全部配置，可重复执行（幂等）：
      1. 部署运行脚本到 %LOCALAPPDATA%\LocalSendToast
      2. 注册自定义协议 localsendfolder://（用于点击通知定位文件）
      3. 注册登录自启任务 LocalSendToastMonitor
      4. 立即启动监控
    接收目录自动从 LocalSend 的 settings.json 读取，不同电脑无需改配置。
.PARAMETER WatchPath
    强制指定监控目录（一般不需要，留空即自动跟随 LocalSend 配置）。
.PARAMETER NoStart
    只做配置，不立即启动监控。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Install.ps1
#>
[CmdletBinding()]
param(
    [string]$WatchPath = '',
    [switch]$NoStart
)

$ErrorActionPreference = 'Stop'
$InstallDir  = Join-Path $env:LOCALAPPDATA 'LocalSendToast'
$TaskName    = 'LocalSendToastMonitor'
$Scheme      = 'localsendfolder'
$SrcDir      = $PSScriptRoot

function Say  { param([string]$m, [string]$c = 'Gray')  Write-Host $m -ForegroundColor $c }
function Ok   { param([string]$m) Write-Host "  [OK]   $m" -ForegroundColor Green }
function Warn { param([string]$m) Write-Host "  [警告] $m" -ForegroundColor Yellow }
function Bad  { param([string]$m) Write-Host "  [失败] $m" -ForegroundColor Red }

Say ''
Say '==============================================' 'Cyan'
Say '  LocalSend 接收完成提醒 - 安装程序' 'Cyan'
Say '==============================================' 'Cyan'
Say ''

# ---------- 0. 环境检查 ----------
if (-not $PSVersionTable.PSVersion.Major -ge 5) {
    Bad "需要 PowerShell 5.1 及以上，当前为 $($PSVersionTable.PSVersion)"
    exit 1
}
Ok "PowerShell 版本 $($PSVersionTable.PSVersion)"

foreach ($f in @('LocalSendToast.ps1', 'OpenFolder.ps1')) {
    $src = Join-Path $SrcDir $f
    if (-not (Test-Path -LiteralPath $src)) {
        Bad "缺少安装所需文件: $src"
        Say '  请把整个文件夹一起拷贝过来，不要只拷单个文件。' 'Yellow'
        exit 1
    }
}
Ok '安装文件完整'

# ---------- 1. 探测 LocalSend ----------
Say ''
Say '[1/5] 探测 LocalSend 配置...' 'White'
$lsCfg = Join-Path $env:APPDATA 'LocalSend\settings.json'
$dest  = ''
if (Test-Path -LiteralPath $lsCfg) {
    Ok "找到配置文件: $lsCfg"
    try {
        $raw = Get-Content -LiteralPath $lsCfg -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($k in @('flutter.ls_destination', 'ls_destination', 'flutter.ls_save_dir')) {
            if ($raw.PSObject.Properties.Name -contains $k) {
                $node = $raw.$k
                if ($node -is [System.Management.Automation.PSCustomObject] -and ($node.PSObject.Properties.Name -contains 'value')) {
                    $node = $node.value
                }
                $dest = ([string]$node).Trim()
                break
            }
        }
    } catch {
        Warn "配置解析失败: $($_.Exception.Message)"
    }
    if ([string]::IsNullOrWhiteSpace($dest)) {
        $dest = Join-Path $env:USERPROFILE 'Downloads'
        Warn "配置中未设置接收目录，回退到系统下载目录"
    }
    Say "  本机接收目录: $dest" 'Cyan'
} else {
    Warn '未检测到 LocalSend 配置（可能尚未安装或从未运行过）'
    Say '  安装仍会继续，脚本运行时会持续等待可用目录并自动跟随。' 'Yellow'
}

if (-not [string]::IsNullOrWhiteSpace($WatchPath)) {
    $dest = $WatchPath
    Say "  已按参数强制指定监控目录: $dest" 'Cyan'
}
if ($dest -and (Test-Path -LiteralPath $dest)) {
    Ok '接收目录存在，可正常监控'
} elseif ($dest) {
    Warn "接收目录当前不存在: $dest（若是移动硬盘，插上后会自动恢复）"
}

# ---------- 2. 部署文件 ----------
Say ''
Say '[2/5] 部署运行文件...' 'White'
if (-not (Test-Path -LiteralPath $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}
foreach ($f in @('LocalSendToast.ps1', 'OpenFolder.ps1')) {
    $src = Join-Path $SrcDir $f
    $dst = Join-Path $InstallDir $f
    $txt = Get-Content -LiteralPath $src -Raw -Encoding UTF8
    [System.IO.File]::WriteAllText($dst, $txt, (New-Object System.Text.UTF8Encoding($true)))
    Ok "$dst"
}

# ---------- 3. 注册协议 ----------
Say ''
Say "[3/5] 注册协议 $($Scheme):// ..." 'White'
$handler = Join-Path $InstallDir 'OpenFolder.ps1'
$base = "HKCU:\Software\Classes\$Scheme"
try {
    New-Item -Path $base -Force | Out-Null
    Set-ItemProperty -Path $base -Name '(Default)' -Value 'URL:LocalSend Folder Opener'
    New-ItemProperty -Path $base -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
    New-Item -Path "$base\DefaultIcon" -Force | Out-Null
    Set-ItemProperty -Path "$base\DefaultIcon" -Name '(Default)' -Value 'explorer.exe,0'
    New-Item -Path "$base\shell\open\command" -Force | Out-Null
    $cmd = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" "%1"' -f $handler
    Set-ItemProperty -Path "$base\shell\open\command" -Name '(Default)' -Value $cmd
    Ok "已写入 $base"
} catch {
    Bad "协议注册失败: $($_.Exception.Message)"
}

# ---------- 4. 注册自启任务 ----------
Say ''
Say '[4/5] 注册登录自启任务...' 'White'
$script  = Join-Path $InstallDir 'LocalSendToast.ps1'
$argLine = if ([string]::IsNullOrWhiteSpace($WatchPath)) {
    'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $script + '"'
} else {
    'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $script + '" -WatchPath "' + $WatchPath + '"'
}
$out = schtasks /Create /TN $TaskName /TR $argLine /SC ONLOGON /RL LIMITED /F 2>&1
if ($LASTEXITCODE -eq 0) {
    Ok "任务 $TaskName 已创建/更新（登录时自动启动）"
} else {
    Bad "任务创建失败: $out"
    Say '  可尝试：右键以管理员身份运行本脚本' 'Yellow'
}

# ---------- 5. 启动监控 ----------
Say ''
Say '[5/5] 启动监控...' 'White'
if ($NoStart) {
    Warn '已按参数跳过启动，下次登录时会自动运行'
} else {
    $running = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
               Where-Object { $_.CommandLine -like '*LocalSendToast.ps1*' }
    foreach ($p in $running) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 800
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$script`"") -WindowStyle Hidden
    Start-Sleep -Seconds 3
    $now = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
           Where-Object { $_.CommandLine -like '*LocalSendToast.ps1*' }
    if ($now) { Ok "监控已启动 (PID $($now[0].ProcessId))" } else { Bad '启动失败，请查看日志' }
}

# ---------- 汇总 ----------
Say ''
Say '==============================================' 'Cyan'
Say '  安装完成' 'Green'
Say '==============================================' 'Cyan'
Say ''
Say "  监控目录 : $(if ($dest) { $dest } else { '自动跟随 LocalSend 配置' })"
Say "  安装位置 : $InstallDir"
Say "  自启任务 : $TaskName"
Say "  运行日志 : $(Join-Path $InstallDir 'monitor.log')"
Say "  点击日志 : $(Join-Path $InstallDir 'open.log')"
Say ''
Say '  验证方法：用手机往本机发一个文件，接收完成后应弹出通知，' 'White'
Say '           点击通知可直接定位到该文件。' 'White'
Say ''

if (-not $NoStart) {
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        $x = New-Object Windows.Data.Xml.Dom.XmlDocument
        $x.LoadXml('<toast duration="short"><visual><binding template="ToastGeneric"><text>LocalSend 提醒已就绪</text><text>接收文件后将自动通知，点击可定位文件</text></binding></visual><audio src="ms-winsoundevent:Notification.Default"/></toast>')
        $t = New-Object Windows.UI.Notifications.ToastNotification $x
        $mgr = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe')
        $mgr.Show($t)
        Say '  已发送一条测试通知，请留意右下角。' 'Cyan'
    } catch { }
}
Say ''

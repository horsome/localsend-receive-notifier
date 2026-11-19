<#
.SYNOPSIS
    LocalSend 接收完成提醒（多机通用版）
.DESCRIPTION
    监控 LocalSend 接收目录，文件完整落盘后弹出 Windows 原生通知，点击通知可定位到文件。

    多机适配：未显式指定 -WatchPath 时，自动从 LocalSend 的 settings.json 读取当前接收目录，
    因此不同电脑（接收目录不同）无需改任何配置。目录暂时不可用（如移动硬盘未挂载、
    用户在 LocalSend 里改了保存位置）时会持续重试并自动跟随新目录。
.PARAMETER WatchPath
    显式指定监控目录。留空（默认）表示自动跟随 LocalSend 配置。
.PARAMETER PollSeconds
    扫描间隔秒数，默认 2。
.PARAMETER StableRounds
    判定文件写完所需的连续大小不变轮数，默认 2。
.PARAMETER BatchWindow
    多个文件的合并通知窗口（秒），默认 3。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File LocalSendToast.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File LocalSendToast.ps1 -WatchPath "D:\Downloads"
#>
[CmdletBinding()]
param(
    [string]$WatchPath   = '',
    [int]$PollSeconds    = 2,
    [int]$StableRounds   = 2,
    [double]$BatchWindow = 3,
    [string]$LogPath     = "$env:LOCALAPPDATA\LocalSendToast\monitor.log",
    [string]$Scheme      = 'localsendfolder',
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# ---------- 单实例互斥 ----------
$mutex = New-Object System.Threading.Mutex($false, 'Local\LocalSendToastMonitor')
if (-not $mutex.WaitOne(0)) {
    Write-Host 'LocalSendToast 已在运行中，本次启动跳过。'
    exit 0
}

# ---------- 日志 ----------
$logDir = Split-Path -Parent $LogPath
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
function Write-Log {
    param([string]$Msg)
    try {
        $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    } catch { }
}

# ---------- 通知通道 ----------
try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
} catch {
    Write-Log "Toast 类型加载失败: $($_.Exception.Message)"
}

$script:AppId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

function Show-Toast {
    param([string]$Title, [string]$Body, [string]$LaunchUri)
    $t = [System.Security.SecurityElement]::Escape($Title)
    $b = [System.Security.SecurityElement]::Escape($Body)
    $activation = ''
    if (-not [string]::IsNullOrWhiteSpace($LaunchUri)) {
        $activation = ' activationType="protocol" launch="{0}"' -f [System.Security.SecurityElement]::Escape($LaunchUri)
    }
    $xmlText = @"
<toast duration="short"$activation>
  <visual>
    <binding template="ToastGeneric">
      <text>$t</text>
      <text>$b</text>
    </binding>
  </visual>
  <audio src="ms-winsoundevent:Notification.Default"/>
</toast>
"@
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($xmlText)
    $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($script:AppId)
    $notifier.Show($toast)
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

# ---------- 自动探测 LocalSend 接收目录 ----------
function Get-LocalSendDestination {
    $cfgCandidates = @(
        (Join-Path $env:APPDATA 'LocalSend\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'LocalSend\settings.json')
    )
    foreach ($cfg in $cfgCandidates) {
        if (-not (Test-Path -LiteralPath $cfg)) { continue }
        try {
            $raw = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch { continue }

        $node = $null
        foreach ($key in @('flutter.ls_destination', 'ls_destination', 'flutter.ls_save_dir')) {
            if ($raw.PSObject.Properties.Name -contains $key) { $node = $raw.$key; break }
        }
        if ($null -eq $node) { continue }

        # 兼容 shared_preferences 的 {value=...} 包装格式
        if ($node -is [System.Management.Automation.PSCustomObject] -and
            ($node.PSObject.Properties.Name -contains 'value')) {
            $node = $node.value
        }

        $p = [string]$node
        if ([string]::IsNullOrWhiteSpace($p)) {
            $p = Join-Path $env:USERPROFILE 'Downloads'
        }
        $p = $p.Trim().TrimEnd('\')
        return $p
    }
    return $null
}

# ---------- 绑定监控目录 ----------
$script:ActivePath = $null
$script:Seen       = @{}
$script:Candidates = @{}

function Set-ActivePath {
    param([string]$Path)
    $script:ActivePath   = $Path
    $script:Seen         = @{}
    $script:Candidates   = @{}
    Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object { $script:Seen[$_.FullName] = $_.Length }
    Write-Log "监控目录已绑定: $Path （已有文件 $($script:Seen.Count) 个）"
}

function Resolve-WatchPath {
    if (-not [string]::IsNullOrWhiteSpace($WatchPath)) { return $WatchPath.TrimEnd('\') }
    return Get-LocalSendDestination
}

$initial = Resolve-WatchPath
if ($initial -and (Test-Path -LiteralPath $initial)) {
    Set-ActivePath -Path $initial
} else {
    Write-Log "启动时接收目录不可用（$initial），进入自动重试模式"
}

Write-Log "监控启动 | 轮询=${PollSeconds}s | 模式=$(if ([string]::IsNullOrWhiteSpace($WatchPath)) {'自动跟随 LocalSend 配置'} else {'固定目录'})"
if (-not $Quiet) { Write-Host "LocalSendToast 已启动，当前监控: $(if ($script:ActivePath) { $script:ActivePath } else { '(等待接收目录可用)' })" }

$batch      = @()
$batchStart = $null

# ---------- 主循环 ----------
while ($true) {
    Start-Sleep -Seconds $PollSeconds

    # 目录不可用 / 已变更时重新解析
    if (-not $script:ActivePath -or -not (Test-Path -LiteralPath $script:ActivePath)) {
        $resolved = Resolve-WatchPath
        if ($resolved -and (Test-Path -LiteralPath $resolved)) {
            if ($resolved -ne $script:ActivePath) {
                Write-Log "接收目录变化: $($script:ActivePath) -> $resolved"
                Set-ActivePath -Path $resolved
            }
        } else {
            Write-Log "接收目录暂不可用，继续等待: $resolved"
            continue
        }
    }

    $files = Get-ChildItem -LiteralPath $script:ActivePath -File -Recurse -ErrorAction SilentlyContinue

    foreach ($f in $files) {
        $p = $f.FullName
        if ($script:Seen.ContainsKey($p)) { continue }
        if ($f.Length -le 0) { continue }

        $rec = $script:Candidates[$p]
        if ($null -eq $rec) {
            $script:Candidates[$p] = @{ Size = $f.Length; Hits = 1 }
            continue
        }
        if ($rec.Size -ne $f.Length) {
            $script:Candidates[$p] = @{ Size = $f.Length; Hits = 1 }
            continue
        }
        $rec.Hits++
        if ($rec.Hits -lt $StableRounds) { continue }

        $busy = $false
        try {
            $fs = [System.IO.File]::Open($p, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
            $fs.Close(); $fs.Dispose()
        } catch { $busy = $true }
        if ($busy) { continue }

        $script:Seen[$p] = $f.Length
        $script:Candidates.Remove($p)
        $batch += [pscustomobject]@{ Name = $f.Name; Full = $p; Size = $f.Length }
        if ($null -eq $batchStart) { $batchStart = Get-Date }
        Write-Log "检测到新文件: $p ($(Format-Size $f.Length))"
    }

    foreach ($k in @($script:Candidates.Keys)) {
        if (-not (Test-Path -LiteralPath $k)) { $script:Candidates.Remove($k) }
    }

    if ($batch.Count -gt 0 -and $null -ne $batchStart) {
        if (((Get-Date) - $batchStart).TotalSeconds -ge $BatchWindow) {
            $total = ($batch | Measure-Object -Property Size -Sum).Sum
            $launchUri = ''
            if ($batch.Count -eq 1) {
                $title = 'LocalSend 接收完成'
                $body  = "{0}  ({1})`n保存至: {2}`n点击通知可直接定位该文件" -f $batch[0].Name, (Format-Size $total), (Split-Path -Parent $batch[0].Full)
                $launchUri = '{0}://select/?p={1}' -f $Scheme, [System.Uri]::EscapeDataString($batch[0].Full)
            } else {
                $title = "LocalSend 接收完成 · $($batch.Count) 个文件"
                $names = ($batch | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', '
                if ($batch.Count -gt 3) { $names += ' 等' }
                $body  = "{0}`n合计 {1}`n点击通知可打开接收目录" -f $names, (Format-Size $total)
                $launchUri = '{0}://open/?p={1}' -f $Scheme, [System.Uri]::EscapeDataString($script:ActivePath)
            }
            try {
                Show-Toast -Title $title -Body $body -LaunchUri $launchUri
                Write-Log "已弹出通知: $title | $($body -replace "`n", ' ')"
            } catch {
                Write-Log "通知弹出失败: $($_.Exception.Message)"
            }
            $batch = @()
            $batchStart = $null
        }
    }
}

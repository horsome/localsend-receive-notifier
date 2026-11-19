---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 582f2cf4cea5162784b9d16334da1fa6_52855853e3ea11f19231525400638852
    ReservedCode1: oRxeMv9vKDVofWCVFW+PIuy12br5tHbJm5mfgTQQ33TfqMavIdto2Q6aGXzifc58fbUE4WYC2Ia8/ugxAs/kqfFMsoxbkHmAJ3FkZHy3mRngVtyFhUe6SsfXvWc6W7ZIBjflQwRyGiYMJGKzS8JAhLotfXfhR2ieDDJZETxqyOM52TJUkOoMuALiGQs=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 582f2cf4cea5162784b9d16334da1fa6_52855853e3ea11f19231525400638852
    ReservedCode2: oRxeMv9vKDVofWCVFW+PIuy12br5tHbJm5mfgTQQ33TfqMavIdto2Q6aGXzifc58fbUE4WYC2Ia8/ugxAs/kqfFMsoxbkHmAJ3FkZHy3mRngVtyFhUe6SsfXvWc6W7ZIBjflQwRyGiYMJGKzS8JAhLotfXfhR2ieDDJZETxqyOM52TJUkOoMuALiGQs=
---



# LocalSend Receive Notifier

**by Horsome Mark**

> Get a native Windows toast notification whenever [LocalSend](https://localsend.org) finishes receiving a file — and click it to jump straight to that file in Explorer.

[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D4)](https://www.microsoft.com/windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)](https://learn.microsoft.com/powershell/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

English | [简体中文](README.zh-CN.md)

---

## The problem

LocalSend is excellent at moving files between devices, but its Windows desktop build **sends no notification at all** when a transfer completes. Files land silently in the receive folder and you have no idea whether the transfer finished, or where the file went.

This project is a small, dependency-free monitor that fills that gap.

## Features

- **Native toast notification** when a file finishes landing — with file name, size and destination
- **Click to locate** — single file: opens Explorer with the file selected; multiple files: opens the receive folder
- **Zero configuration** — the watch folder is read from LocalSend's own `settings.json`, so the same package works on every machine even when receive folders differ
- **Auto-rebind** — if you change the save location in LocalSend, or your external drive remounts, the monitor follows automatically
- **Accurate completion detection** — a file is only announced once its size stays stable and it can be opened exclusively, so large transfers never trigger false alarms
- **Batch merging** — files arriving within 3 seconds are merged into one notification instead of spamming you
- **No admin rights** — everything is per-user (`HKCU` + a logon scheduled task), nothing touches `HKLM` or system services
- **No dependencies** — pure PowerShell 5.1, no modules to install, no runtime

## Install

1. Download or clone this repository
2. Double-click **`install.bat`**
3. Done — you should see a test notification

The installer will:

| Step | Action |
|---|---|
| 1 | Detect the LocalSend receive folder from `%APPDATA%\LocalSend\settings.json` |
| 2 | Deploy scripts to `%LOCALAPPDATA%\LocalSendToast\` |
| 3 | Register the `localsendfolder://` protocol under `HKCU` |
| 4 | Create the logon task `LocalSendToastMonitor` |
| 5 | Start the monitor immediately |

The installer is idempotent — run it again any time to repair or update.

### Manual install

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

Stops the monitor, removes the scheduled task and the protocol handler, then asks whether to delete the install directory and logs.

## How it works

```
LocalSend saves a file
        │
        ▼
LocalSendToast.ps1  (polls the receive folder)
        │  size stable for 2 rounds  +  exclusive read succeeds
        ▼
Windows Toast  ─── activationType="protocol"
        │              launch="localsendfolder://select/?p=<encoded path>"
        ▼  (user clicks)
ShellExecute → OpenFolder.ps1 → explorer.exe /select,"<path>"
```

A few design notes worth knowing if you plan to modify it:

- **Why a custom protocol?** PowerShell has no toast activation callback. `ToastNotificationManager` can only fire and forget. Routing the click through a registered URI scheme is the only way to make the notification actionable without shipping a compiled COM activator.
- **Why polling instead of `FileSystemWatcher`?** `FileSystemWatcher` reports a file the moment it is created, long before it is complete. Polling with a stability check is simpler and more reliable for detecting transfer completion across SMB, removable drives and NAS paths.
- **Why the PowerShell AUMID?** Toasts need an AppUserModelID. Reusing PowerShell's built-in one avoids registering an application manifest.

## Configuration

All parameters are optional; defaults work for most setups.

| Parameter | Default | Description |
|---|---|---|
| `-WatchPath` | *(auto)* | Watch folder. Empty means follow LocalSend's config. |
| `-PollSeconds` | `2` | Folder scan interval in seconds |
| `-StableRounds` | `2` | Consecutive unchanged-size scans required before announcing |
| `-BatchWindow` | `3` | Seconds to merge multiple arriving files into one notification |
| `-LogPath` | `%LOCALAPPDATA%\LocalSendToast\monitor.log` | Monitor log |
| `-Scheme` | `localsendfolder` | URI scheme used for click-through |
| `-Quiet` | off | Suppress console output |

Example — watch a fixed folder instead of auto-detection:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File LocalSendToast.ps1 -WatchPath "D:\Inbox"
```

## Logs

| File | Contents |
|---|---|
| `%LOCALAPPDATA%\LocalSendToast\monitor.log` | Detected files, notifications fired, errors |
| `%LOCALAPPDATA%\LocalSendToast\open.log` | Results of notification click-through |

## Requirements

- Windows 10 (1809+) or Windows 11
- Windows PowerShell 5.1 (included with Windows) — PowerShell 7 is not required
- LocalSend desktop build installed for the current user

## FAQ

**No notification at all?**
Check that a PowerShell process with `LocalSendToast.ps1` in its command line is running, then inspect `monitor.log`. Also confirm Windows notifications are enabled and Do Not Disturb is off.

**Clicking the notification does nothing?**
See `open.log`. If it reports the target no longer exists, the file was moved or deleted — the handler falls back to opening the parent folder.

**Does this work with the portable LocalSend build?**
Portable builds may not create `settings.json`, in which case auto-detection falls back to your Downloads folder. Pass `-WatchPath` explicitly in that case.

**Will it work on macOS / Linux?**
No — the toast layer and protocol registration are Windows-specific. PRs for other platforms are welcome as separate projects.

**Does it upload anything anywhere?**
No. It is a local file watcher. No network access, no telemetry.

## Disclaimer

This is an unofficial, community project. It is not affiliated with, endorsed by, or connected to the LocalSend project. It does not modify LocalSend — it only observes the folder LocalSend writes to.

## License

[MIT](LICENSE)
*（内容由AI生成，仅供参考）*
*（内容由AI生成，仅供参考）*

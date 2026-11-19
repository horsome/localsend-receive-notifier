---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 582f2cf4cea5162784b9d16334da1fa6_5350e76ee3ea11f19231525400638852
    ReservedCode1: ctLiIf+3Mtt3fXwLN1w7W3kYCDs0mMCrKmgzOmuUrI5eUgSNw55MNJwVQT8PF/aX+k9h/DUlpxK7It8XN4C0vemG/waah92H8kvJiA0z/AUXVh52Z1hzkV+C64lOyFHETsu2U1EHTXOoCr7Gw7eC594kg65PnUSibnT3LvA7t7SZ/XYA8Bep1znjsA8=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 582f2cf4cea5162784b9d16334da1fa6_5350e76ee3ea11f19231525400638852
    ReservedCode2: ctLiIf+3Mtt3fXwLN1w7W3kYCDs0mMCrKmgzOmuUrI5eUgSNw55MNJwVQT8PF/aX+k9h/DUlpxK7It8XN4C0vemG/waah92H8kvJiA0z/AUXVh52Z1hzkV+C64lOyFHETsu2U1EHTXOoCr7Gw7eC594kg65PnUSibnT3LvA7t7SZ/XYA8Bep1znjsA8=
---



# LocalSend 接收完成提醒

**作者：Horsome Mark**

> 当 [LocalSend](https://localsend.org) 接收完文件时，弹出 Windows 原生通知 —— 点击通知直接跳到文件所在位置。

[![平台](https://img.shields.io/badge/平台-Windows%2010%20%7C%2011-0078D4)](https://www.microsoft.com/windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)](https://learn.microsoft.com/powershell/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[English](README.md) | 简体中文

---

## 为什么需要它

LocalSend 跨设备传文件很方便，但它的 Windows 桌面版在接收完成后**不发任何通知**。文件静静地落进接收目录，你既不知道传完没有，也不知道存到了哪里。

这个项目就是一个零依赖的小监控器，专门补上这个缺口。

## 特性

- **接收完成即弹窗**：原生 Toast 通知，显示文件名、大小、保存位置
- **点击定位**：单个文件 — 打开资源管理器并选中该文件；多个文件 — 打开接收目录
- **零配置**：监控目录直接从 LocalSend 自己的 `settings.json` 读取，因此同一个安装包在任何电脑上都能用，即使各机接收目录不同
- **自动跟随**：在 LocalSend 里改了保存位置、或移动硬盘重新挂载，监控会自动重新绑定
- **准确的完成判定**：文件大小连续稳定且能被独占读取才通知，大文件传输不会误报
- **批量合并**：3 秒内连续到达的多个文件合并成一条通知，不刷屏
- **无需管理员**：全部用户级（`HKCU` + 登录计划任务），不碰 `HKLM` 和系统服务
- **零依赖**：纯 PowerShell 5.1，不用装任何模块，没有运行时

## 安装

1. 下载或克隆本仓库
2. 双击 **`install.bat`**
3. 完成 —— 你应该会看到一条测试通知

安装器会做这些事：

| 步骤 | 动作 |
|---|---|
| 1 | 从 `%APPDATA%\LocalSend\settings.json` 探测接收目录 |
| 2 | 部署脚本到 `%LOCALAPPDATA%\LocalSendToast\` |
| 3 | 在 `HKCU` 下注册 `localsendfolder://` 协议 |
| 4 | 创建登录任务 `LocalSendToastMonitor` |
| 5 | 立即启动监控 |

安装器是幂等的 —— 随时可以重跑，用于修复或更新。

### 手动安装

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

## 卸载

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

依次停止监控、删除计划任务、移除协议处理器，最后询问是否删除安装目录与日志。

## 工作原理

```
LocalSend 写入文件
        │
        ▼
LocalSendToast.ps1（轮询接收目录）
        │  大小连续 2 轮不变 + 独占读取成功
        ▼
Windows Toast  ─── activationType="protocol"
        │              launch="localsendfolder://select/?p=<编码路径>"
        ▼  （用户点击）
ShellExecute → OpenFolder.ps1 → explorer.exe /select,"<路径>"
```

几个设计说明，供二次开发参考：

- **为什么要自定义协议？** PowerShell 没有 Toast 激活回调能力，`ToastNotificationManager` 只能发不能收。通过注册 URI scheme 把点击转交系统 ShellExecute，是唯一不需要附带编译版 COM 激活器的可行方案。
- **为什么用轮询而不是 `FileSystemWatcher`？** `FileSystemWatcher` 在文件刚创建时就会报告，而那时文件远未写完。轮询配合稳定性检查，在 SMB、移动硬盘、NAS 路径上判断传输完成更可靠。
- **为什么用 PowerShell 的 AUMID？** Toast 需要 AppUserModelID，复用 PowerShell 自带的不必注册应用清单。

## 参数

全部参数可选，默认值适用于绝大多数场景。

| 参数 | 默认值 | 说明 |
|---|---|---|
| `-WatchPath` | *自动* | 监控目录，留空表示跟随 LocalSend 配置 |
| `-PollSeconds` | `2` | 目录扫描间隔（秒） |
| `-StableRounds` | `2` | 判定完成所需的连续大小不变次数 |
| `-BatchWindow` | `3` | 多文件合并通知窗口（秒） |
| `-LogPath` | `%LOCALAPPDATA%\LocalSendToast\monitor.log` | 监控日志 |
| `-Scheme` | `localsendfolder` | 点击跳转用的 URI scheme |
| `-Quiet` | 关闭 | 不输出控制台信息 |

示例 —— 指定固定目录而不自动探测：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File LocalSendToast.ps1 -WatchPath "D:\Inbox"
```

## 日志

| 文件 | 内容 |
|---|---|
| `%LOCALAPPDATA%\LocalSendToast\monitor.log` | 检测到的文件、已弹通知、异常 |
| `%LOCALAPPDATA%\LocalSendToast\open.log` | 通知点击的处理结果 |

## 环境要求

- Windows 10 (1809+) 或 Windows 11
- Windows PowerShell 5.1（系统自带），不需要 PowerShell 7
- 当前用户已安装 LocalSend 桌面版

## 常见问题

**完全没有通知？**
先确认命令行含 `LocalSendToast.ps1` 的 PowerShell 进程在运行，再看 `monitor.log`。同时检查 Windows 通知已开启、勿扰模式已关闭。

**点击通知没反应？**
看 `open.log`。若提示目标不存在，说明文件已被移动或删除，此时会降级打开父目录。

**支持 LocalSend 便携版吗？**
便携版可能不生成 `settings.json`，这种情况下自动探测会回退到「下载」文件夹。请显式传入 `-WatchPath`。

**支持 macOS / Linux 吗？**
不支持 —— 通知层和协议注册都是 Windows 专属实现。欢迎以独立项目的形式提交其他平台的版本。

**会上传数据吗？**
不会。这是纯本地文件监控：不联网、无遥测。

## 免责声明

这是非官方的社区项目，与 LocalSend 官方无任何隶属或背书关系。它不修改 LocalSend 本体 —— 只是观察 LocalSend 写入的目录。

## 许可证

[MIT](LICENSE)
*（内容由AI生成，仅供参考）*
*（内容由AI生成，仅供参考）*

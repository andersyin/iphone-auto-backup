<div align="center">

# iPhone Auto Backup

Auto-backup iPhone photos & videos to external drive on USB plug-in.<br>
EXIF date archiving, content-hash dedup, zero cloud dependency.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)
![Language](https://img.shields.io/badge/language-Bash-green.svg)
![Dependencies](https://img.shields.io/badge/dependencies-libimobiledevice%20%2B%20exiftool-orange.svg)
![Stars](https://img.shields.io/github/stars/andersyin/iphone-auto-backup?style=social)

[English](#features) | [中文文档](#中文文档)

</div>

---

## Why this exists

Every time you plug in your iPhone, macOS wants to open Photos.app or Image Capture — but neither gives you **automatic, deduplicated, date-sorted** backups to an external drive. iCloud costs money and locks you in. iMazing is $40+. This tool does it for free, with zero cloud, and runs entirely via `launchd` + `libimobiledevice`.

## Features

- **Auto-trigger on USB plug-in** — `launchd` daemon detects iPhone connection, no manual action needed
- **Content-hash dedup** — SHA1 of first/last 512KB + file size, never backup the same file twice
- **EXIF date archiving** — reads `CreateDate` / `DateTimeOriginal`, sorts into `YYYY-MM-DD` folders
- **Smart photo classification** — auto-separates camera photos / screenshots / saved images into subdirectories
- **Device-side pre-filter** — skips download entirely when file path + size unchanged (instant pass for already-backed-up files)
- **Integrity verification** — compares local vs device file size after AFC download, auto-retries on truncation
- **Sleep prevention** — keeps your Mac awake during backup via `caffeinate`
- **Desktop notifications** — macOS native notifications for start / complete / error
- **No cloud, no vendor lock-in** — files live on your disk, plain `YYYY-MM-DD/001.mov` structure

## How it works

```
iPhone (USB)
    │
    ▼
┌─────────────────────────────┐
│  iphone_backup_monitor.sh   │  ← launchd daemon (KeepAlive)
│  Polls idevice_id every 10s │
└──────────┬──────────────────┘
           │ iPhone detected & trusted
           ▼
    ┌──────┴──────┐
    ▼             ▼
 backup_videos   backup_photos
    │             │
    │  ┌──────────┘
    ▼  ▼
 Scan DCIM via afcclient
    │
    ▼
 Device-side pre-filter ──── skip (path+size unchanged)
    │
    ▼
 Download via AFC
    │
    ▼
 Size verify (retry on truncation)
    │
    ▼
 Content hash dedup ──────── skip (hash already seen)
    │
    ▼
 Read EXIF date ──→ fallback: filename ──→ device mtime ──→ _unknown_date
    │
    ▼
 Classify (photo/screenshot/saved)   ← photos only
    │
    ▼
 Archive → /Volumes/Drive/iPhone_Photos/Photos/2026-04-09/001.heic
    │
    ▼
 Set file mtime = EXIF timestamp
    │
    ▼
 macOS notification ✅
```

## Quick Start

```bash
# 1. Clone
git clone https://github.com/andersyin/iphone-auto-backup.git
cd iphone-auto-backup

# 2. Install (auto-installs libimobiledevice + exiftool via Homebrew, registers launchd)
bash install.sh

# 3. Edit config to point to your external drive
nano config.sh
```

Plug in your iPhone → trust the computer → backup runs automatically.

## Terminal Demo

```
$ bash backup_videos_v3.sh

[14:23:01] ==== iPhone 视频备份 v3 ====
[OK] iPhone 已连接
[14:23:01] 已阻止 Mac 睡眠 (PID 48291)
[14:23:01] 正在扫描 iPhone...
[OK] 发现 47 个视频

  45% |████████████░░░░░░░░░░░░| 21/47  IMG_4523.MOV
[OK] IMG_4523.MOV → 2026-04-07/001.mov
[SKIP] 内容重复: IMG_4524.MOV
[OK] IMG_4525.MOV → 2026-04-07/002.mov
  ...
[OK] IMG_4569.MOV → 2026-04-09/003.mov

======================================================================
                    iPhone 视频备份报告
======================================================================
同步文件夹:   /Volumes/MyDrive/iPhone_Videos
  共计:       482 个视频文件
  新增:       12 个视频
  跳过:       35 个（已存在/内容重复，其中 28 个设备侧未变、免下载秒过）
  失败:       0 个
======================================================================
```

## Comparison

| Feature | iCloud Photos | Image Capture | iMazing | **This tool** |
|---------|:---:|:---:|:---:|:---:|
| Free | 5GB limit | Yes | $40+ | **Yes** |
| Auto on USB plug-in | No (Wi-Fi) | No (manual) | Yes | **Yes** |
| Content-hash dedup | No | No | No | **Yes** |
| Sort by EXIF date | No | No | Yes | **Yes** |
| Photo classification | No | No | No | **Yes** |
| Incremental (skip seen) | N/A | No | Yes | **Yes** (device-side) |
| No cloud dependency | No | Yes | Yes | **Yes** |
| Open source | N/A | No | No | **Yes** |
| File mtime = shoot date | N/A | No | No | **Yes** |

## Backup Structure

```
/Volumes/YourDrive/iPhone_Videos/
└── 2026-04-07/
    ├── 001.mov
    └── 002.mov

/Volumes/YourDrive/iPhone_Photos/
├── Photos/
│   └── 2026-04-09/
│       ├── 001.jpg
│       └── 002.heic
├── Screenshots/
│   └── 2026-04-10/
│       └── 001.png
└── Saved_Images/
    └── 2026-04-10/
        └── 001.gif
```

## Configuration (`config.sh`)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `BACKUP_ROOT` | Video backup target path | `/Volumes/YourExternalDrive/iPhone_Videos` |
| `PHOTO_BACKUP_ROOT` | Photo backup target path | `/Volumes/YourExternalDrive/iPhone_Photos` |
| `VIDEO_EXTENSIONS` | Supported video formats | `MOV MP4 M4V 3GP AVI MKV` |
| `PHOTO_EXTENSIONS` | Supported photo formats | `JPG JPEG HEIC PNG GIF` |
| `AUTO_REFRESH_INDEX` | Run `refresh_index.sh` after backup if available | `0` (off) |

## Dependencies

| Tool | Purpose | Install |
|------|---------|---------|
| `libimobiledevice` | iPhone communication (afcclient / idevicepair) | `brew install libimobiledevice` |
| `exiftool` | Read EXIF dates from photos/videos | `brew install exiftool` |

> No macFUSE / ifuse needed. Only macOS built-in tools + 2 Homebrew packages.

## Requirements

- macOS (Apple Silicon preferred; Intel Macs change `/opt/homebrew/bin` → `/usr/local/bin`)
- iPhone with USB connection (must click "Trust This Computer")
- External drive or designated backup directory

## Manual Run

```bash
bash backup_videos_v3.sh    # backup videos
bash backup_photos_v3.sh    # backup photos
```

## Logs

```bash
cat /tmp/iphone_backup_monitor.status    # monitor state
cat /tmp/iphone_backup_stdout.log        # video backup log
cat /tmp/iphone_photo_backup_stdout.log  # photo backup log
```

## File Structure

```
iphone-auto-backup/
├── config.sh                             # Configuration (edit before first use)
├── backup_videos_v3.sh                   # Video backup script
├── backup_photos_v3.sh                   # Photo backup script
├── backup_safe.sh                        # Simple backup (v1, copy-only, no dedup)
├── iphone_backup_monitor.sh              # Device watcher daemon
├── rebuild_hash_index.sh                 # Hash index rebuild tool
├── install.sh                            # One-click install (registers launchd)
├── uninstall.sh                          # Uninstall launchd
├── com.user.iphone-backup-monitor.plist  # launchd config (monitor)
├── com.user.iphone-video-backup.plist    # launchd config (legacy video)
└── com.user.iphone-photo-backup.plist    # launchd config (legacy photo)
```

## FAQ

**Q: Backup doesn't auto-trigger?**
A: Make sure you clicked "Trust This Computer" on the iPhone. Re-run `bash install.sh` to re-register launchd. Check `cat /tmp/iphone_backup_monitor.status`.

**Q: Same video backed up twice?**
A: v3 uses content-hash dedup (first/last 512KB + file size → SHA1). The hash index lives at `~/.iphone_video_backup_v3.hashes`.

**Q: External drive wasn't mounted, backup failed?**
A: The script logs the error and sends a notification without crashing. Run manually once the drive is mounted:
```bash
bash backup_videos_v3.sh
bash backup_photos_v3.sh
```

**Q: How to uninstall auto-trigger?**
```bash
bash uninstall.sh
```
This only removes the launchd config. Scripts, backup data, and hash indexes are untouched.

## Uninstall

```bash
bash uninstall.sh
```

To completely wipe all data:
```bash
rm -f ~/.iphone_video_backup_v3.hashes ~/.iphone_photo_backup_v3.hashes
rm -f ~/.iphone_video_backup_v3.device_seen ~/.iphone_photo_backup_v3.device_seen
rm -rf /Volumes/YourExternalDrive/iPhone_Videos /Volumes/YourExternalDrive/iPhone_Photos
```

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)

---

## 中文文档

iPhone 插入 Mac 时自动备份视频和照片到外置硬盘，按 EXIF 拍摄日期归档，内容哈希精确去重，零云依赖。

### 特性

- **自动触发**：iPhone 插入 USB 即自动备份，无需手动操作
- **内容哈希去重**：首尾 512KB + 文件大小 → SHA1，同一内容不会重复备份
- **按拍摄日期归档**：读取 EXIF CreateDate，自动按 `YYYY-MM-DD` 分文件夹
- **照片智能分类**：自动区分相机照片 / 截图 / 保存的图片，分目录存放
- **增量预筛**：设备路径+文件大小未变 → 跳过下载，秒过已有文件
- **完整性校验**：AFC 下载后比对设备侧文件大小，截断自动重试
- **防睡眠**：备份期间阻止 Mac 休眠
- **桌面通知**：备份开始/完成/异常均推送 macOS 通知

### 快速开始

```bash
git clone https://github.com/andersyin/iphone-auto-backup.git
cd iphone-auto-backup
bash install.sh    # 自动安装依赖 + 注册 launchd
nano config.sh     # 改成你的外置硬盘路径
```

插入 iPhone → 信任电脑 → 自动开始备份。

### 配置说明

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `BACKUP_ROOT` | 视频备份目标路径 | `/Volumes/YourExternalDrive/iPhone_Videos` |
| `PHOTO_BACKUP_ROOT` | 照片备份目标路径 | `/Volumes/YourExternalDrive/iPhone_Photos` |
| `VIDEO_EXTENSIONS` | 支持的视频格式 | `MOV MP4 M4V 3GP AVI MKV` |
| `PHOTO_EXTENSIONS` | 支持的照片格式 | `JPG JPEG HEIC PNG GIF` |
| `AUTO_REFRESH_INDEX` | 备份后自动刷新媒体索引 | `0`（关闭） |

### 依赖

| 工具 | 用途 | 安装方式 |
|------|------|----------|
| `libimobiledevice` | iPhone 通信协议 | `brew install libimobiledevice` |
| `exiftool` | 读取拍摄日期 | `brew install exiftool` |

### 常见问题

**Q: 备份没有自动触发？**
A: 确认 iPhone 已点击「信任此电脑」；重新运行 `bash install.sh`；检查 `cat /tmp/iphone_backup_monitor.status`。

**Q: 重复备份同一个视频？**
A: v3 使用内容哈希去重，哈希索引位于 `~/.iphone_video_backup_v3.hashes`。

**Q: 怎么卸载？**
```bash
bash uninstall.sh
```

<div align="center">

**If this tool saved your photos, consider giving it a ⭐**

</div>

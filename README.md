# iPhone Auto Backup

iPhone 插入 Mac 时，自动将视频和照片备份到外置硬盘，按拍摄日期归档，内容哈希精确去重。

## 特性

- **自动触发**：iPhone 插入 USB 即自动备份，无需手动操作
- **内容哈希去重**：首尾 512KB + 文件大小 → SHA1，同一内容不会重复备份
- **按拍摄日期归档**：读取 EXIF/CreateDate，自动按 `YYYY-MM-DD` 分文件夹
- **照片智能分类**：自动区分相机照片 / 截图 / 保存的图片，分目录存放
- **增量预筛**：设备路径+文件大小未变 → 跳过下载，秒过已有文件
- **完整性校验**：AFC 下载后比对设备侧文件大小，截断自动重试
- **防睡眠**：备份期间阻止 Mac 休眠
- **桌面通知**：备份开始/完成/异常均推送 macOS 通知

## 文件结构

```
iphone-auto-backup/
├── config.sh                             # 配置文件（首次使用前编辑）
├── backup_videos_v3.sh                   # 视频备份主脚本
├── backup_photos_v3.sh                   # 照片备份主脚本
├── backup_safe.sh                        # 简易备份（v1，只复制不去重）
├── iphone_backup_monitor.sh              # 设备监听守护进程
├── rebuild_hash_index.sh                 # 哈希索引重建工具
├── install.sh                            # 一键安装（注册 launchd）
├── uninstall.sh                          # 卸载 launchd
├── com.user.iphone-backup-monitor.plist  # launchd 配置（监听器）
├── com.user.iphone-video-backup.plist    # launchd 配置（旧版视频，兼容保留）
└── com.user.iphone-photo-backup.plist    # launchd 配置（旧版照片，兼容保留）
```

## 快速开始

### 第一步：安装依赖并注册自动触发

```bash
cd iphone-auto-backup
bash install.sh
```

安装脚本会自动：
- 检查并安装 `libimobiledevice`（通过 Homebrew）
- 检查并安装 `exiftool`（通过 Homebrew）
- 注册 launchd 任务，iPhone 插入 USB 时自动触发备份

### 第二步：确认配置

编辑 `config.sh`：

```bash
nano config.sh
```

确认以下路径（改为你的外置硬盘）：

```bash
BACKUP_ROOT="/Volumes/YourExternalDrive/iPhone_Videos"
PHOTO_BACKUP_ROOT="/Volumes/YourExternalDrive/iPhone_Photos"
```

### 第三步：插入 iPhone

- 插入 USB 线
- iPhone 弹出「是否信任此电脑」，点击**信任**并输入密码
- 备份自动开始，完成后收到桌面通知

## 备份结果示例

```
/Volumes/YourExternalDrive/iPhone_Videos/
└── 2026-04-07/
    ├── 001.mov
    └── 002.mov

/Volumes/YourExternalDrive/iPhone_Photos/
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

## 配置说明（config.sh）

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `BACKUP_ROOT` | 视频备份目标路径 | `/Volumes/YourExternalDrive/iPhone_Videos` |
| `PHOTO_BACKUP_ROOT` | 照片备份目标路径 | `/Volumes/YourExternalDrive/iPhone_Photos` |
| `VIDEO_EXTENSIONS` | 支持的视频格式 | `MOV MP4 M4V 3GP AVI MKV` |
| `PHOTO_EXTENSIONS` | 支持的照片格式 | `JPG JPEG HEIC PNG GIF` |
| `AUTO_REFRESH_INDEX` | 备份完成后是否自动刷新媒体索引（需同目录下有 `refresh_index.sh`） | `0`（关闭） |

## 手动运行

```bash
# 视频备份
bash backup_videos_v3.sh

# 照片备份
bash backup_photos_v3.sh
```

## 查看日志

```bash
cat /tmp/iphone_backup_monitor.status    # 监听器状态
cat /tmp/iphone_backup_stdout.log        # 视频备份日志
cat /tmp/iphone_photo_backup_stdout.log  # 照片备份日志
```

## 依赖

| 工具 | 用途 | 安装方式 |
|------|------|----------|
| `libimobiledevice` | iPhone 通信协议（afcclient / idevicepair） | `brew install libimobiledevice` |
| `exiftool` | 读取视频/照片拍摄日期 | `brew install exiftool` |

> 仅依赖 macOS 自带工具 + 以上两个 Homebrew 包，无需 macFUSE / ifuse。

## 系统要求

- macOS（Apple Silicon 优先，Intel 需修改脚本中的 `/opt/homebrew/bin` 为 `/usr/local/bin`）
- iPhone（USB 连接，需点击「信任此电脑」）
- 外置硬盘或指定备份目录

## 常见问题

**Q: 备份没有自动触发？**
A: 确认 iPhone 已点击「信任此电脑」；运行 `bash install.sh` 重新注册 launchd；检查日志 `cat /tmp/iphone_backup_monitor.status`。

**Q: 重复备份同一个视频？**
A: v3 使用内容哈希去重（首尾 512KB + 文件大小 → SHA1），同一内容不会重复备份。哈希索引位于 `~/.iphone_video_backup_v3.hashes`。

**Q: 外置硬盘没插，备份失败怎么办？**
A: 脚本会记录错误并发送桌面通知，不会崩溃。下次插上硬盘后手动运行即可：

```bash
bash backup_videos_v3.sh
bash backup_photos_v3.sh
```

**Q: 怎么卸载自动触发？**

```bash
bash uninstall.sh
```

卸载只移除 launchd 自动触发配置，脚本文件、备份数据、哈希索引均不受影响。

## 卸载

```bash
bash uninstall.sh
```

如需彻底清除所有数据：

```bash
rm -f ~/.iphone_video_backup_v3.hashes ~/.iphone_photo_backup_v3.hashes
rm -f ~/.iphone_video_backup_v3.device_seen ~/.iphone_photo_backup_v3.device_seen
rm -rf /Volumes/YourExternalDrive/iPhone_Videos /Volumes/YourExternalDrive/iPhone_Photos
```

## License

[MIT](LICENSE)

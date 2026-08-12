#!/bin/bash
# ============================================================
# iPhone 视频 & 照片备份工具 - 卸载脚本
# ============================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }

echo ""
echo "=================================================="
echo "   iPhone 视频 & 照片备份工具 - 卸载程序"
echo "=================================================="

# 卸载 monitor launchd
if [[ -f "$HOME/Library/LaunchAgents/com.user.iphone-backup-monitor.plist" ]]; then
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.user.iphone-backup-monitor.plist" 2>/dev/null || true
    launchctl unload "$HOME/Library/LaunchAgents/com.user.iphone-backup-monitor.plist" 2>/dev/null || true
    rm "$HOME/Library/LaunchAgents/com.user.iphone-backup-monitor.plist"
    info "已卸载: com.user.iphone-backup-monitor.plist"
else
    warn "未找到: com.user.iphone-backup-monitor.plist（可能未安装）"
fi

# 兼容清理旧 video launchd
if [[ -f "$HOME/Library/LaunchAgents/com.user.iphone-video-backup.plist" ]]; then
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.user.iphone-video-backup.plist" 2>/dev/null || true
    launchctl unload "$HOME/Library/LaunchAgents/com.user.iphone-video-backup.plist" 2>/dev/null || true
    rm "$HOME/Library/LaunchAgents/com.user.iphone-video-backup.plist"
    info "已卸载: com.user.iphone-video-backup.plist"
else
    warn "未找到: com.user.iphone-video-backup.plist（可能未安装）"
fi

# 兼容清理旧 photo launchd
if [[ -f "$HOME/Library/LaunchAgents/com.user.iphone-photo-backup.plist" ]]; then
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.user.iphone-photo-backup.plist" 2>/dev/null || true
    launchctl unload "$HOME/Library/LaunchAgents/com.user.iphone-photo-backup.plist" 2>/dev/null || true
    rm "$HOME/Library/LaunchAgents/com.user.iphone-photo-backup.plist"
    info "已卸载: com.user.iphone-photo-backup.plist"
else
    warn "未找到: com.user.iphone-photo-backup.plist（可能未安装）"
fi

echo ""
echo "=================================================="
echo ""
info "卸载完成！"
echo ""
echo "  launchd 自动触发：已移除"
echo "  脚本文件：不受影响（保留在 the project directory）"
  echo "  备份数据：不受影响（保留在 /Volumes/YourExternalDrive/iPhone_*/）"
echo "  哈希索引：不受影响（保留在 ~/.iphone_*_backup_v3.hashes）"
echo ""
echo "彻底清除所有数据："
echo "  rm -f ~/.iphone_video_backup_v3.hashes ~/.iphone_photo_backup_v3.hashes"
  echo "  rm -rf /Volumes/YourExternalDrive/iPhone_Videos /Volumes/YourExternalDrive/iPhone_Photos"
echo ""

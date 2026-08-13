#!/bin/bash
# ============================================================
# iPhone 视频 & 照片备份工具 - 卸载脚本
# 只移除 launchd 自动触发；不删除脚本、备份数据或哈希索引
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }

LA="$HOME/Library/LaunchAgents"
AGENTS=(
    com.user.iphone-backup-monitor
    com.user.iphone-video-backup
    com.user.iphone-photo-backup
)

echo ""
echo "=================================================="
echo "   iPhone 视频 & 照片备份工具 - 卸载程序"
echo "=================================================="
echo ""

removed=0
for name in "${AGENTS[@]}"; do
    plist="$LA/$name.plist"
    if [[ -f "$plist" ]]; then
        launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
        launchctl unload "$plist" 2>/dev/null || true
        rm -f "$plist"
        info "已卸载: $name.plist"
        removed=$((removed + 1))
    fi
done

if [[ "$removed" -eq 0 ]]; then
    warn "未找到已安装的 launchd 配置（可能尚未安装）"
fi

echo ""
echo "=================================================="
echo ""
info "卸载完成！"
echo ""
echo "  launchd 自动触发：已移除"
echo "  脚本文件：不受影响（保留在 $SCRIPT_DIR）"
echo "  备份数据：不受影响"
echo "    $BACKUP_ROOT"
echo "    $PHOTO_BACKUP_ROOT"
echo "  哈希/状态索引：不受影响（~/.iphone_*_backup_v3.*）"
echo ""
echo "彻底清除索引（不会删除已备份的文件）："
echo "  rm -f ~/.iphone_video_backup_v3.hashes ~/.iphone_photo_backup_v3.hashes"
echo "  rm -f ~/.iphone_video_backup_v3.device_seen ~/.iphone_photo_backup_v3.device_seen"
echo "  rm -f ~/.iphone_video_backup_v3.state ~/.iphone_photo_backup_v3.state"
echo ""
echo "如需删除备份文件，请自行确认路径后再删："
echo "  rm -rf \"$BACKUP_ROOT\" \"$PHOTO_BACKUP_ROOT\""
echo ""

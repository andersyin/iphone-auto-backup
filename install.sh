#!/bin/bash
# ============================================================
# iPhone 视频 & 照片备份工具 - 安装脚本
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREW="/opt/homebrew/bin/brew"
LOG_DIR="/tmp"

# ---------- 彩色输出 ----------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✗]${NC} $*"; }

# ---------- 检查 Homebrew ----------
check_homebrew() {
    echo ""
    echo "检查 Homebrew..."
    if [[ ! -f "$BREW" ]]; then
        err "未找到 Homebrew，请先安装："
        echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
    info "Homebrew 已安装 ($("$BREW" --version | head -1))"
}

# ---------- 安装依赖 ----------
check_deps() {
    echo ""
    echo "检查依赖..."

    # libimobiledevice
    if ! command -v /opt/homebrew/bin/idevice_id &>/dev/null; then
        warn "未找到 libimobiledevice，正在安装..."
        "$BREW" install libimobiledevice
    else
        info "libimobiledevice 已安装"
    fi

    # exiftool
    if ! command -v /opt/homebrew/bin/exiftool &>/dev/null; then
        warn "未找到 ExifTool，正在安装..."
        "$BREW" install exiftool
    else
        info "ExifTool 已安装"
    fi
}

# ---------- 设置脚本权限 ----------
set_perms() {
    echo ""
    echo "设置脚本权限..."
    chmod +x "$SCRIPT_DIR/backup_videos_v3.sh"
    chmod +x "$SCRIPT_DIR/backup_photos_v3.sh"
    chmod +x "$SCRIPT_DIR/iphone_backup_monitor.sh"
    info "backup_videos_v3.sh  → 可执行"
    info "backup_photos_v3.sh → 可执行"
    info "iphone_backup_monitor.sh → 可执行"
}

# ---------- 注册 launchd ----------
install_plist() {
    local plist_name="$1"
    local plist_src="$SCRIPT_DIR/$plist_name"
    local plist_dest="$HOME/Library/LaunchAgents/$plist_name"

    if [[ ! -f "$plist_src" ]]; then
        err "未找到: $plist_src"
        return 1
    fi

    mkdir -p "$HOME/Library/LaunchAgents"

    # 卸载旧版本（如果存在）
    launchctl bootout "gui/$(id -u)" "$plist_dest" 2>/dev/null || true
    launchctl unload "$plist_dest" 2>/dev/null || true

    # Replace __SCRIPT_DIR__ placeholder with actual script directory
    sed "s|__SCRIPT_DIR__|$SCRIPT_DIR|g" "$plist_src" > "$plist_dest"
    launchctl bootstrap "gui/$(id -u)" "$plist_dest" 2>/dev/null || launchctl load "$plist_dest"
    info "launchd 已加载: $plist_name"
}

# ---------- 安装 monitor plist ----------
install_launchd() {
    echo ""
    echo "注册自动触发..."
    for old in com.user.iphone-video-backup.plist com.user.iphone-photo-backup.plist; do
        local old_dest="$HOME/Library/LaunchAgents/$old"
        launchctl bootout "gui/$(id -u)" "$old_dest" 2>/dev/null || true
        launchctl unload "$old_dest" 2>/dev/null || true
        rm -f "$old_dest"
    done
    install_plist "com.user.iphone-backup-monitor.plist"
}

# ---------- 提示配置 ----------
prompt_config() {
    echo ""
    echo "=================================================="
    echo ""
    warn "重要：请确认 config.sh 中的路径配置正确："
    echo ""
    echo "    nano $SCRIPT_DIR/config.sh"
    echo ""
    echo "  当前检测到的外置磁盘："
    echo "    $(ls /Volumes/ | grep -v 'Macintosh HD' | tr '\n' ' '  || echo '（未检测到外置磁盘）')"
    echo ""
    echo "  确认以下路径存在，或自行修改："
    echo "    BACKUP_ROOT=\"/Volumes/YourExternalDrive/iPhone_Videos\""
    echo "    PHOTO_BACKUP_ROOT=\"/Volumes/YourExternalDrive/iPhone_Photos\""
    echo ""
    echo "=================================================="
    echo ""
    info "安装完成！"
    echo ""
    echo "  monitor：开机/登录后常驻监听真实 iPhone 连接"
    echo "  视频备份：接入并信任 iPhone → 自动触发（v3 内容哈希去重）"
    echo "  照片备份：接入并信任 iPhone → 自动触发（v3 内容哈希去重）"
    echo ""
    echo "手动测试："
    echo "  bash $SCRIPT_DIR/backup_videos_v3.sh"
    echo "  bash $SCRIPT_DIR/backup_photos_v3.sh"
    echo ""
    echo "日志查看："
    echo "  cat /tmp/iphone_backup_monitor.status"
    echo "  cat /tmp/iphone_backup_stdout.log"
    echo "  cat /tmp/iphone_photo_backup_stdout.log"
    echo ""
}

# ---------- 主流程 ----------
main() {
    echo ""
    echo "=================================================="
    echo "   iPhone 视频 & 照片备份工具 - 安装程序"
    echo "=================================================="

    check_homebrew
    check_deps
    set_perms
    install_launchd
    prompt_config
}

main "$@"

#!/bin/bash
# ============================================================
# iPhone 视频 & 照片备份工具 - 安装脚本
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"

# ---------- 彩色输出 ----------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✗]${NC} $*"; }

find_brew() {
    if [[ -x /opt/homebrew/bin/brew ]]; then
        BREW="/opt/homebrew/bin/brew"
    elif [[ -x /usr/local/bin/brew ]]; then
        BREW="/usr/local/bin/brew"
    elif command -v brew >/dev/null 2>&1; then
        BREW="$(command -v brew)"
    else
        BREW=""
    fi
}

# ---------- 检查配置 ----------
check_config() {
    echo ""
    echo "检查配置..."
    if config_has_placeholders; then
        err "config.sh 仍是占位路径 YourExternalDrive。"
        echo "  请先编辑后再安装："
        echo "    nano $SCRIPT_DIR/config.sh"
        echo "  将 BACKUP_ROOT / PHOTO_BACKUP_ROOT 改成你的外置磁盘路径。"
        echo "  Edit BACKUP_ROOT and PHOTO_BACKUP_ROOT before installing."
        exit 1
    fi
    info "备份路径: $BACKUP_ROOT"
    info "照片路径: $PHOTO_BACKUP_ROOT"
}

# ---------- 检查 Homebrew ----------
check_homebrew() {
    echo ""
    echo "检查 Homebrew..."
    find_brew
    if [[ -z "$BREW" ]]; then
        err "未找到 Homebrew，请先安装："
        echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
    info "Homebrew 已安装 ($("$BREW" --version | head -n 1))"
}

tool_installed() {
    local name="$1"
    [[ -x "/opt/homebrew/bin/$name" || -x "/usr/local/bin/$name" ]] || command -v "$name" >/dev/null 2>&1
}

# ---------- 安装依赖 ----------
check_deps() {
    echo ""
    echo "检查依赖..."

    if ! tool_installed idevice_id; then
        warn "未找到 libimobiledevice，正在安装..."
        "$BREW" install libimobiledevice
    else
        info "libimobiledevice 已安装"
    fi

    if ! tool_installed exiftool; then
        warn "未找到 ExifTool，正在安装..."
        "$BREW" install exiftool
    else
        info "ExifTool 已安装"
    fi

    local prefix
    prefix="$("$BREW" --prefix)"
    if [[ ! -x "$prefix/bin/idevice_id" ]] && ! command -v idevice_id >/dev/null 2>&1; then
        err "安装后仍找不到 idevice_id（$prefix/bin/idevice_id）"
        exit 1
    fi
    if [[ ! -x "$prefix/bin/exiftool" ]] && ! command -v exiftool >/dev/null 2>&1; then
        err "安装后仍找不到 exiftool（$prefix/bin/exiftool）"
        exit 1
    fi
}

# ---------- 设置脚本权限 ----------
set_perms() {
    echo ""
    echo "设置脚本权限..."
    local f
    for f in backup_videos_v3.sh backup_photos_v3.sh iphone_backup_monitor.sh \
             install.sh uninstall.sh rebuild_hash_index.sh backup_safe.sh; do
        chmod +x "$SCRIPT_DIR/$f"
    done
    info "脚本已设为可执行"
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
    local old old_dest
    for old in com.user.iphone-video-backup.plist com.user.iphone-photo-backup.plist; do
        old_dest="$HOME/Library/LaunchAgents/$old"
        launchctl bootout "gui/$(id -u)" "$old_dest" 2>/dev/null || true
        launchctl unload "$old_dest" 2>/dev/null || true
        rm -f "$old_dest"
    done
    install_plist "com.user.iphone-backup-monitor.plist"
}

list_external_volumes() {
    local vol base found=0
    for vol in /Volumes/*; do
        [[ -e "$vol" ]] || continue
        base="$(basename "$vol")"
        [[ "$base" == "Macintosh HD" ]] && continue
        printf '%s ' "$base"
        found=1
    done
    if [[ "$found" -eq 0 ]]; then
        printf '%s' "（未检测到外置磁盘）"
    fi
}

# ---------- 提示配置 ----------
prompt_config() {
    echo ""
    echo "=================================================="
    echo ""
    info "安装完成！"
    echo ""
    echo "  当前备份路径："
    echo "    BACKUP_ROOT=$BACKUP_ROOT"
    echo "    PHOTO_BACKUP_ROOT=$PHOTO_BACKUP_ROOT"
    echo ""
    echo "  当前检测到的外置磁盘："
    echo "    $(list_external_volumes)"
    echo ""
    echo "  monitor：开机/登录后常驻监听真实 iPhone 连接"
    echo "  视频备份：接入并信任 iPhone → 自动触发（v3 内容哈希去重）"
    echo "  照片备份：接入并信任 iPhone → 自动触发（v3 内容哈希去重）"
    echo ""
    echo "首次使用："
    echo "  1. 插入 iPhone，解锁，点击「信任此电脑」"
    echo "  2. 确认外置磁盘已挂载"
    echo "  3. 查看状态: cat /tmp/iphone_backup_monitor.status"
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
    echo "卸载: bash $SCRIPT_DIR/uninstall.sh"
    echo ""
}

# ---------- 主流程 ----------
main() {
    echo ""
    echo "=================================================="
    echo "   iPhone 视频 & 照片备份工具 - 安装程序"
    echo "=================================================="

    check_config
    check_homebrew
    check_deps
    set_perms
    install_launchd
    prompt_config
}

main "$@"

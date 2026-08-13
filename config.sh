#!/bin/bash
# shellcheck disable=SC2034
# ============================================================
# iPhone 视频 & 照片备份工具 - 配置文件
# 路径/扩展名变量由其他脚本通过 source 引用；文件末尾的函数请保留
# ============================================================

# 视频备份根目录
# 修改为你的外置硬盘路径（安装前必须改掉 YourExternalDrive 占位名）
BACKUP_ROOT="/Volumes/YourExternalDrive/iPhone_Videos"

# 照片备份根目录
PHOTO_BACKUP_ROOT="/Volumes/YourExternalDrive/iPhone_Photos"

# 支持备份的视频格式（空格分隔）
VIDEO_EXTENSIONS="MOV MP4 M4V 3GP AVI MKV"

# 支持备份的照片格式（空格分隔）
PHOTO_EXTENSIONS="JPG JPEG HEIC PNG GIF"

# 1 = iPhone 视频/照片备份完成后,自动跑媒体索引刷新（需要同目录下有 refresh_index.sh）
# 0 = 禁用（默认）
: "${AUTO_REFRESH_INDEX:=0}"

# ── Tool paths ──
# Apple Silicon Homebrew: /opt/homebrew/bin | Intel: /usr/local/bin
# Leave empty to auto-detect; override if you install the tools elsewhere.
: "${AFCCLIENT:=}"
: "${IDEVICEPAIR:=}"
: "${IDEVICE_ID:=}"
: "${EXIFTOOL:=}"

# ── Internal helpers (keep these when editing paths above) ──

_iphone_resolve_tool() {
    local name="$1"
    local current="${2:-}"
    if [[ -n "$current" && -x "$current" ]]; then
        printf '%s\n' "$current"
        return 0
    fi
    if [[ -x "/opt/homebrew/bin/$name" ]]; then
        printf '%s\n' "/opt/homebrew/bin/$name"
        return 0
    fi
    if [[ -x "/usr/local/bin/$name" ]]; then
        printf '%s\n' "/usr/local/bin/$name"
        return 0
    fi
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return 0
    fi
    # Predictable default so error messages stay useful before brew install
    printf '%s\n' "/opt/homebrew/bin/$name"
}

AFCCLIENT="$(_iphone_resolve_tool afcclient "${AFCCLIENT:-}")"
IDEVICEPAIR="$(_iphone_resolve_tool idevicepair "${IDEVICEPAIR:-}")"
IDEVICE_ID="$(_iphone_resolve_tool idevice_id "${IDEVICE_ID:-}")"
EXIFTOOL="$(_iphone_resolve_tool exiftool "${EXIFTOOL:-}")"

config_has_placeholders() {
    [[ "$BACKUP_ROOT" == *YourExternalDrive* || "$PHOTO_BACKUP_ROOT" == *YourExternalDrive* ]]
}

# Print the volume/parent that must exist, then return 0/1.
backup_root_volume() {
    local root="$1"
    if [[ "$root" == /Volumes/* ]]; then
        local name="${root#/Volumes/}"
        name="${name%%/*}"
        printf '%s\n' "/Volumes/$name"
        return 0
    fi
    printf '%s\n' "$(dirname "$root")"
}

# For /Volumes/Disk/..., require that volume to be mounted so we never mkdir a
# fake disk under /Volumes. Other paths are created with mkdir -p.
# On failure, stdout is the missing path.
ensure_backup_root() {
    local root="$1"
    local vol
    vol="$(backup_root_volume "$root")"
    if [[ "$root" == /Volumes/* && ! -d "$vol" ]]; then
        printf '%s\n' "$vol"
        return 1
    fi
    if ! mkdir -p "$root"; then
        printf '%s\n' "$root"
        return 1
    fi
    return 0
}

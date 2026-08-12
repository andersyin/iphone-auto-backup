#!/bin/bash
# ============================================================
# iPhone 视频 & 照片备份工具 - 配置文件
# ============================================================

# 视频备份根目录
# 修改为你的外置硬盘路径
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

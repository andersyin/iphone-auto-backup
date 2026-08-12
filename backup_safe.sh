#!/bin/bash
# iPhone 安全备份 v1 — 只复制，不删除，不清理

AFCCLIENT="/opt/homebrew/bin/afcclient"
IDEVICEPAIR="/opt/homebrew/bin/idevicepair"
BACKUP_ROOT="/Volumes/YourExternalDrive/iPhone_Videos"
PHOTO_BACKUP_ROOT="/Volumes/YourExternalDrive/iPhone_Photos"
TMP_DIR="/tmp/iphone_safe_backup_tmp"

LOCKFILE="/tmp/iphone_safe_backup.lock"
if [[ -f "$LOCKFILE" ]]; then echo "[INFO] 已在运行，退出"; exit 0; fi
trap 'rm -f "$LOCKFILE"' EXIT
touch "$LOCKFILE"

caffeinate -dims -t 0 &
CAFFPID=$!
trap 'kill $CAFFPID 2>/dev/null; rm -f "$LOCKFILE"' EXIT

# iPhone 检查
PAIR_OK=$("$IDEVICEPAIR" pair 2>&1 | grep -ciE "success|paired|already" || true)
if [[ "$PAIR_OK" -eq 0 ]]; then
    echo "[ERR] iPhone 未连接或未授权"
    exit 0
fi
echo "[OK] iPhone 已连接"

mkdir -p "$TMP_DIR" "$BACKUP_ROOT" "$PHOTO_BACKUP_ROOT"

echo "扫描 iPhone..."
ALL_DIRS=$("$AFCCLIENT" list /DCIM 2>/dev/null | grep -E '^[0-9]+APPLE$' || true)

# 收集未备份文件
TODO_VIDEO=""
TODO_PHOTO=""
while IFS= read -r D; do
    [[ -z "$D" ]] && continue
    FILES=$("$AFCCLIENT" list "/DCIM/$D" 2>/dev/null || true)
    while IFS= read -r F; do
        [[ -z "$F" ]] && continue
        EXT=$(echo "${F##*.}" | tr '[:lower:]' '[:upper:]')
        # 只处理未备份的（检查目标文件不存在）
        case "$EXT" in
            MOV|MP4|M4V|3GP)
                [[ ! -f "$BACKUP_ROOT/$F" ]] && TODO_VIDEO="$TODO_VIDEO$F|$D"$'\n'
                ;;
            JPG|JPEG|HEIC|PNG|GIF)
                [[ ! -f "$PHOTO_BACKUP_ROOT/$F" ]] && TODO_PHOTO="$TODO_PHOTO$F|$D"$'\n'
                ;;
        esac
    done <<< "$FILES"
done <<< "$ALL_DIRS"

# 计数
COUNT_V=$(echo "$TODO_VIDEO" | grep -c '|' || true)
COUNT_P=$(echo "$TODO_PHOTO" | grep -c '|' || true)
echo "待备份: 视频 $COUNT_V / 照片 $COUNT_P"

# 传输函数：只 cp 到目标目录，绝不覆盖
backup_files() {
    local LIST="$1" DST="$2" TYPE="$3"
    local COPIED=0 SKIPPED=0 FAILED=0 IDX=0 TOTAL=0
    TOTAL=$(echo "$LIST" | grep -c '|' || true)
    [[ "$TOTAL" -eq 0 ]] && { echo "$TYPE: 无需备份"; return; }

    while IFS= read -r E; do
        [[ -z "$E" ]] && continue
        ((IDX++))
        FNAME="${E%|*}"; DIR="${E#*|}"
        printf "\r  %3d%% | %d/%d  %s" "$((IDX*100/TOTAL))" "$IDX" "$TOTAL" "$FNAME"

        # 安全检查：目标已存在则跳过
        [[ -f "$DST/$FNAME" ]] && { ((SKIPPED++)); continue; }

        # 下载
        "$AFCCLIENT" get "/DCIM/$DIR/$FNAME" "$TMP_DIR/$FNAME" 2>/dev/null || { ((FAILED++)); continue; }

        # 复制（cp 绝不覆盖已有文件）
        if [[ ! -f "$DST/$FNAME" ]] && cp "$TMP_DIR/$FNAME" "$DST/$FNAME" 2>/dev/null; then
            rm -f "$TMP_DIR/$FNAME"
            ((COPIED++))
        else
            rm -f "$TMP_DIR/$FNAME"
            ((FAILED++))
        fi
    done <<< "$LIST"
    echo ""
    echo "$TYPE: 新增 $COPIED / 跳过 $SKIPPED / 失败 $FAILED"
}

echo "=== 视频 ==="
backup_files "$TODO_VIDEO" "$BACKUP_ROOT" "视频"
echo "=== 照片 ==="
backup_files "$TODO_PHOTO" "$PHOTO_BACKUP_ROOT" "照片"

rm -rf "$TMP_DIR" 2>/dev/null
echo "=== 完成 ==="
echo "视频目录: $(find "$BACKUP_ROOT" -type f 2>/dev/null | wc -l) 文件"
echo "照片目录: $(find "$PHOTO_BACKUP_ROOT" -type f 2>/dev/null | wc -l) 文件"
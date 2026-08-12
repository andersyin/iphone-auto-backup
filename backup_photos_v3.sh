#!/bin/bash
#
# iPhone 照片备份脚本 v3.3
# 质量优先 + 内容哈希去重 + 目录清理 + 防睡眠 + 详细报告
#
# v3.3 修复：
#   - 清理过期锁后重新获取锁必须检查结果，避免并发进程接管时覆盖 PID
#   - 临时文件路径仅接受纯文件名，避免设备侧异常文件名逃逸 TMP_DIR
#
# v3.2 修复：
#   - 移除 set -o pipefail（进度条 printf 会因 SIGPIPE 导致脚本异常退出）
#   - IFS 分割 bug：DCIM 扫描 for→while read，安全处理含空格/Unicode 路径
#   - 并发锁 TOCTOU：PID 文件检查改为 mkdir 原子锁（macOS/Linux 通用）
#   - cleanup_target_dirs：for→while read 消除 IFS 问题
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

AFCCLIENT="/opt/homebrew/bin/afcclient"
IDEVICEPAIR="/opt/homebrew/bin/idevicepair"
EXIFTOOL="/opt/homebrew/bin/exiftool"

# ---------- 路径 ----------
STATE_FILE="$HOME/.iphone_photo_backup_v3.state"
HASH_INDEX="$HOME/.iphone_photo_backup_v3.hashes"
DEVICE_SEEN="$HOME/.iphone_photo_backup_v3.device_seen"
TMP_DIR="/tmp/iphone_photo_backup_v3_tmp"

# ---------- 锁（mkdir 原子锁，macOS/Linux 通用，消除 TOCTOU 竞态）----------
LOCKDIR="/tmp/iphone_photo_backup_v3.lockdir"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
    _lock_pid=$(cat "$LOCKDIR/pid" 2>/dev/null || echo "")
    if [[ -n "$_lock_pid" ]] && kill -0 "$_lock_pid" 2>/dev/null; then
        echo "[$(date '+%H:%M:%S')] [INFO] 相册备份已在运行 (PID $_lock_pid)，退出"
        exit 0
    fi
    # 进程已死，清理过期锁目录
    rm -rf "$LOCKDIR"
    if ! mkdir "$LOCKDIR" 2>/dev/null; then
        echo "[$(date '+%H:%M:%S')] [INFO] 相册备份锁已被其他进程接管，退出"
        exit 0
    fi
fi
echo $$ > "$LOCKDIR/pid"
trap 'restore_sleep; rm -rf "$LOCKDIR"' EXIT

# ---------- 彩色输出 ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
prok()  { echo -e "${GREEN}[OK]${NC} $*"; }
prskip(){ echo -e "${YELLOW}[SKIP]${NC} $*"; }
prerr() { echo -e "${RED}[ERR]${NC} $*"; }
prwarn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
pr()    { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $*"; }

notify() {
    local title="$1"; local msg="$2"
    command -v osascript >/dev/null 2>&1 || return 0
    local safe_title safe_msg
    safe_title=$(printf "%s" "$title" | sed 's/"/\\"/g')
    safe_msg=$(printf "%s" "$msg" | sed 's/"/\\"/g')
    osascript -e "display notification \"$safe_msg\" with title \"$safe_title\"" 2>/dev/null || true
}

other_iphone_backup_running() {
    pgrep -f "backup_videos_v3.sh" >/dev/null 2>&1
}

run_media_index_if_ready() {
    local copied="$1"; local failed="$2"
    local pending_flag="/tmp/iphone_media_index.pending"

    if [[ "${AUTO_REFRESH_INDEX:-0}" != "1" ]]; then
        save_field "phase" "done"
        return 0
    fi
    if [[ "$failed" -gt 0 ]]; then
        save_field "phase" "done_unindexed"
        notify "iPhone 媒体索引未启动" "照片备份有 $failed 个失败,先处理失败文件。"
        return 0
    fi
    if [[ "$copied" -gt 0 ]]; then
        echo "photo $(date '+%Y-%m-%dT%H:%M:%S') copied=$copied" >> "$pending_flag"
    fi
    if [[ ! -f "$pending_flag" ]]; then
        save_field "phase" "done"
        return 0
    fi
    if other_iphone_backup_running; then
        save_field "phase" "waiting_sibling_for_index"
        notify "iPhone 生产线等待" "照片已备份,等待视频备份完成后统一刷新索引。"
        return 0
    fi

    local refresh="$SCRIPT_DIR/refresh_index.sh"
    if [[ ! -x "$refresh" ]]; then
        save_field "phase" "index_missing"
        notify "iPhone 媒体索引未执行" "找不到 refresh_index.sh,备份已完成。"
        return 1
    fi

    local index_lock="/tmp/iphone_media_index.lockdir"
    if ! mkdir "$index_lock" 2>/dev/null; then
        save_field "phase" "index_already_running"
        notify "iPhone 媒体索引已在运行" "照片已备份,另一条任务正在刷新索引。"
        return 0
    fi
    trap 'restore_sleep; rm -rf "$LOCKDIR"; rm -rf /tmp/iphone_media_index.lockdir' EXIT

    save_field "phase" "indexing"
    notify "iPhone 媒体索引开始" "照片新增 $copied 个,开始自动对账并识别。"
    pr "AUTO_REFRESH_INDEX=1 → 跑媒体索引刷新"
    if "$refresh"; then
        save_field "phase" "done_indexed"
        notify "iPhone 生产线完成" "照片备份完成,媒体索引已刷新。"
        rm -f "$pending_flag"
        rm -rf "$index_lock"
        return 0
    fi

    save_field "phase" "index_failed"
    notify "iPhone 媒体索引失败" "照片备份已完成,但索引刷新失败;请查看日志后手动重跑媒体索引。"
    rm -f "$pending_flag"
    rm -rf "$index_lock"
    return 1
}

# ---------- 防睡眠 ----------
CAFFEINATE_PID=""
prevent_sleep() {
    caffeinate -dims -t 0 &
    CAFFEINATE_PID=$!
    pr "已阻止 Mac 睡眠 (PID $CAFFEINATE_PID)"
}
restore_sleep() {
    if [[ -n "$CAFFEINATE_PID" ]]; then
        kill "$CAFFEINATE_PID" 2>/dev/null || true
        CAFFEINATE_PID=""
    fi
}

# ---------- 进度条 ----------
draw_bar() {
    local cur="$1"; local tot="$2"; local name="$3"
    (( tot == 0 )) && tot=1
    local pct=$(( cur * 100 / tot ))
    local wid=24; local fill=$(( cur * wid / tot )); local empty=$(( wid - fill ))
    printf "\r  %3d%% |%${fill}s%${empty}s| %d/%d  %s" "$pct" "" "" "$cur" "$tot" "$name"
}
clear_bar() { printf "\r%68s\r" ""; }

# ---------- 状态读写 ----------
save_field() {
    local key="$1"; local val="$2"
    local tmp; tmp=$(mktemp)
    grep -v "^${key}=" "$STATE_FILE" >> "$tmp" 2>/dev/null || true
    echo "${key}=${val}" >> "$tmp"
    mv "$tmp" "$STATE_FILE"
}
write_progress_state() {
    local phase="$1" processed="$2" total="$3" current="$4" copied="$5" skipped="$6" failed="$7"
    local tmp; tmp=$(mktemp)
    {
        echo "phase=$phase"
        echo "processed=$processed"
        echo "total=$total"
        echo "current_file=$current"
        echo "copied=$copied"
        echo "skipped=$skipped"
        echo "failed=$failed"
        echo "started_at=${PROGRESS_STARTED_AT:-}"
        echo "updated_at=$(date '+%Y-%m-%dT%H:%M:%S')"
    } > "$tmp"
    mv "$tmp" "$STATE_FILE"
}
get_field() {
    local key="$1"
    grep "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d= -f2- || echo ""
}
touch_state() {
    mkdir -p "$(dirname "$STATE_FILE")"
    mkdir -p "$TMP_DIR"
    touch "$HASH_INDEX"
    touch "$DEVICE_SEEN"
    : > "$TMP_DIR/.run_done"
}

# ---------- 内容哈希 ----------
compute_hash() {
    local f="$1"
    local size; size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)
    local head tail
    head=$(head -c 524288 "$f" | shasum | cut -d' ' -f1)
    tail=$(tail -c 524288 "$f" | shasum | cut -d' ' -f1)
    echo "${size}_${head}_${tail}"
}

hash_seen() {
    local h="$1"
    grep -qx "$h" "$HASH_INDEX" 2>/dev/null
}
hash_record() {
    echo "$1" >> "$HASH_INDEX"
}

# ---------- 设备侧元数据（afcclient info: st_size + st_mtime）----------
# 输出 "size|mtime秒"；info 失败输出空并返回 1（调用方走保守路径：不预筛/不校验）。
# 注意: afcclient 的 st_mtime 是纳秒级 epoch，取前 10 位得秒。
device_info() {
    local dpath="$1"
    local out size mtns mts=""
    out=$("$AFCCLIENT" info "$dpath" 2>/dev/null) || return 1
    size=$(printf '%s' "$out" | sed -n 's/.*"st_size":[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)
    mtns=$(printf '%s' "$out" | sed -n 's/.*"st_mtime":[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)
    [[ -n "$size" ]] || return 1
    if [[ -n "$mtns" ]]; then
        if (( ${#mtns} > 10 )); then mts="${mtns:0:10}"; else mts="$mtns"; fi
    fi
    printf '%s|%s\n' "$size" "$mts"
}

device_seen() {
    grep -qxF "$1" "$DEVICE_SEEN" 2>/dev/null
}
device_record() {
    echo "$1" >> "$DEVICE_SEEN"
}

# ---------- EXIF 日期读取 ----------
# $2 = 设备侧 st_mtime（秒，可空）。
# 禁用本地 mtime 兜底：下载后 mtime = 下载时间，会把旧素材全部归到同步当日（2026-07-20 实跑教训）。
get_photo_date() {
    local fp="$1"
    local dev_mtime="${2:-}"
    local d=""

    d=$("$EXIFTOOL" -DateTimeOriginal -s3 -d "%Y-%m-%d" "$fp" 2>/dev/null | head -1)
    if [[ -n "$d" && "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "$d"; return
    fi

    d=$("$EXIFTOOL" -CreateDate -s3 -d "%Y-%m-%d" "$fp" 2>/dev/null | head -1)
    if [[ -n "$d" && "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "$d"; return
    fi

    d=$("$EXIFTOOL" -MediaCreateDate -s3 -d "%Y-%m-%d" "$fp" 2>/dev/null | head -1)
    if [[ -n "$d" && "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "$d"; return
    fi

    local bn; bn=$(basename "$fp")
    local ds
    ds=$(expr "$bn" : 'IMG_\([0-9]\{8\}\)' 2>/dev/null || true)
    if [[ -n "$ds" && ${#ds} -eq 8 ]]; then
        echo "${ds:0:4}-${ds:4:2}-${ds:6:2}"; return
    fi

    # 设备侧修改时间：截图/App 保存的无 EXIF 图片，这是最接近真实日期的来源
    if [[ -n "$dev_mtime" && "$dev_mtime" =~ ^[0-9]{9,10}$ ]]; then
        d=$(date -r "$dev_mtime" '+%Y-%m-%d' 2>/dev/null || true)
        if [[ -n "$d" && "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            echo "$d"; return
        fi
    fi

    # 全部失效 → 归到 _unknown_date，绝不冒充某个具体日期
    echo "_unknown_date"
}

# ---------- EXIF 完整时间戳 (touch -t 格式) ----------
# $2 = 设备侧 st_mtime（秒，可空），用于无 EXIF 的截图回退。
# 返回 touch -t 兼容格式: YYYYMMDDHHMM.SS；全链失效返回空。
# 2026-07-21: 归档后用此值 touch -t 设文件 mtime，使下游索引 st_mtime = 拍摄日期而非下载日期。
get_photo_timestamp() {
    local fp="$1"
    local dev_mtime="${2:-}"
    local ts=""
    ts=$("$EXIFTOOL" -DateTimeOriginal -s3 -d "%Y%m%d%H%M.%S" "$fp" 2>/dev/null | head -1)
    if [[ -n "$ts" && "$ts" =~ ^[0-9]{12}\.[0-9]{2}$ ]]; then
        echo "$ts"; return
    fi
    ts=$("$EXIFTOOL" -CreateDate -s3 -d "%Y%m%d%H%M.%S" "$fp" 2>/dev/null | head -1)
    if [[ -n "$ts" && "$ts" =~ ^[0-9]{12}\.[0-9]{2}$ ]]; then
        echo "$ts"; return
    fi
    # 无 EXIF（截图/App 存图）→ 设备侧 st_mtime（真实保存日）
    if [[ -n "$dev_mtime" && "$dev_mtime" =~ ^[0-9]{9,10}$ ]]; then
        ts=$(date -r "$dev_mtime" '+%Y%m%d%H%M.%S' 2>/dev/null || true)
        if [[ -n "$ts" ]]; then
            echo "$ts"; return
        fi
    fi
    # 全部失效 → 返回空，调用方不设 mtime（保留下载时间）
    echo ""
}

# ---------- 判断是否是照片 ----------
is_photo() {
    local ext="${1##*.}"
    ext=$(echo "$ext" | tr '[:lower:]' '[:upper:]')
    [[ " JPG JPEG HEIC PNG GIF " =~ " $ext " ]]
}

# ---------- 同步时内容分类（与 media_index_tools.py classify_content_type 对齐）----------
# 返回 "photo" / "screenshot" / "saved_image" 三类。
# 创意截图需 Eagle 策展上下文，同步时无法判定 → 归入 saved_image，后续索引层再升级。
# 规则优先级：HEIC→photo；PNG+屏幕分辨率→screenshot；PNG 非屏幕→saved_image；
#   JPG：有相机 EXIF→photo，屏幕分辨率→screenshot，相机传感器分辨率→photo，其余→saved_image；GIF→saved_image。

# 常见 iPhone/iPad/Mac 逻辑屏幕像素（竖向×横向均算）
_screen_dims_set() {
    cat <<'DIMS'
640x1136 1136x640
750x1334 1334x750
828x1792 1792x828
1080x2340 2340x1080
1125x2436 2436x1125
1170x2532 2532x1170
1179x2556 2556x1179
1206x2622 2622x1206
1242x2208 2208x1242
1242x2688 2688x1242
1284x2778 2778x1284
1290x2796 2796x1290
1320x2868 2868x1320
886x1920 1920x886
1620x2160 2160x1620
1640x2360 2360x1640
1668x2388 2388x1668
2048x2732 2732x2048
2560x1600 1600x2560
2880x1800 1800x2880
3024x1964 1964x3024
3456x2234 2234x3456
1512x982 982x1512
1728x1117 1117x1728
1440x2560 2560x1440
1440x2960 2960x1440
1440x3088 3088x1440
1440x3120 3120x1440
1536x2560 2560x1536
1600x2560 2560x1600
DIMS
}

# 常见 iPhone/相机传感器分辨率（横竖均算）
_camera_dims_set() {
    cat <<'DIMS'
4032x3024 3024x4032
4032x2268 2268x4032
3264x2448 2448x3264
3840x2160 2160x3840
4000x3000 3000x4000
4128x3096 3096x4128
4624x3472 3472x4624
5712x4284 4284x5712
1080x1920 1920x1080
720x1280 1280x720
DIMS
}

_dims_match() {
    # $1=dims "WxH", $2=set name (screen/camera)
    local dims="$1" set_name="$2"
    local pattern
    if [[ "$set_name" == "screen" ]]; then
        pattern="$(_screen_dims_set | tr '\n' ' ')"
    else
        pattern="$(_camera_dims_set | tr '\n' ' ')"
    fi
    echo " $pattern " | grep -q " $dims "
}

classify_photo_type() {
    local fp="$1"   # 已下载到本地的文件路径
    local ext="${1##*.}"
    ext=$(echo "$ext" | tr '[:lower:]' '[:upper:]')

    # HEIC = iPhone 相机原生格式（iOS 截图一律 PNG）
    if [[ " HEIC HEIF " =~ " $ext " ]]; then
        echo "photo"; return
    fi

    # GIF/WebP → 存图
    if [[ " GIF WEBP " =~ " $ext " ]]; then
        echo "saved_image"; return
    fi

    # 获取尺寸（sips 是 macOS 自带，不依赖 PIL）
    local w h dims=""
    local sips_out
    sips_out=$(sips -g pixelWidth -g pixelHeight "$fp" 2>/dev/null) || true
    w=$(echo "$sips_out" | awk '/pixelWidth/{print $2}')
    h=$(echo "$sips_out" | awk '/pixelHeight/{print $2}')
    if [[ -n "$w" && -n "$h" ]]; then
        dims="${w}x${h}"
    fi

    # PNG：屏幕分辨率 → 截图，否则 → 存图
    if [[ "$ext" == "PNG" ]]; then
        if [[ -n "$dims" ]] && _dims_match "$dims" "screen"; then
            echo "screenshot"; return
        fi
        echo "saved_image"; return
    fi

    # JPG/JPEG/TIFF：多级判定
    if [[ " JPG JPEG TIF TIFF " =~ " $ext " ]]; then
        # 屏幕分辨率 → 截图（无论有无 EXIF）
        if [[ -n "$dims" ]] && _dims_match "$dims" "screen"; then
            echo "screenshot"; return
        fi
        # 相机传感器分辨率 → 拍摄照片（EXIF 被剥离但分辨率确属相机）
        if [[ -n "$dims" ]] && _dims_match "$dims" "camera"; then
            echo "photo"; return
        fi
        # 有相机 EXIF (Make/Model) → 拍摄照片
        local make
        make=$("$EXIFTOOL" -Make -s3 "$fp" 2>/dev/null | head -1)
        if [[ -n "$make" ]]; then
            echo "photo"; return
        fi
        # 无 EXIF、非已知分辨率 → 存图
        echo "saved_image"; return
    fi

    # 兜底
    echo "saved_image"
}

tmp_path_for() {
    local fname="$1"
    local base
    base="$(basename "$fname")"
    if [[ -z "$base" || "$base" = "." || "$base" = ".." || "$base" != "$fname" ]]; then
        return 1
    fi
    # 拒绝纯空白主名（如 " .jpg"）：此类名多为传输残片，且肉眼不可见（2026-07-20 实跑教训）
    local stem="${base%.*}"
    if [[ -z "${stem//[[:space:]]/}" ]]; then
        return 1
    fi
    printf "%s/%s\n" "$TMP_DIR" "$base"
}

# ---------- 清理目标目录 ----------
cleanup_target_dirs() {
    # 清理 .DS_Store（macOS 会自动生成，导致空文件夹判断失败）
    find "$PHOTO_BACKUP_ROOT" -name ".DS_Store" -delete 2>/dev/null || true
    local removed_empty=0
    while IFS= read -r d; do
        [[ -z "$d" ]] && continue
        rmdir "$d" 2>/dev/null && removed_empty=$((removed_empty + 1)) || true
    done < <(find "$PHOTO_BACKUP_ROOT" -mindepth 1 -type d -empty 2>/dev/null || true)
    if (( removed_empty > 0 )); then
        pr "  清理: 删除了 ${removed_empty} 个空文件夹"
    fi
}

# ---------- 统计备份目录 ----------
count_backup_files() {
    find "$PHOTO_BACKUP_ROOT" -type f 2>/dev/null | wc -l | tr -d ' '
}

# ---------- 主流程 ----------
main() {
    mkdir -p "$PHOTO_BACKUP_ROOT"
    touch_state

    # ---------- iPhone 检查 ----------
    if ! "$IDEVICEPAIR" pair 2>&1 | grep -qiq "success\|paired\|already"; then
        if [[ "${IPHONE_BACKUP_QUIET_NO_DEVICE:-0}" = "1" ]]; then
            exit 0
        fi
        echo ""
        pr "==== iPhone 照片备份 v3 ===="
        prerr "iPhone 未连接或未授权，请插入 USB 并信任电脑"
        pr "  （无设备时退出，静默等待下次插入事件）"
        exit 0
    fi

    echo ""
    pr "==== iPhone 照片备份 v3 ===="
    prevent_sleep
    prok "iPhone 已连接"

    # ---------- 阶段1: 扫描 ----------
    PROGRESS_STARTED_AT=$(date '+%Y-%m-%dT%H:%M:%S')
    write_progress_state "scanning" 0 0 "" 0 0 0
    pr "正在扫描 iPhone 相册..."

    local iphone_photos=()
    local total=0

    while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            if is_photo "$f"; then
                iphone_photos+=("/DCIM/$dir/$f|$f")
                ((total++)) || true
            fi
        done < <("$AFCCLIENT" list "/DCIM/$dir" 2>/dev/null || true)
    done < <("$AFCCLIENT" list /DCIM 2>/dev/null | grep -E '^[0-9]+APPLE$' || true)

    prok "发现 ${total} 个照片"
    write_progress_state "downloading" 0 "$total" "" 0 0 0

    # 清理目标目录
    cleanup_target_dirs

    # ---------- 阶段2: 逐文件处理 ----------
    local copied=0 skipped=0 failed=0 prefilter_skipped=0
    local -a fail_names fail_reasons
    local -a new_files
    local idx=0
    for entry in "${iphone_photos[@]}"; do
        ((idx++)) || true
        local src_path fname
        IFS='|' read -r src_path fname <<< "$entry"
        draw_bar "$idx" "$total" "$fname"
        write_progress_state "downloading" "$idx" "$total" "$fname" "$copied" "$skipped" "$failed"

        # 下载到临时目录
        local tmp_path
        if ! tmp_path=$(tmp_path_for "$fname"); then
            fail_names+=("$fname")
            fail_reasons+=("文件名异常，已跳过")
            ((failed++)) || true
            clear_bar
            continue
        fi
        # 设备侧元数据（info 失败时两值为空 → 不预筛、不校验，走旧逻辑）
        local dev_size="" dev_mtime="" dinfo=""
        if dinfo=$(device_info "$src_path"); then
            dev_size="${dinfo%%|*}"
            dev_mtime="${dinfo##*|}"
        fi

        # 增量预筛：设备路径+大小与上次成功处理一致 → 不下载直接跳过（省一次全量下载）
        if [[ -n "$dev_size" ]] && device_seen "${src_path}|${dev_size}"; then
            ((skipped++)) || true
            ((prefilter_skipped++)) || true
            clear_bar
            continue
        fi

        if ! "$AFCCLIENT" get "$src_path" "$tmp_path" 2>/dev/null; then
            fail_names+=("$fname")
            fail_reasons+=("下载失败 (USB 连接中断或文件不存在)")
            ((failed++)) || true
            clear_bar
            continue
        fi

        # 完整性校验：本地大小必须等于设备侧大小（AFC 会在整 MiB 处静默截断），失败重试 1 次
        local fsize; fsize=$(stat -f%z "$tmp_path" 2>/dev/null || stat -c%s "$tmp_path" 2>/dev/null || echo 0)
        if [[ -n "$dev_size" ]] && (( fsize != dev_size )); then
            rm -f "$tmp_path"
            "$AFCCLIENT" get "$src_path" "$tmp_path" 2>/dev/null || true
            fsize=$(stat -f%z "$tmp_path" 2>/dev/null || stat -c%s "$tmp_path" 2>/dev/null || echo 0)
            if (( fsize != dev_size )); then
                fail_names+=("$fname")
                fail_reasons+=("下载不完整 (本地 ${fsize}B ≠ 设备 ${dev_size}B，重试 1 次仍失败)")
                rm -f "$tmp_path"
                ((failed++)) || true
                clear_bar
                continue
            fi
        fi

        # 内容哈希去重
        local h; h=$(compute_hash "$tmp_path")
        if hash_seen "$h"; then
            prskip "内容重复: $fname"
            rm -f "$tmp_path"
            [[ -n "$dev_size" ]] && device_record "${src_path}|${dev_size}"
            ((skipped++)) || true
            clear_bar
            continue
        fi

        # 质量检查：文件大小
        if (( fsize < 1024 )); then
            fail_names+=("$fname")
            fail_reasons+=("文件异常 (${fsize}B < 1KB，疑似损坏)")
            rm -f "$tmp_path"
            ((failed++)) || true
            clear_bar
            continue
        fi

        # 读取拍摄日期
        local photo_date; photo_date=$(get_photo_date "$tmp_path" "$dev_mtime")

        # 同步时内容分类：photo / screenshot / saved_image
        local ptype; ptype=$(classify_photo_type "$tmp_path")
        local type_subdir
        case "$ptype" in
            photo)         type_subdir="Photos" ;;
            screenshot)    type_subdir="Screenshots" ;;
            *)             type_subdir="Saved_Images" ;;
        esac

        # 归档到类型/日期 子目录
        local target_dir="$PHOTO_BACKUP_ROOT/$type_subdir/$photo_date"
        mkdir -p "$target_dir"

        # 扫最大序号而非数文件数，避免手动删文件后序号碰撞覆盖
        local max_seq=0 _f _bn _num
        while IFS= read -r _f; do
            _bn=$(basename "$_f")
            _num=$(echo "$_bn" | grep -oE '^[0-9]+' | head -1)
            _num=${_num:-0}
            (( 10#$_num > max_seq )) && max_seq=$((10#$_num)) || true
        done < <(find "$target_dir" -maxdepth 1 -type f 2>/dev/null || true)
        local seq; seq=$((max_seq + 1))
        local ext="${fname##*.}"; ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
        local new_name target_path
        printf -v new_name "%03d.%s" "$seq" "$ext"
        target_path="$target_dir/$new_name"
        # 兜底：目标文件已存在则递增（防止非标准文件名干扰）
        while [[ -e "$target_path" ]]; do
            ((seq++)) || true
            printf -v new_name "%03d.%s" "$seq" "$ext"
            target_path="$target_dir/$new_name"
        done

        if mv "$tmp_path" "$target_path" 2>/dev/null; then
            new_files+=("$type_subdir/$photo_date/$new_name")
            hash_record "$h"
            [[ -n "$dev_size" ]] && device_record "${src_path}|${dev_size}"
            ((copied++)) || true
            # 2026-07-21: 设文件 mtime = EXIF 拍摄时间，使下游索引读到拍摄日期而非下载日期
            local ts; ts=$(get_photo_timestamp "$target_path" "$dev_mtime")
            if [[ -n "$ts" ]]; then
                touch -t "$ts" "$target_path" 2>/dev/null || true
            fi
        else
            fail_names+=("$fname")
            fail_reasons+=("归档失败 (mv 权限受限，目标路径: $target_path)")
            rm -f "$tmp_path"
            ((failed++)) || true
        fi

        clear_bar
        prok "$fname → $photo_date/$new_name"
    done

    # ---------- 阶段3: 完成后清理 ----------
    write_progress_state "done" "$total" "$total" "" "$copied" "$skipped" "$failed"
    cleanup_target_dirs

    # ---------- 恢复睡眠 ----------
    restore_sleep

    # ---------- 详细报告 ----------
    local total_backup; total_backup=$(count_backup_files)

    echo ""
    echo "======================================================================"
    echo "                    iPhone 照片备份报告"
    echo "======================================================================"
    printf "%-12s %s\n" "同步文件夹:" "$PHOTO_BACKUP_ROOT"
    printf "%-12s %s\n" "  共计:" "$total_backup 个照片文件"
    printf "%-12s ${GREEN}%s${NC}\n" "  新增:" "$copied 个照片"
    printf "%-12s ${YELLOW}%s${NC}\n" "  跳过:" "$skipped 个照片（已存在/内容重复，其中 $prefilter_skipped 个设备侧未变、免下载秒过）"
    printf "%-12s ${RED}%s${NC}\n" "  失败:" "$failed 个照片"
    echo ""

    if (( copied > 0 )); then
        echo "新增文件位置:"
        for nf in "${new_files[@]}"; do
            echo "  → $PHOTO_BACKUP_ROOT/$nf"
        done
        echo ""
    fi

    if (( failed > 0 )); then
        echo "失败详情:"
        for i in "${!fail_names[@]}"; do
            echo -e "  ${RED}✗${NC} ${fail_names[$i]}"
            echo "    原因: ${fail_reasons[$i]}"
        done
        echo ""
    fi

    echo "----------------------------------------------------------------------"
    echo "改进建议:"
    if (( failed > 0 )); then
        echo "  1. 下载/归档失败 → 检查 iPhone 是否保持解锁状态，USB 线是否松动"
        echo "  2. 避免备份期间操作 iPhone（如切换相册、删除照片）"
    fi
    if (( skipped == 0 && copied == 0 && total > 0 )); then
        echo "  1. 所有照片均已备份，无需重复操作"
    fi
    if (( total == 0 )); then
        echo "  1. iPhone DCIM 中未发现照片，请确认照片存储在本地而非 iCloud"
    fi
    if (( copied > 0 )); then
        echo "  1. 定期检查 $PHOTO_BACKUP_ROOT 目录占用空间"
    fi
    echo "======================================================================"
    echo ""

    rm -rf "$TMP_DIR" 2>/dev/null || true

    notify "iPhone 照片备份完成" "新增: ${copied} | 跳过: ${skipped} | 失败: ${failed}"
    run_media_index_if_ready "$copied" "$failed"
}

main "$@"

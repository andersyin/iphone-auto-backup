#!/bin/bash
#
# iPhone backup monitor: watches libimobiledevice for a real iPhone, then runs
# video and photo backup once per connection session.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

IDEVICE_ID="/opt/homebrew/bin/idevice_id"
IDEVICEPAIR="/opt/homebrew/bin/idevicepair"
STATUS_FILE="/tmp/iphone_backup_monitor.status"
LOCKDIR="/tmp/iphone_backup_monitor.lockdir"
: "${IPHONE_MONITOR_INTERVAL:=10}"

notify() {
    local title="$1" msg="$2"
    command -v osascript >/dev/null 2>&1 || return 0
    title=$(printf "%s" "$title" | sed 's/"/\\"/g')
    msg=$(printf "%s" "$msg" | sed 's/"/\\"/g')
    osascript -e "display notification \"$msg\" with title \"$title\"" 2>/dev/null || true
}

write_status() {
    local state="$1" device="${2:-}" detail="${3:-}"
    {
        echo "state=$state"
        echo "device=$device"
        echo "detail=$detail"
        echo "updated_at=$(date '+%Y-%m-%dT%H:%M:%S')"
    } > "$STATUS_FILE"
}


devices() {
    "$IDEVICE_ID" -l 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

trusted() {
    "$IDEVICEPAIR" validate 2>&1 | grep -Eiq 'success|valid'
}

run_backups() {
    local device="$1"
    notify "iPhone 已接入" "开始自动备份视频和照片。"
    write_status "running" "$device" "video+photo backup"

    IPHONE_BACKUP_QUIET_NO_DEVICE=1 bash "$SCRIPT_DIR/backup_videos_v3.sh" &
    local video_pid=$!
    IPHONE_BACKUP_QUIET_NO_DEVICE=1 bash "$SCRIPT_DIR/backup_photos_v3.sh" &
    local photo_pid=$!

    wait "$video_pid"; local video_rc=$?
    wait "$photo_pid"; local photo_rc=$?

    if [[ "$video_rc" -eq 0 && "$photo_rc" -eq 0 ]]; then
        write_status "done" "$device" "video_rc=0 photo_rc=0"
        notify "iPhone 自动备份完成" "视频和照片任务已结束；如有新增会自动刷新媒体索引。"
        return 0
    fi

    write_status "failed" "$device" "video_rc=$video_rc photo_rc=$photo_rc"
    notify "iPhone 自动备份异常" "视频返回 $video_rc，照片返回 $photo_rc；请查看 /tmp/iphone_* 日志。"
    return 1
}

if ! mkdir "$LOCKDIR" 2>/dev/null; then
    old_pid=$(cat "$LOCKDIR/pid" 2>/dev/null || true)
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
        exit 0
    fi
    rm -rf "$LOCKDIR"
    mkdir "$LOCKDIR" 2>/dev/null || exit 0
fi
echo $$ > "$LOCKDIR/pid"
trap 'rm -rf "$LOCKDIR"' EXIT

previous_state=$(grep '^state=' "$STATUS_FILE" 2>/dev/null | cut -d= -f2- || true)
previous_device=$(grep '^device=' "$STATUS_FILE" 2>/dev/null | cut -d= -f2- || true)
last_device=""
backed_up_device=""
last_backup_ts=0
if [[ ( "$previous_state" == "watching_connected" || "$previous_state" == "done" ) && -n "$previous_device" ]]; then
    # 监听器自身重启不等于物理重插；同一主动连接只备一次，避免重复全量扫描。
    # （failed 不在此列：失败的轮次允许重启后自动重试。）
    last_device="$previous_device"
    backed_up_device="$previous_device"
fi
# 同一连接备份策略（2026-08-04 用户拍板）：
#   once   （默认）同一主动连接只自动备份一次；再备走手动触发（控制台「立即备份」
#          写 TRIGGER_FILE）或拔插重连
#   resync 旧行为——同一连接每 IPHONE_RESYNC_INTERVAL 秒自动复查新文件
: "${IPHONE_SAME_CONN:=once}"
: "${IPHONE_RESYNC_INTERVAL:=300}"
TRIGGER_FILE="/tmp/iphone_backup_manual.trigger"
trust_notice_at=0
write_status "watching" "" "interval=${IPHONE_MONITOR_INTERVAL}s same_conn=${IPHONE_SAME_CONN}"

while true; do
    current="$(devices)"
    if [[ -z "$current" ]]; then
        if [[ -n "$last_device" ]]; then
            write_status "watching" "" "device disconnected"
        fi
        rm -f "$TRIGGER_FILE"
        last_device=""
        backed_up_device=""
        last_backup_ts=0
        trust_notice_at=0
        sleep "$IPHONE_MONITOR_INTERVAL"
        continue
    fi

    last_device="$current"
    if ! trusted; then
        now=$(date +%s)
        write_status "waiting_trust" "$current" "unlock iPhone and trust this computer"
        if (( now - trust_notice_at >= 60 )); then
            notify "iPhone 等待授权" "请解锁手机并点击“信任此电脑”。"
            trust_notice_at=$now
        fi
        sleep "$IPHONE_MONITOR_INTERVAL"
        continue
    fi

    # 手动开关：控制台「立即备份」写触发文件；消费一次 = 立即跑一轮
    if [[ -f "$TRIGGER_FILE" ]]; then
        rm -f "$TRIGGER_FILE"
        backed_up_device=""
        notify "iPhone 手动备份" "已触发新一轮备份（已有文件秒过，只拷新增）。"
    fi

    now_ts=$(date +%s)
    if [[ "$current" != "$backed_up_device" ]]; then
        run_backups "$current" || true
        backed_up_device="$current"
        last_backup_ts=$(date +%s)
    elif [[ "$IPHONE_SAME_CONN" == "resync" ]] && (( now_ts - last_backup_ts >= IPHONE_RESYNC_INTERVAL )); then
        # resync 模式（旧行为）：同一连接超过 IPHONE_RESYNC_INTERVAL 秒，重新检查新文件
        # （device_seen 预筛会让已有文件秒过）
        write_status "resync_check" "$current" "checking for new files (resync interval)"
        run_backups "$current" || true
        last_backup_ts=$(date +%s)
    else
        if [[ "$IPHONE_SAME_CONN" == "resync" ]]; then
            remaining=$(( IPHONE_RESYNC_INTERVAL - (now_ts - last_backup_ts) ))
            write_status "watching_connected" "$current" "already backed up this connection; resync in ${remaining}s"
        else
            write_status "watching_connected" "$current" "already backed up this connection; manual trigger or re-plug to run again"
        fi
    fi

    sleep "$IPHONE_MONITOR_INTERVAL"
done

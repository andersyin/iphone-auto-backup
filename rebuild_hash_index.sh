#!/bin/bash
#
# 照片哈希索引一次性重建工具
#
# 用途：扫描 PHOTO_BACKUP_ROOT 下所有现有照片文件，把哈希补录进
#       ~/.iphone_photo_backup_v3.hashes，解决以下场景的重复备份问题：
#         - Screenshots/ _unknown_date/ 等由其他工具归档的照片
#         - 早期没经过 backup_photos_v3.sh 备份而手动放入的照片
#
# 运行一次即可，之后正常备份不需要再跑。
#
# 用法：bash rebuild_hash_index.sh
#        bash rebuild_hash_index.sh --dry-run   # 只统计，不写入
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"

HASH_INDEX="$HOME/.iphone_photo_backup_v3.hashes"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
pr()    { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $*"; }
prok()  { echo -e "${GREEN}[OK]${NC} $*"; }
prskip(){ echo -e "${YELLOW}[SKIP]${NC} $*"; }

compute_hash() {
    local f="$1"
    local size; size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)
    local head tail
    head=$(head -c 524288 "$f" | shasum | cut -d' ' -f1)
    tail=$(tail -c 524288 "$f" | shasum | cut -d' ' -f1)
    echo "${size}_${head}_${tail}"
}

hash_seen() { grep -qx "$1" "$HASH_INDEX" 2>/dev/null; }

main() {
    echo ""
    pr "==== 照片哈希索引重建 ===="
    if config_has_placeholders; then
        echo "config.sh 仍是占位路径 YourExternalDrive，请先修改 PHOTO_BACKUP_ROOT"
        exit 1
    fi
    if [[ ! -d "$PHOTO_BACKUP_ROOT" ]]; then
        echo "PHOTO_BACKUP_ROOT 不存在（磁盘未挂载？）: $PHOTO_BACKUP_ROOT"
        exit 1
    fi
    $DRY_RUN && pr "（DRY-RUN 模式：只统计，不写入）"
    pr "扫描目录: $PHOTO_BACKUP_ROOT"
    pr "索引文件: $HASH_INDEX"
    echo ""

    touch "$HASH_INDEX"

    local total=0 added=0 already=0 skipped=0

    # 统计总文件数（排除 .DS_Store）
    total=$(find "$PHOTO_BACKUP_ROOT" -type f ! -name ".DS_Store" | wc -l | tr -d ' ')
    pr "共发现 $total 个文件，开始处理..."
    echo ""

    local idx=0
    while IFS= read -r f; do
        ((idx++)) || true
        local bn; bn=$(basename "$f")

        # 跳过系统文件
        [[ "$bn" == .DS_Store ]] && { ((skipped++)) || true; continue; }

        # 进度（每50个打印一次）
        (( idx % 50 == 0 )) && pr "  进度: ${idx}/${total}..."

        local h; h=$(compute_hash "$f")

        if hash_seen "$h"; then
            ((already++)) || true
        else
            if ! $DRY_RUN; then
                echo "$h" >> "$HASH_INDEX"
            fi
            ((added++)) || true
            prok "补录: $f"
        fi
    done < <(find "$PHOTO_BACKUP_ROOT" -type f ! -name ".DS_Store" 2>/dev/null | sort)

    echo ""
    echo "======================================================================"
    echo "                    哈希索引重建报告"
    echo "======================================================================"
    printf "%-14s %s\n" "扫描目录:" "$PHOTO_BACKUP_ROOT"
    printf "%-14s %s\n" "索引文件:" "$HASH_INDEX"
    printf "%-14s %s\n" "扫描文件数:" "$total"
    printf "%-14s ${GREEN}%s${NC}\n" "新补录:" "$added 个"
    printf "%-14s ${YELLOW}%s${NC}\n" "已在索引:" "$already 个"
    printf "%-14s %s\n" "跳过(系统):" "$skipped 个"
    echo ""
    if $DRY_RUN; then
        echo "DRY-RUN：未写入。去掉 --dry-run 参数重新运行即可实际补录。"
    else
        echo "完成。下次插 iPhone 备份时，已有文件将被正确跳过。"
    fi
    echo "======================================================================"
    echo ""
}

main "$@"

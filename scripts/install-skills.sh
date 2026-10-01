#!/usr/bin/env bash
#
# 把仓库里的两个 Skill 安装到本机的技能目录。
#
# 用法：
#   scripts/install-skills.sh              装到 ~/.workbuddy/skills
#   SKILLS_DIR=~/.claude/skills scripts/install-skills.sh
#   scripts/install-skills.sh --link       软链接而不是复制（改仓库代码即时生效）
#   scripts/install-skills.sh --uninstall  卸载
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/skills"
DEST="${SKILLS_DIR:-$HOME/.workbuddy/skills}"

SKILLS=(mp-wechat-style mp-wechat-extract)

MODE="copy"
for arg in "$@"; do
    case "$arg" in
        --link)      MODE="link" ;;
        --uninstall) MODE="uninstall" ;;
        -h|--help)
            cat <<'USAGE'
把仓库里的两个 Skill 安装到本机的技能目录。

用法：
  scripts/install-skills.sh                     装到 ~/.workbuddy/skills
  SKILLS_DIR=~/.claude/skills scripts/install-skills.sh
                                                装到别处
  scripts/install-skills.sh --link              软链接而不是复制
                                                （改仓库代码即时生效）
  scripts/install-skills.sh --uninstall         卸载
USAGE
            exit 0 ;;
        *)           echo "未知参数: $arg" >&2; exit 2 ;;
    esac
done

if [ ! -d "$SRC" ]; then
    echo "✗ 找不到 $SRC" >&2
    exit 1
fi

if [ "$MODE" = "uninstall" ]; then
    for skill in "${SKILLS[@]}"; do
        target="$DEST/$skill"
        if [ -e "$target" ] || [ -L "$target" ]; then
            rm -rf "$target"
            echo "  已移除 $target"
        fi
    done
    echo "卸载完成。"
    exit 0
fi

mkdir -p "$DEST"

for skill in "${SKILLS[@]}"; do
    target="$DEST/$skill"
    rm -rf "$target"

    if [ "$MODE" = "link" ]; then
        ln -s "$SRC/$skill" "$target"
        echo "  软链 $target → $SRC/$skill"
    else
        # 排除各类缓存，避免把本机状态带进目标目录
        rsync -a --exclude '__pycache__' --exclude '*.pyc' --exclude '.DS_Store' \
              "$SRC/$skill/" "$target/"
        echo "  复制 $target"
    fi
done

echo
echo "安装完成，目标是 $DEST"
echo "试一下："
echo "  python3 $DEST/mp-wechat-style/scripts/mp-render.py --help"
echo "  python3 $DEST/mp-wechat-extract/scripts/extract.py --help"

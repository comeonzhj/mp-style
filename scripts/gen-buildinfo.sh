#!/usr/bin/env bash
# 生成 Sources/BuildInfo.swift —— 把版本号、构建时间、git 提交注入到二进制里。
# 该文件由构建流程生成，不纳入版本控制（见 .gitignore）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/Sources/BuildInfo.swift"

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD="$(date +%Y%m%d.%H%M)"

if git -C "$ROOT" rev-parse --short HEAD >/dev/null 2>&1; then
  GIT_HASH="$(git -C "$ROOT" rev-parse --short HEAD)"
  # 只看已跟踪文件的改动。未跟踪文件（构建产物、临时笔记）不该让发布版本号背上 -dirty，
  # 否则随手放个文件就会污染版本标识，而这个标识是给用户报问题时用的。
  if [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no | head -1)" ]; then
    GIT_HASH="${GIT_HASH}-dirty"
  fi
else
  GIT_HASH="nogit"
fi

cat > "$OUT" <<EOF
// 本文件由 scripts/gen-buildinfo.sh 自动生成，请勿手动修改。
enum BuildInfo {
    static let version = "$VERSION"
    static let build   = "$BUILD"
    static let gitHash = "$GIT_HASH"
}
EOF

echo "BuildInfo.swift -> v$VERSION build $BUILD ($GIT_HASH)"

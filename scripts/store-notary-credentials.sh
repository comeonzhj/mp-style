#!/usr/bin/env bash
# 把公证凭据存进钥匙串，之后 notarize 就直接用 profile，不再需要密码。
#
# 密码用 read -s 交互输入，不走命令行参数 —— 否则会出现在 `ps` 输出和 shell 历史里。
#
# 用法: scripts/store-notary-credentials.sh [profile 名]
#
# 两种凭据任选其一：
#   A. Apple ID + App 专用密码  在 https://account.apple.com → 登录与安全 → App 专用密码 生成
#   B. App Store Connect API Key（.p8 文件 + Key ID + Issuer ID）
#      在 App Store Connect → 用户和访问 → 集成 → App Store Connect API 生成

set -euo pipefail

PROFILE="${1:-com.comeonzhj.mpstyle}"

# 从本机 Developer ID 证书里取 Team ID，省得手输
TEAM_ID="${TEAM_ID:-$(security find-certificate -c 'Developer ID Application' -p 2>/dev/null \
  | openssl x509 -noout -subject 2>/dev/null \
  | sed -nE 's/.*\(([A-Z0-9]{10})\).*/\1/p' | head -1)}"

if [ -z "$TEAM_ID" ]; then
  echo "取不到 Team ID，请显式指定：TEAM_ID=XXXXXXXXXX $0 $PROFILE" >&2
  exit 1
fi

echo "公证凭据类型："
echo "  1) Apple ID + App 专用密码"
echo "  2) App Store Connect API Key (.p8)"
read -rp "选择 [1/2]: " CHOICE

case "${CHOICE:-1}" in
  2)
    read -rp "Key 文件路径 (.p8): " KEY_PATH
    read -rp "Key ID: " KEY_ID
    read -rp "Issuer ID: " ISSUER_ID
    xcrun notarytool store-credentials "$PROFILE" \
      --key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$ISSUER_ID"
    ;;
  *)
    read -rp "Apple ID (邮箱): " APPLE_ID
    read -rsp "App 专用密码: " APP_PASSWORD
    echo
    xcrun notarytool store-credentials "$PROFILE" \
      --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD"
    unset APP_PASSWORD
    ;;
esac

echo
echo "✓ 凭据已存入钥匙串 profile: $PROFILE"
echo "  Team ID: $TEAM_ID"
echo
echo "验证："
xcrun notarytool history --keychain-profile "$PROFILE" | head -5

#!/bin/bash
# ============================================================================
#  公证 + 装订（Developer ID 分发路线）
#
#    ./notarize.sh
#
#  前置：
#    1. release.conf 里填好 APP_NAME / BUNDLE_ID / SIGN_IDENTITY / TEAM_ID / NOTARY_PROFILE
#    2. 已用下面命令把公证凭据存进钥匙串（只需一次）：
#
#       xcrun notarytool store-credentials "AC_PASS" \
#         --apple-id "you@example.com" \
#         --team-id "TEAMID" \
#         --password "abcd-efgh-ijkl-mnop"      # App 专用密码
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

APP_NAME="Pointofix"
NOTARY_PROFILE=""
[ -f "$ROOT/release.conf" ] && . "$ROOT/release.conf"

APP="$ROOT/build/$APP_NAME.app"
ZIP="$ROOT/build/$APP_NAME-notarize.zip"

if [ -z "$NOTARY_PROFILE" ]; then
  echo "!! release.conf 里 NOTARY_PROFILE 为空"; exit 3
fi
if [ ! -d "$APP" ]; then
  echo "==> 先做发布构建"; "$ROOT/build.sh" --release
fi

echo "==> 1/5 校验签名与 Hardened Runtime"
codesign --verify --deep --strict --verbose=2 "$APP"
if ! codesign -dvv "$APP" 2>&1 | grep -q "flags=.*runtime"; then
  echo "!! 未启用 Hardened Runtime —— 公证会被拒。请用 ./build.sh --release"
  exit 4
fi
if codesign -dvv "$APP" 2>&1 | grep -q "Signature=adhoc"; then
  echo "!! 仍是 ad-hoc 签名 —— 公证会被拒。请检查 release.conf 的 SIGN_IDENTITY"
  exit 4
fi

echo "==> 2/5 打包 zip（公证只接受压缩包/dmg/pkg）"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
ls -lh "$ZIP"

echo "==> 3/5 提交公证（通常几分钟）"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> 4/5 装订公证票据（离线首次启动也能通过 Gatekeeper）"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> 5/5 Gatekeeper 实测"
spctl -a -vvv -t install "$APP" && echo "  ✅ 已通过 Gatekeeper 校验"

echo
echo "==> 可分发产物: $APP"
echo "    再打个 dmg 给用户下载："
echo "      hdiutil create -volname \"$APP_NAME\" -srcfolder \"$APP\" -ov -format UDZO \"$ROOT/build/$APP_NAME.dmg\""

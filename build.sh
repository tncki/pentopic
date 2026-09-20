#!/bin/bash
# ============================================================================
#  构建脚本 —— 只需要 Command Line Tools，不需要装 Xcode
#
#    ./build.sh              开发构建（ad-hoc 签名，供本机测试）
#    ./build.sh --release    发布构建（Developer ID 签名 + Hardened Runtime）
#    ./build.sh --mas        Mac App Store 构建（沙箱）
#
#  产品名 / Bundle ID / 签名身份全部来自 release.conf（不存在则用下面的默认值）。
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CACHE="$ROOT/.cache"
BUILD="$ROOT/build"
# 注意：build/ 也要先建好 —— Info.plist 是在创建 .app 之前就写进 build/ 的，
# 否则全新 clone 后第一次构建会失败（No such file or directory）
mkdir -p "$CACHE/clang" "$CACHE/swift" "$BUILD"

# 沙箱/无 Xcode 环境下必须把模块缓存放到项目内
export CLANG_MODULE_CACHE_PATH="$CACHE/clang"
export SWIFT_MODULE_CACHE_PATH="$CACHE/swift"

# ---- 兜底默认值（仅当 app.conf 缺失时生效；正常都应来自 app.conf）----------
APP_NAME="PentoPic"
EXECUTABLE="PentoPic"
BUNDLE_ID="io.github.tncki.pentopic"
VERSION="1.0.0"
COPYRIGHT="© 2026 Zhao Bin. Free software (MIT). Inspired by Pointofix by Thomas Gottfried EDV — no affiliation with the original."
SCREEN_CAPTURE_DESC="This app freezes the screen so you can annotate on top of it. The image never leaves your Mac."
SIGN_IDENTITY=""
TEAM_ID=""
NOTARY_PROFILE=""
APPLE_ID=""

# ---- 读取配置 --------------------------------------------------------------
# app.conf     = 产品身份（会提交到仓库，CI 也读它）
# release.conf = 签名/公证机密（不提交，可选）
if [ -f "$ROOT/app.conf" ]; then
  # shellcheck disable=SC1091
  . "$ROOT/app.conf"
  echo "==> 身份配置: app.conf"
fi
if [ -f "$ROOT/release.conf" ]; then
  # shellcheck disable=SC1091
  . "$ROOT/release.conf"
  echo "==> 签名配置: release.conf"
fi

# ---- 本地开发签名身份 ------------------------------------------------------
# 自签名证书让 TCC 的「指定要求」变成 identifier + 证书指纹，**不再包含 cdhash**，
# 所以重新编译不会让屏幕录制授权失效（ad-hoc 签名会，每改一次代码就要重新授权）。
# 注意用不带 -v 的 find-identity：自签名证书通常是未受信任状态，-v 会把它过滤掉。
DEV_IDENTITY="${DEV_IDENTITY:-PentoPic Dev}"
HAS_DEV_IDENTITY=0
if security find-identity -p codesigning 2>/dev/null | grep -qF "\"$DEV_IDENTITY\""; then
  HAS_DEV_IDENTITY=1
fi

MODE="debug"
UNIVERSAL=0
for arg in "$@"; do
  case "$arg" in
    --release)   MODE="release" ;;
    --mas)       MODE="mas" ;;
    --debug)     MODE="debug" ;;
    --universal) UNIVERSAL=1 ;;
    *) echo "未知参数: $arg"; echo "用法: $0 [--release|--mas] [--universal]"; exit 2 ;;
  esac
done

APP="$BUILD/$APP_NAME.app"

# ---- 生成 Info.plist -------------------------------------------------------
PLIST="$BUILD/Info.plist"
sed -e "s|@APP_NAME@|$APP_NAME|g" \
    -e "s|@EXECUTABLE@|$EXECUTABLE|g" \
    -e "s|@BUNDLE_ID@|$BUNDLE_ID|g" \
    -e "s|@VERSION@|$VERSION|g" \
    -e "s|@COPYRIGHT@|$COPYRIGHT|g" \
    -e "s|@SCREEN_CAPTURE_DESC@|$SCREEN_CAPTURE_DESC|g" \
    "$ROOT/Resources/Info.plist.in" > "$PLIST"

if ! plutil -lint "$PLIST" >/dev/null 2>&1; then
  echo "!! 生成的 Info.plist 无效；请检查 release.conf 里是否含 & < > 等字符"
  plutil -lint "$PLIST" || true
  exit 1
fi

# ---- 编译 ------------------------------------------------------------------
SDK="$(xcrun --show-sdk-path)"
HOST_TARGET="arm64-apple-macos14.0"
[ "$(uname -m)" = "x86_64" ] && HOST_TARGET="x86_64-apple-macos14.0"

echo "==> 模式:    $MODE$( [ "$UNIVERSAL" = 1 ] && echo " (universal: arm64 + x86_64)" )"
echo "==> 产品名:  $APP_NAME  ($BUNDLE_ID)  v$VERSION"
echo "==> SDK:     $SDK"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

compile_slice() {   # $1 = target triple, $2 = 输出路径
  swiftc \
    -sdk "$SDK" \
    -target "$1" \
    -swift-version 5 \
    -O \
    -module-name "AppModule" \
    -module-cache-path "$CACHE/clang" \
    -framework AppKit -framework SwiftUI -framework ScreenCaptureKit \
    -framework Carbon -framework UniformTypeIdentifiers \
    -o "$2" \
    "$ROOT"/Sources/*.swift
}

BIN="$APP/Contents/MacOS/$EXECUTABLE"
if [ "$UNIVERSAL" = 1 ]; then
  echo "==> 编译 arm64 切片";   compile_slice "arm64-apple-macos14.0"  "$BUILD/.slice-arm64"
  echo "==> 编译 x86_64 切片";  compile_slice "x86_64-apple-macos14.0" "$BUILD/.slice-x86_64"
  echo "==> 合并为通用二进制";  lipo -create -output "$BIN" "$BUILD/.slice-arm64" "$BUILD/.slice-x86_64"
  rm -f "$BUILD/.slice-arm64" "$BUILD/.slice-x86_64"
  lipo -info "$BIN"
else
  compile_slice "$HOST_TARGET" "$BIN"
fi

cp "$PLIST" "$APP/Contents/Info.plist"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
cp "$ROOT/Resources/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/"

# 为每种界面语言建一个 .lproj 目录：只有 CFBundleLocalizations 还不够，
# AppKit 还要看包里实际存在哪些 .lproj 才会把系统面板（打开/保存对话框）切成对应语言。
for L in en zh-Hans zh-Hant de; do
  mkdir -p "$APP/Contents/Resources/$L.lproj"
  : > "$APP/Contents/Resources/$L.lproj/Localizable.strings"
done

# ---- 签名 ------------------------------------------------------------------
ENTITLEMENTS=""
[ "$MODE" = "release" ] && ENTITLEMENTS="$ROOT/Resources/entitlements-developerid.plist"
[ "$MODE" = "mas" ]     && ENTITLEMENTS="$ROOT/Resources/entitlements-mas.plist"

if [ "$MODE" = "debug" ]; then
  if [ "$HAS_DEV_IDENTITY" = 1 ]; then
    echo "==> 签名: $DEV_IDENTITY（自签名 —— 重编译不会使屏幕录制授权失效）"
    # 注意：**不要用 --deep** —— 对未受信任的自签名证书会报 errSecInternalComponent。
    # 本 bundle 里没有嵌套代码，本来也不需要 --deep。
    if ! codesign --force --sign "$DEV_IDENTITY" "$APP"; then
      echo
      echo "!! 用证书签名失败（errSecInternalComponent 通常是登录钥匙串被锁住）。"
      echo "   先解锁钥匙串再重跑效果最好："
      echo "     钥匙串访问 → 右键「登录」钥匙串 → 解锁"
      echo "   或: security unlock-keychain ~/Library/Keychains/login.keychain-db"
      echo
      echo "   现在改为 ad-hoc 签名以保证产物可用，"
      echo "   ⚠️  但这会让屏幕录制授权失效，需要重新授权一次。"
      codesign --force --sign - "$APP" || { echo "!! ad-hoc 签名也失败"; exit 4; }
    fi
    echo "    指定要求: $(codesign -d -r- "$APP" 2>&1 | grep -o 'designated.*')"
  else
    echo "==> 签名: ad-hoc（未找到证书 \"$DEV_IDENTITY\"）"
    echo "    ⚠️  重编译后系统会要求重新授权屏幕录制；详见 README「关于屏幕录制权限」"
    codesign --force --sign - "$APP" 2>/dev/null || echo "   (codesign 跳过)"
  fi
elif [ -z "$SIGN_IDENTITY" ]; then
  echo "!! $MODE 构建需要签名身份，但 release.conf 里 SIGN_IDENTITY 为空"
  echo "   先在 developer.apple.com 创建证书，再用下面命令确认名称："
  echo "     security find-identity -v -p codesigning"
  exit 3
else
  echo "==> 签名: $SIGN_IDENTITY"
  echo "    Hardened Runtime + entitlements: $ENTITLEMENTS"
  codesign --force --options runtime --timestamp \
           --entitlements "$ENTITLEMENTS" \
           --sign "$SIGN_IDENTITY" "$APP"
  echo "==> 校验签名"
  codesign --verify --deep --strict --verbose=2 "$APP"
  codesign -dvv "$APP" 2>&1 | grep -E "^Identifier|^TeamIdentifier|^Authority|flags=" || true
fi

# ---- 校验（之前签名失败是静默的，这里务必确认）--------------------------------
if ! codesign --verify --strict "$APP" 2>/dev/null; then
  echo "!! 签名校验未通过："; codesign --verify --strict --verbose=2 "$APP"; exit 5
fi

echo "==> 完成: $APP"
du -sh "$APP"

#!/bin/bash
# ============================================================================
#  离屏自检 —— 把界面与绘图结果渲染成 PNG，不需要屏幕录制权限
#
#  产物在 preview/ 目录，用于跟原版并排比对、以及给授权邮件当附件。
#
#  注意：这里会把预览程序装进一个最小的 .app 包里跑，这样 Info.plist 里的
#  产品名能生效，渲染出来的工具栏标题与真实应用完全一致（裸可执行文件
#  因为没有 Info.plist，Brand.name 会退回默认值）。
# ============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
CACHE="$ROOT/.cache"; mkdir -p "$CACHE/clang" "$CACHE/swift"
export CLANG_MODULE_CACHE_PATH="$CACHE/clang" SWIFT_MODULE_CACHE_PATH="$CACHE/swift"
SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macos14.0"; [ "$(uname -m)" = "x86_64" ] && TARGET="x86_64-apple-macos14.0"

# ---- 读产品身份（与 build.sh 一致）----------------------------------------
APP_NAME="PentoPic"; EXECUTABLE="PentoPic"; BUNDLE_ID="io.github.tncki.pentopic"
VERSION="1.0.0"; COPYRIGHT=""; SCREEN_CAPTURE_DESC=""
[ -f "$ROOT/app.conf" ] && . "$ROOT/app.conf"

BUNDLE="$ROOT/build/preview.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$ROOT/build"

echo "==> 编译预览程序（产品名: $APP_NAME）"
swiftc -sdk "$SDK" -target "$TARGET" -swift-version 5 -O -module-name POFPreview \
  -module-cache-path "$CACHE/clang" \
  -framework AppKit -framework SwiftUI -framework ScreenCaptureKit -framework Carbon -framework UniformTypeIdentifiers -framework WebKit \
  -o "$BUNDLE/Contents/MacOS/POFPreview" \
  "$ROOT"/Sources/Core.swift "$ROOT"/Sources/Prefs.swift "$ROOT"/Sources/Capture.swift \
  "$ROOT"/Sources/CanvasView.swift "$ROOT"/Sources/Windows.swift "$ROOT"/Sources/Toolbar.swift \
  "$ROOT"/Sources/Exporter.swift "$ROOT"/Sources/SettingsWindow.swift "$ROOT"/Sources/HotKey.swift \
  "$ROOT"/Sources/Decorator.swift "$ROOT"/Sources/History.swift "$ROOT"/Sources/HelpWindow.swift \
  "$ROOT"/Tools/preview/main.swift

# 只统计**参与预览构建**的源文件。SelfTest.swift 与 main.swift 不在预览的可执行文件里，
# 算进来会让"改了测试"也误报"预览图过期"。
#
# 注意：别把 case 写进 $( { … } | … ) 里 —— `;;` 在命令替换中会让 bash 解析失败，
# 而且只有在真正执行到那一行时才报错，`bash -n` 也救不了。
SRCS=$(ls "$ROOT"/Sources/*.swift | grep -v -E '/(SelfTest|main)\.swift$')
HASH=$(cat "$ROOT/app.conf" $SRCS | shasum -a 256 | awk '{print $1}')
echo "$HASH" > "$ROOT/preview/.source-hash"
# ---- 最小 Info.plist，让 Brand.name 取到真实产品名 -------------------------
cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>POFPreview</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID.preview</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>NSHumanReadableCopyright</key><string>${COPYRIGHT:-}</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key>
  <array><string>en</string><string>zh-Hans</string><string>zh-Hant</string><string>de</string></array>
</dict></plist>
PLIST

for L in en zh-Hans zh-Hant de; do
  mkdir -p "$BUNDLE/Contents/Resources/$L.lproj"
  : > "$BUNDLE/Contents/Resources/$L.lproj/Localizable.strings"
done

"$BUNDLE/Contents/MacOS/POFPreview"

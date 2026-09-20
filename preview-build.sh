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
  -framework AppKit -framework SwiftUI -framework ScreenCaptureKit -framework Carbon -framework UniformTypeIdentifiers \
  -o "$BUNDLE/Contents/MacOS/POFPreview" \
  "$ROOT"/Sources/Core.swift "$ROOT"/Sources/Prefs.swift "$ROOT"/Sources/Capture.swift \
  "$ROOT"/Sources/CanvasView.swift "$ROOT"/Sources/Windows.swift "$ROOT"/Sources/Toolbar.swift \
  "$ROOT"/Sources/Exporter.swift "$ROOT"/Sources/SettingsWindow.swift "$ROOT"/Sources/HotKey.swift \
  "$ROOT"/Tools/preview/main.swift

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
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

"$BUNDLE/Contents/MacOS/POFPreview"

#!/bin/bash
# SakuraVeil 构建脚本：swiftc 命令行编译 + 手工组装 .app（不建 Xcode 工程）。
# 用法：
#   ./build.sh              # 编译 arm64 并打包 SakuraVeil.app
#   MAKE_DMG=1 ./build.sh   # 额外生成 DMG
#   ARCHS="arm64 x86_64" ./build.sh   # 双架构（自动 lipo 合并）
set -eo pipefail

APP_NAME="SakuraVeil"
APP_VERSION="1.2.2"
APP_BUILD="122"
BUILD_DIR="build"
APP_BUNDLE="$APP_NAME.app"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICON_PNG="$BUILD_DIR/AppIcon-1024.png"
ICON_ICNS="$BUILD_DIR/AppIcon.icns"
ARCHS="${ARCHS:-arm64}"
DEPLOY_TARGET="13.0"
MAKE_DMG="${MAKE_DMG:-0}"
SDK_PATH="$(xcrun --show-sdk-path)"

generate_icon() {
  mkdir -p "$BUILD_DIR"
  cat > "$BUILD_DIR/gen_icon.swift" <<'SWIFT'
import AppKit

let output = CommandLine.arguments[1]
let size: CGFloat = 1024
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let image = NSImage(size: rect.size)

image.lockFocus()
// 深紫 → 樱粉 渐变底
let bg = NSBezierPath(roundedRect: rect.insetBy(dx: 56, dy: 56), xRadius: 220, yRadius: 220)
NSGradient(colors: [
    NSColor(calibratedRed: 0.24, green: 0.10, blue: 0.44, alpha: 1),
    NSColor(calibratedRed: 0.85, green: 0.28, blue: 0.56, alpha: 1),
])?.draw(in: bg, angle: -55)

if let symbol = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) {
    let sizeCfg = NSImage.SymbolConfiguration(pointSize: 380, weight: .heavy)
    let colorCfg = NSImage.SymbolConfiguration(paletteColors: [.white])
    var sym = symbol.withSymbolConfiguration(sizeCfg) ?? symbol
    sym = sym.withSymbolConfiguration(colorCfg) ?? sym
    sym.isTemplate = false  // 用调色板白色渲染，避免脚本上下文里 template 变黑
    sym.draw(in: NSRect(x: 272, y: 282, width: 480, height: 460))
}
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to generate icon")
}
try png.write(to: URL(fileURLWithPath: output))
SWIFT

  swift "$BUILD_DIR/gen_icon.swift" "$ICON_PNG"

  rm -rf "$ICONSET_DIR" "$ICON_ICNS"
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  cp "$ICON_PNG" "$ICONSET_DIR/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"
}

mkdir -p "$BUILD_DIR"
BINARIES=()
for arch in $ARCHS; do
  case "$arch" in
    arm64|x86_64) ;;
    *) echo "不支持的架构: $arch" >&2; exit 1 ;;
  esac
  echo "🔨 编译 $arch..."
  binary="$BUILD_DIR/$APP_NAME-$arch"
  swiftc -O -swift-version 5 \
    -target "$arch-apple-macos$DEPLOY_TARGET" \
    -sdk "$SDK_PATH" \
    -framework Cocoa -framework AVFoundation -framework Carbon \
    -framework ServiceManagement -framework IOKit \
    Sources/*.swift -o "$binary"
  BINARIES+=("$binary")
done

if [ "${#BINARIES[@]}" -gt 1 ]; then
  echo "🔗 合并架构：$ARCHS..."
  lipo -create -output "$BUILD_DIR/$APP_NAME" "${BINARIES[@]}"
  rm -f "${BINARIES[@]}"
else
  mv "${BINARIES[0]}" "$BUILD_DIR/$APP_NAME"
fi

echo "📦 组装 .app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
generate_icon
cp "$ICON_ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>

    <key>CFBundleDisplayName</key>
    <string>樱幕 SakuraVeil</string>

    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>

    <key>CFBundleIdentifier</key>
    <string>com.sakura.sakuraveil</string>

    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>

    <key>CFBundleVersion</key>
    <string>$APP_BUILD</string>

    <key>CFBundleIconFile</key>
    <string>AppIcon</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Sakura. All rights reserved.</string>

    <key>NSHighResolutionCapable</key>
    <true/>

    <key>LSMinimumSystemVersion</key>
    <string>$DEPLOY_TARGET</string>

    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>

    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "✍️  签名..."
codesign --force --deep --sign - "$APP_BUNDLE"

if [ "$MAKE_DMG" = "1" ]; then
  echo "💿 生成 DMG..."
  DMG_STAGING="$BUILD_DIR/dmg-staging"
  rm -rf "$DMG_STAGING"
  mkdir -p "$DMG_STAGING"
  cp -R "$APP_BUNDLE" "$DMG_STAGING/"
  ln -s /Applications "$DMG_STAGING/Applications"
  rm -f "$APP_NAME.dmg"
  hdiutil create \
    -volname "$APP_NAME Installer" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$APP_NAME.dmg"
fi

echo "✅ 完成：$APP_BUNDLE"
echo "   运行：open $APP_BUNDLE"

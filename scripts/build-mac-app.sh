#!/bin/sh
# Build "Photo Curator.app": the native SwiftUI app (mac/) that starts the local engine.
#   scripts/build-mac-app.sh            build into dist/Photo Curator.app
#   scripts/build-mac-app.sh --install  also copy it to ~/Applications
# The app starts the server from THIS project folder (path stored in Info.plist),
# so rebuild it if the folder moves. Nothing is downloaded.
set -e
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="dist/Photo Curator.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling the app (Xcode 27 toolchain)…"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
(cd mac && swift build -c release --product PhotoCurator >/dev/null)
cp "mac/.build/release/PhotoCurator" "$APP/Contents/MacOS/PhotoCurator"

echo "Drawing the icon…"
swift tools/mac-app/make-icon.swift "$TMP/icon.png"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

VERSION="$(git describe --tags --always 2>/dev/null || echo dev)"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Photo Curator</string>
  <key>CFBundleDisplayName</key><string>Photo Curator</string>
  <key>CFBundleIdentifier</key><string>si.beehive.photocurator</string>
  <key>CFBundleExecutable</key><string>PhotoCurator</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.8</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
  <key>PCProjectPath</key><string>$ROOT</string>
</dict></plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built: $ROOT/$APP"

if [ "$1" = "--install" ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Photo Curator.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed: $HOME/Applications/Photo Curator.app"
fi

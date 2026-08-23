#!/bin/zsh
# Builds wac.app from Sources/*.swift
set -e
cd "$(dirname "$0")"

APP=wac.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O Sources/*.swift -o "$APP/Contents/MacOS/wac"

# App icon (regenerate with: swift gen-icon.swift wac.iconset && iconutil -c icns wac.iconset -o wac.icns)
[ -f wac.icns ] && cp wac.icns "$APP/Contents/Resources/wac.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>      <string>wac</string>
    <key>CFBundleIdentifier</key>      <string>com.cuthours.wac</string>
    <key>CFBundleName</key>            <string>wac</string>
    <key>CFBundleIconFile</key>        <string>wac</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.2</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>wac records microphone audio alongside screen recordings.</string>
    <key>NSCameraUsageDescription</key>
    <string>wac shows your camera in a floating bubble during screen recordings.</string>
</dict>
</plist>
PLIST

# Prefer the stable identity (permissions survive rebuilds); fall back to ad-hoc.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "wac-dev-sign"; then
    codesign --force --sign "wac-dev-sign" "$APP"
    echo "Signed with stable identity: wac-dev-sign"
else
    codesign --force --sign - "$APP"
    echo "WARNING: ad-hoc signed — permission grants reset on every rebuild."
    echo "Run ./setup-signing.sh once to fix that."
fi

echo "Built $APP — run with: open $APP"

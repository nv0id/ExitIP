#!/bin/bash
# Builds ExitIP.app next to this script. Needs Xcode command line tools
# (xcode-select --install) and macOS 13 or later.
#   ./build.sh           build only
#   ./build.sh install   build, copy to /Applications and launch
set -euo pipefail
cd "$(dirname "$0")"

APP="ExitIP.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -parse-as-library -target "$(uname -m)-apple-macos13.0" ExitIP.swift -o "$APP/Contents/MacOS/ExitIP"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ExitIP</string>
    <key>CFBundleIdentifier</key><string>local.exitip</string>
    <key>CFBundleExecutable</key><string>ExitIP</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x ExitIP 2>/dev/null || true
    rm -rf "/Applications/$APP"
    cp -R "$APP" /Applications/
    open "/Applications/$APP"
    echo "Installed to /Applications and launched"
fi

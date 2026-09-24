#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="ClaudeSwitch"
APP_DIR="$DIR/../$APP_NAME.app"

echo "🔨 Building $APP_NAME.app..."

# 1. Clean previous build
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# 2. Generate Info.plist
cat <<EOF > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.user.claudeswitch</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

# 3. Copy Resources
if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    cp "$DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi
if [ -f "$DIR/Resources/logo.png" ]; then
    cp "$DIR/Resources/logo.png" "$APP_DIR/Contents/Resources/logo.png"
fi
if [ -f "$DIR/Resources/proxy_daemon.py" ]; then
    cp "$DIR/Resources/proxy_daemon.py" "$APP_DIR/Contents/Resources/proxy_daemon.py"
    chmod +x "$APP_DIR/Contents/Resources/proxy_daemon.py"
fi

# 4. Compile Swift sources
echo "Compiling Swift sources..."
swiftc -O -parse-as-library \
    "$DIR/Sources/ConfigManager.swift" \
    "$DIR/Sources/ProxyManager.swift" \
    "$DIR/Sources/AppState.swift" \
    "$DIR/Sources/Views/ConfigView.swift" \
    "$DIR/Sources/Views/ProxyView.swift" \
    "$DIR/Sources/Views/ProfilesView.swift" \
    "$DIR/Sources/Views/MainView.swift" \
    "$DIR/Sources/App.swift" \
    -o "$APP_DIR/Contents/MacOS/$APP_NAME"

chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

# 5. Ad-hoc codesign
codesign --force --deep --sign - "$APP_DIR"
codesign -v "$APP_DIR"

echo "✅ Successfully built: $APP_DIR"

#!/bin/zsh
# Buduje natywny bundle macOS: dist/Ksefiarz.app
# Użycie: ./Scripts/build-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."

echo "▸ Kompilacja (release)…"
swift build -c release

APP="dist/Ksefiarz.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

echo "▸ Składanie bundla…"
cp .build/release/Ksefiarz "$CONTENTS/MacOS/Ksefiarz"

# Zasoby SPM (m.in. AppIcon.png ładowany przez Bundle.module).
for bundle in .build/release/*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$CONTENTS/Resources/"
done

echo "▸ Generowanie AppIcon.icns…"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
SRC="Sources/KsefiarzApp/Resources/AppIcon.png"
for size in 16 32 128 256 512; do
  sips -z $size $size "$SRC" --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
  retina=$((size * 2))
  sips -z $retina $retina "$SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

echo "▸ Info.plist…"
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>pl</string>
    <key>CFBundleExecutable</key>
    <string>Ksefiarz</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>pl.itkrak.ksefiarz</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Ksefiarz</string>
    <key>CFBundleDisplayName</key>
    <string>Ksefiarz</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Ksefiarz steruje aplikacją Mail, aby przygotowywać lub wysyłać automatyczne przypomnienia e-mail o płatnościach.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026</string>
</dict>
</plist>
PLIST

echo "▸ Podpisywanie (ad-hoc)…"
codesign --force --deep -s - "$APP"

echo "✓ Gotowe: $APP"
echo "  Uruchom:  open $APP"
echo "  Instalacja: przeciągnij do /Applications"

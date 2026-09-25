#!/bin/zsh
# Собирает DynamicIsland.app в ./build. Нужны только Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/DynamicIsland.app
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/DynamicIsland" "$APP/Contents/MacOS/DynamicIsland"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp MediaAdapter/run.pl "$APP/Contents/Resources/run.pl"

clang -fobjc-arc -dynamiclib -O2 -arch arm64 -arch arm64e -arch x86_64 \
    -mmacosx-version-min=14.0 -framework Foundation \
    MediaAdapter/MediaAdapter.m -o "$APP/Contents/Resources/libIslandMedia.dylib"

# Постоянный сертификат (scripts/setup-signing.sh) сохраняет выданные доступы между сборками.
# Без него — ad-hoc подпись, и macOS заново спрашивает доступы после каждой сборки.
SIGN="-"
if security find-identity -v -p codesigning | grep -q "DynamicIsland Dev"; then
    SIGN="DynamicIsland Dev"
else
    echo "Подсказка: запустите scripts/setup-signing.sh, чтобы доступы не сбрасывались после сборки."
fi
codesign --force --sign "$SIGN" "$APP/Contents/Resources/libIslandMedia.dylib"
codesign --force --sign "$SIGN" "$APP"
echo "Готово: $APP"

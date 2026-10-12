#!/bin/zsh
# Перезапускает Notchly из ./build/Notchly.app.
#   scripts/restart.sh          — просто перезапустить
#   scripts/restart.sh --build  — сначала пересобрать (build.sh), потом перезапустить
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$PWD/build/Notchly.app"

if [[ "${1:-}" == "--build" || "${1:-}" == "-b" ]]; then
    ./build.sh
fi

if [[ ! -d "$APP" ]]; then
    echo "Нет $APP — запустите scripts/restart.sh --build" >&2
    exit 1
fi

# Сначала просим выйти по-хорошему, если не вышло за 3 секунды — завершаем принудительно.
if pgrep -xq Notchly; then
    osascript -e 'tell application id "'"$(defaults read "$APP/Contents/Info" CFBundleIdentifier)"'" to quit' >/dev/null 2>&1 || true
    for _ in {1..30}; do
        pgrep -xq Notchly || break
        sleep 0.1
    done
    pkill -x Notchly 2>/dev/null || true
fi
# Помощник для медиа запускается отдельным процессом perl — не оставляем его висеть.
pkill -f "Notchly.app/Contents/Resources/run.pl" 2>/dev/null || true
sleep 0.3

open "$APP"
echo "Notchly перезапущен."

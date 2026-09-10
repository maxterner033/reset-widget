#!/bin/bash
# Установка Widget Reset на чистый Mac одной командой:
#   ./scripts/install.sh
#
# Что делает:
#   1. проверяет macOS 14+ и Swift toolchain (Command Line Tools);
#   2. создаёт локальный self-signed сертификат для подписи, если его ещё нет
#      (Apple Developer Program и Xcode не нужны — см. docs/spec.md);
#   3. собирает release-бандл через scripts/build-widget.sh;
#   4. ставит "Widget Reset.app" в /Applications и запускает.
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_ID="${SIGN_ID:-Widget Reset Signing}"
APP_NAME="Widget Reset.app"
DEST="/Applications/${APP_NAME}"

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[31m!! %s\033[0m\n' "$1" >&2; exit 1; }

say "проверка системы"
os_major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$os_major" -ge 14 ] || fail "нужна macOS 14 (Sonoma) или новее, у тебя $(sw_vers -productVersion)."

if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
    fail "нет Swift toolchain. Запусти 'xcode-select --install', дождись установки Command Line Tools и повтори."
fi
echo "macOS $(sw_vers -productVersion), $(swift --version 2>&1 | head -1)"

say "сертификат для подписи (\"$SIGN_ID\")"
if security find-identity -p codesigning | grep -q "$SIGN_ID"; then
    echo "уже есть в связке ключей — пропускаю."
else
    echo "создаю новый self-signed сертификат (действует 10 лет, живёт только на этой машине)."
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    openssl req -x509 -newkey rsa:2048 -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
        -days 3650 -nodes \
        -subj "/CN=${SIGN_ID}/O=Local Dev" \
        -addext "basicConstraints=critical,CA:false" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
    openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/ident.p12" \
        -passout pass:temp -name "$SIGN_ID"
    security import "$tmp/ident.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
        -P temp -T /usr/bin/codesign
    rm -rf "$tmp"; trap - EXIT
    echo "готово. Приватный ключ остался только в login-связке, в репозиторий не попадает."
fi

say "сборка (release)"
SIGN_ID="$SIGN_ID" ./scripts/build-widget.sh release

say "установка в /Applications"
if pgrep -f "${DEST}/Contents/MacOS/WidgetReset" >/dev/null 2>&1; then
    echo "останавливаю запущенную копию"
    pkill -f "${DEST}/Contents/MacOS/WidgetReset" || true
    sleep 1
fi
rm -rf "$DEST"
ditto "build/${APP_NAME}" "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$DEST" >/dev/null 2>&1 || true
open "$DEST"

cat <<'DONE'

==> Установлено.

Дальше — один раз руками:

  1. Логин в CLI, откуда берутся лимиты (что из этого есть — то и покажет виджет):
       claude login      # лимиты Claude Code читаются из Keychain
       codex login       # лимиты Codex читаются через `codex app-server`

  2. При первом запуске macOS спросит доступ к записи Keychain
     "Claude Code-credentials" — нажми "Всегда разрешать" (Always Allow).
     Спросит один раз: подпись постоянным сертификатом переживает пересборки.

  3. Правый клик по рабочему столу -> "Изменить виджеты" -> найди "Widget Reset"
     -> перетащи плитку (есть маленькая и средняя).
     Если в галерее пусто — подожди пару секунд и открой /Applications/"Widget Reset".app
     ещё раз: chronod иногда кэширует дескриптор со второй попытки.

  4. Приложение фоновое (без иконки в Dock) и само добавляется в автозапуск.
     Настройки: открой /Applications/"Widget Reset".app ещё раз.

DONE

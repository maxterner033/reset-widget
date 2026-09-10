#!/bin/bash
# Собирает Widget Reset.app без Xcode: swift build + ручная сборка бандла
# + codesign локальным self-signed сертификатом. См. docs/spec.md, раздел
# "Обходы ограничений" п.2.
#
# Почему не ad-hoc: у ad-hoc-подписи designated requirement — это голый cdhash,
# то есть хеш самого бинарника. Keychain привязывает "Всегда разрешать" именно
# к нему, поэтому после каждой пересборки система считала приложение новым и
# снова спрашивала доступ к токену Claude. С постоянным сертификатом
# requirement выглядит как `identifier ... and certificate root = H"..."`
# и переживает пересборки.
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_ID="${SIGN_ID:-Widget Reset Signing}"
if ! security find-identity -p codesigning | grep -q "$SIGN_ID"; then
    echo "!! Нет identity \"$SIGN_ID\" — подписываю ad-hoc."
    echo "!! Keychain будет заново спрашивать доступ после каждой пересборки."
    SIGN_ID="-"
fi

APP_BUNDLE_ID="dev.maxterner.WidgetReset"
WIDGET_BUNDLE_ID="dev.maxterner.WidgetReset.Widget"
CONFIG="${1:-debug}"
BUILD_DIR=".build/${CONFIG}"
OUT_DIR="build"
OUT_APP="${OUT_DIR}/Widget Reset.app"
APPEX_DIR="${OUT_APP}/Contents/PlugIns/WidgetResetWidget.appex"

echo "==> swift build -c ${CONFIG}"
if [ "$CONFIG" = "release" ]; then
    swift build -c release
else
    swift build
fi

echo "==> assembling app bundle"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_APP/Contents/MacOS"
mkdir -p "$OUT_APP/Contents/Resources"
mkdir -p "$APPEX_DIR/Contents/MacOS"

cp "$BUILD_DIR/Host" "$OUT_APP/Contents/MacOS/WidgetReset"
cp "$BUILD_DIR/WidgetExtension" "$APPEX_DIR/Contents/MacOS/WidgetResetWidget"

cp "App/Info.plist" "$OUT_APP/Contents/Info.plist"
cp "App/Resources/AppIcon.icns" "$OUT_APP/Contents/Resources/AppIcon.icns"
cp "Widget/Info.plist" "$APPEX_DIR/Contents/Info.plist"

echo "==> codesign widget extension ($SIGN_ID, app-sandbox entitlement)"
codesign --force --deep --sign "$SIGN_ID" --entitlements "Widget/entitlements.plist" "$APPEX_DIR"

echo "==> codesign app ($SIGN_ID)"
codesign --force --sign "$SIGN_ID" "$OUT_APP"

echo "==> verify"
codesign --verify --deep --strict "$OUT_APP"
echo "OK: $OUT_APP"
echo "bundle ids: app=$APP_BUNDLE_ID widget=$WIDGET_BUNDLE_ID"

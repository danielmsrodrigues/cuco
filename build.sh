#!/bin/bash
# Compila a Cuco.app e instala-a em ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "Falta o compilador de Swift. Instala as ferramentas de linha de comandos:" >&2
    echo "    xcode-select --install" >&2
    exit 1
fi

APP="build/Cuco.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/Cuco.iconset

swift Tools/makeicon.swift build/Cuco.iconset
iconutil -c icns build/Cuco.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# O "cu-cu" da app, sintetizado (o macOS não traz nenhum).
python3 Tools/fazsom.py build/cuco.wav
afconvert -f AIFF -d BEI16 build/cuco.wav "$APP/Contents/Resources/Cuco.aiff"

cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -target "$(uname -m)-apple-macos13" \
    -o "$APP/Contents/MacOS/Cuco" Sources/*.swift \
    -framework AppKit -framework UserNotifications -framework ServiceManagement

# O macOS só entrega notificações a apps com assinatura a sério (ad-hoc não chega).
IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | awk '{print $2}' || true)
if [ -n "$IDENTITY" ]; then
    codesign --force --options runtime --sign "$IDENTITY" "$APP"
else
    echo "Aviso: sem certificado Apple Development no keychain — a app compila e"
    echo "instala, mas o macOS não lhe entrega notificações. Abre o Xcode, inicia"
    echo "sessão com o teu Apple ID em Settings -> Accounts e volta a correr isto."
    codesign --force --sign - "$APP"
fi

if [ "${1:-}" = "--install" ]; then
    pkill -x Cuco 2>/dev/null || true
    sleep 1
    mkdir -p ~/Applications
    rm -rf ~/Applications/Cuco.app
    cp -R "$APP" ~/Applications/Cuco.app
    # Também nos sons do sistema, para o Centro de Notificações lhe chegar.
    mkdir -p ~/Library/Sounds
    cp "$APP/Contents/Resources/Cuco.aiff" ~/Library/Sounds/Cuco.aiff
    open ~/Applications/Cuco.app
    echo "Instalada em ~/Applications/Cuco.app e a correr."
else
    echo "Compilada em $APP (usa ./build.sh --install para instalar)."
fi

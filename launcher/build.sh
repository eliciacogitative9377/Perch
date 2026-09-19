#!/bin/bash
# Builds Perch.app.  Command Line Tools are enough -- no Xcode needed.
#
#   ./build.sh                 release, ad-hoc signed
#   ./build.sh debug           debug build
#   PERCH_IDENTITY="Perch Dev" ./build.sh
#       sign with a named keychain identity instead of ad-hoc, so macOS keeps
#       the Accessibility grant across rebuilds (see README, "Signing").
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=${1:-release}
APP="Perch.app"
IDENTITY="${PERCH_IDENTITY:--}"

echo "==> compiling ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Perch"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Perch"
cp Info.plist "$APP/Contents/Info.plist"

if [ ! -f Perch.icns ]; then
    echo "==> rendering icon"
    swift Tools/makeicon.swift
    iconutil -c icns Perch.iconset -o Perch.icns
fi
cp Perch.icns "$APP/Contents/Resources/Perch.icns"

echo "==> signing ($([ "$IDENTITY" = "-" ] && echo ad-hoc || echo "$IDENTITY"))"
codesign --force --sign "$IDENTITY" --identifier com.sagar.perch "$APP"

echo "==> done: $(pwd)/$APP"

if [ "$IDENTITY" = "-" ]; then
    cat <<'WARN'

    NOTE  This is an ad-hoc signature, which has no stable identity, so macOS
          keys the Accessibility grant to the binary's hash -- and that hash
          changes on every build.  Expect to re-enable Perch under
          System Settings > Privacy & Security > Accessibility after each
          rebuild.  Symptom: apps still launch and raise, but nothing
          minimizes (raising needs no permission; minimizing does).

          To stop this, make a self-signed code-signing certificate once and
          build with PERCH_IDENTITY set.  See README, "Signing".
WARN
fi

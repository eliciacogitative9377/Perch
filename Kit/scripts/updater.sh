#!/bin/bash
set -eu

DMG_PATH="$HOME/Downloads/Perch.dmg"
MOUNT_PATH="/tmp/Perch"
APPLICATION_PATH="/Applications/"
LAUNCH_UID=""

STEP=""

while [[ "$#" -gt 0 ]]; do case "$1" in
  -s|--step) STEP="$2"; shift;;
  -d|--dmg) DMG_PATH="$2"; shift;;
  -a|--app) APPLICATION_PATH="$2"; shift;;
  -m|--mount) MOUNT_PATH="$2"; shift;;
  -u|--user) LAUNCH_UID="$2"; shift;;
  *) echo "Unknown parameter passed: $1"; exit 1;;
esac; shift; done

APP_DST="${APPLICATION_PATH%/}/Perch.app"
APP_SRC="${MOUNT_PATH%/}/Perch.app"

# When the script runs as root (admin auth path) but a target UID was passed,
# launch the new app back as the original user so it doesn't run as root.
launch_app() {
    if [[ -n "$LAUNCH_UID" && "$(id -u)" == "0" ]]; then
        /bin/launchctl asuser "$LAUNCH_UID" /usr/bin/sudo -u "#$LAUNCH_UID" "$@"
    else
        "$@"
    fi
}

# The copy being replaced is still running, and still owns every global hotkey
# the app registered: ⌃Space, ⌃Tab, ⌃` and the per-app keys. Launch the new one
# alongside it and none of those registrations succeed, leaving an app that
# looks fine and answers no keyboard shortcut until it is restarted by hand.
# Quit the old one first, and wait for it to actually go.
quit_running_app() {
    /usr/bin/pkill -f "$APP_DST/Contents/MacOS/Perch" >/dev/null 2>&1 || true
    local waited=0
    while /usr/bin/pgrep -f "$APP_DST/Contents/MacOS/Perch" >/dev/null 2>&1; do
        /bin/sleep 0.2
        waited=$((waited + 1))
        if [[ "$waited" -ge 25 ]]; then
            # Five seconds is long enough for a clean exit; past that, insist,
            # since leaving both alive is the failure this avoids.
            /usr/bin/pkill -9 -f "$APP_DST/Contents/MacOS/Perch" >/dev/null 2>&1 || true
            /bin/sleep 0.5
            break
        fi
    done
}

install_app() {
    local parent staging old
    parent="$(/usr/bin/dirname "$APP_DST")"
    staging="$(/usr/bin/mktemp -d "$parent/.Perch-update.XXXXXX")"

    if command -v ditto >/dev/null 2>&1; then
        ditto "$APP_SRC" "$staging/Perch.app"
    else
        cp -Rf "$APP_SRC" "$staging/Perch.app"
    fi

    old=""
    if [[ -e "$APP_DST" ]]; then
        old="$(/usr/bin/mktemp -d "$parent/.Perch-old.XXXXXX")"
        mv "$APP_DST" "$old/Perch.app"
    fi
    mv "$staging/Perch.app" "$APP_DST"

    rm -rf "$staging"
    if [[ -n "$old" ]]; then
        rm -rf "$old"
    fi
}

if [[ "$STEP" == "2" ]]; then
    quit_running_app
    install_app

    launch_app "$APP_DST/Contents/MacOS/Perch" --dmg "$DMG_PATH"

    echo "New version started"
elif [[ "$STEP" == "3" ]]; then
    /usr/bin/hdiutil detach "$MOUNT_PATH"
    /bin/rm -rf "$MOUNT_PATH"
    /bin/rm -rf "$DMG_PATH"

    echo "Done"
else
    quit_running_app
    install_app

    launch_app "$APP_DST/Contents/MacOS/Perch" --dmg-path "$DMG_PATH" --mount-path "$MOUNT_PATH"

    echo "New version started"
fi

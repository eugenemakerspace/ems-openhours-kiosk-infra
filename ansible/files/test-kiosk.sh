#!/usr/bin/env bash
#
# test-kiosk.sh — Run the kiosk manually to see crash output
#
# Usage: sudo ./test-kiosk.sh

set -euo pipefail

SERVO_BIN="/opt/servo/servo"
KIOSK_URL="https://example.com"

echo "==> Checking prerequisites..."

if [[ $EUID -ne 0 ]]; then
    echo "Run this with sudo." >&2
    exit 1
fi

if [[ ! -x "$SERVO_BIN" ]]; then
    echo "Servo binary not found at $SERVO_BIN" >&2
    exit 1
fi

if [[ ! -d /opt/servo/resources ]]; then
    echo "WARNING: /opt/servo/resources/ does not exist!"
    echo "Servo will likely crash without its resource files."
    echo ""
fi

if ! command -v cage &>/dev/null; then
    echo "cage is not installed." >&2
    exit 1
fi

# Ensure runtime dir exists
mkdir -p /run/kiosk
chown kiosk:kiosk /run/kiosk

echo "==> Starting cage + servo as 'kiosk' user..."
echo "    (All output below is from cage/servo)"
echo "    Press Ctrl+C to stop."
echo ""

sudo -u kiosk env \
    XDG_RUNTIME_DIR=/run/kiosk \
    LIBSEAT_BACKEND=seatd \
    WLR_LIBINPUT_NO_DEVICES=1 \
    WLR_NO_HARDWARE_CURSORS=1 \
    SURFMAN_FORCE_GLES=1 \
    cage -- "$SERVO_BIN" \
        --webdriver=4444 \
        --no-native-titlebar \
        "$KIOSK_URL"

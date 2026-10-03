#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this installer with sudo: sudo ./install.sh" >&2
    exit 1
fi

SOURCE_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
TARGET_USER="${ANYDESK_USER:-${SUDO_USER:-}}"

if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = root ]; then
    echo "Set ANYDESK_USER to the desktop account that runs AnyDesk." >&2
    exit 1
fi

TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
if [ -z "$TARGET_HOME" ]; then
    echo "Could not determine the home directory for $TARGET_USER." >&2
    exit 1
fi

TRACE_FILE="$TARGET_HOME/.anydesk/anydesk.trace"
LID_DEVICE=""

for name_file in /sys/class/input/input*/name; do
    [ -r "$name_file" ] || continue
    if [ "$(cat "$name_file")" = "Lid Switch" ]; then
        device_path=$(readlink -f "${name_file%/name}/device")
        LID_DEVICE=$(basename "$device_path")
        break
    fi
done

if [ -z "$LID_DEVICE" ]; then
    echo "Could not locate an ACPI lid-switch input device." >&2
    exit 1
fi

install -m 0755 "$SOURCE_DIR/anydesk-input-delay-fix" /usr/local/sbin/
install -m 0755 "$SOURCE_DIR/anydesk-input-delay-fix-watcher" /usr/local/sbin/
install -m 0644 "$SOURCE_DIR/anydesk-input-delay-fix.service" /etc/systemd/system/

config_file=$(mktemp)
trap 'rm -f "$config_file"' EXIT
{
    printf 'LID_DEVICE=%s\n' "$LID_DEVICE"
    printf 'ANYDESK_TRACE_FILE=%s\n' "$TRACE_FILE"
} > "$config_file"
install -m 0644 "$config_file" /etc/default/anydesk-input-delay-fix

systemctl daemon-reload
systemctl enable --now anydesk-input-delay-fix.service

echo "Installed for AnyDesk user: $TARGET_USER"
echo "Lid device: $LID_DEVICE"
echo "Trace file: $TRACE_FILE"

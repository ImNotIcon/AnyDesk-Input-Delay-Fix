#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this installer with sudo: sudo ./install.sh" >&2
    exit 1
fi

SOURCE_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
for command in bash awk getconf pgrep stat date find sort sed busctl systemctl install getent; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Missing required command: $command" >&2
        exit 1
    fi
done
if [ ! -w /sys/module/button/parameters/lid_init_state ]; then
    echo "A writable ACPI button lid_init_state parameter is required." >&2
    exit 1
fi
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
    # An active workaround removes the input device, but not its platform node.
    for device_path in /sys/bus/platform/devices/PNP0C0D:*; do
        [ -e "$device_path" ] || continue
        LID_DEVICE=$(basename "$device_path")
        break
    done
    if [ -z "$LID_DEVICE" ]; then
        echo "Could not locate an ACPI lid-switch device." >&2
        exit 1
    fi
fi

install -m 0755 "$SOURCE_DIR/anydesk-input-delay-fix" /usr/local/sbin/
install -m 0755 "$SOURCE_DIR/anydesk-input-delay-fix-watcher" /usr/local/sbin/
install -m 0644 "$SOURCE_DIR/anydesk-input-delay-fix.service" /etc/systemd/system/

config_file=$(mktemp)
trap 'rm -f "$config_file"' EXIT
if [ ! -e /etc/default/anydesk-input-delay-fix ]; then
    case "$TRACE_FILE" in
        *\"*|*\\*) echo "Unsupported quote or backslash in trace path" >&2; exit 1 ;;
    esac
    {
        printf 'LID_DEVICE=%s\n' "$LID_DEVICE"
        printf 'ANYDESK_TRACE_FILE="%s"\n' "$TRACE_FILE"
    } > "$config_file"
    install -m 0644 "$config_file" /etc/default/anydesk-input-delay-fix
else
    echo "Preserving existing /etc/default/anydesk-input-delay-fix configuration"
fi

systemctl daemon-reload
systemctl enable anydesk-input-delay-fix.service
systemctl restart anydesk-input-delay-fix.service

echo "Installed for AnyDesk user: $TARGET_USER"
echo "Lid device: $LID_DEVICE"
echo "Trace file: $TRACE_FILE"

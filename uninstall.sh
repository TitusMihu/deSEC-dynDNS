#!/usr/bin/env bash

set -Eeuo pipefail

CONFIG_DIR="/etc/dyndns"
CONFIG_FILE="${CONFIG_DIR}/credentials"
SCRIPT_FILE="/usr/local/sbin/update-dns-apex.sh"
SERVICE_FILE="/etc/systemd/system/dyndns.service"
TIMER_FILE="/etc/systemd/system/dyndns.timer"
DROPIN_DIR="/etc/systemd/system/dyndns.timer.d"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this uninstaller with sudo: sudo ./uninstall.sh" >&2
    exit 1
fi

echo "deSEC Dynamic DNS uninstaller"
echo

if systemctl is-active --quiet dyndns.timer 2>/dev/null; then
    echo "Stopping timer..."
    systemctl stop dyndns.timer
fi

if systemctl is-enabled --quiet dyndns.timer 2>/dev/null; then
    echo "Disabling timer..."
    systemctl disable dyndns.timer
fi

rm -f "$SCRIPT_FILE" "$SERVICE_FILE" "$TIMER_FILE"
rm -rf "$DROPIN_DIR"

systemctl daemon-reload

echo
echo "Updater, service and timer removed."

if [[ -f "$CONFIG_FILE" ]]; then
    echo
    read -r -p "Delete $CONFIG_FILE and the deSEC API token? [y/N]: " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        rm -f "$CONFIG_FILE"
        rmdir "$CONFIG_DIR" 2>/dev/null || true
        echo "Credentials removed."
    else
        echo "Credentials preserved at $CONFIG_FILE."
    fi
fi

echo
echo "Uninstallation complete."

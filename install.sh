#!/usr/bin/env bash

set -Eeuo pipefail

PREFIX="/usr/local/sbin"
CONFIG_DIR="/etc/dyndns"
CONFIG_FILE="${CONFIG_DIR}/credentials"
SERVICE_FILE="/etc/systemd/system/dyndns.service"
TIMER_FILE="/etc/systemd/system/dyndns.timer"
SCRIPT_FILE="${PREFIX}/update-dns-apex.sh"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

log() {
    printf '[INFO] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "Run this installer with sudo: sudo ./install.sh"
    fi
}

apt_install_if_missing() {
    local package="$1"
    local command="$2"

    if command -v "$command" >/dev/null 2>&1; then
        return
    fi

    if ! command -v apt-get >/dev/null 2>&1; then
        die "Missing '$command' and apt-get is unavailable. Install '$package' manually."
    fi

    log "Installing dependency: $package"
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$package"
}

validate_domain() {
    local domain="$1"
    [[ "$domain" =~ ^([A-Za-z0-9-]+\.)+[A-Za-z]{2,63}$ ]]
}

validate_interval() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

require_root

[[ -f "${SCRIPT_DIR}/bin/update-dns-apex.sh" ]] ||
    die "Missing bin/update-dns-apex.sh"

[[ -f "${SCRIPT_DIR}/systemd/dyndns.service" ]] ||
    die "Missing systemd/dyndns.service"

[[ -f "${SCRIPT_DIR}/systemd/dyndns.timer" ]] ||
    die "Missing systemd/dyndns.timer"

command -v systemctl >/dev/null 2>&1 ||
    die "systemd/systemctl is required."

apt_install_if_missing "curl" "curl"
apt_install_if_missing "dnsutils" "dig"

mkdir -p "$CONFIG_DIR"
chmod 0750 "$CONFIG_DIR"

echo
echo "deSEC Dynamic DNS installer"
echo

existing_domain=""
existing_token=""
existing_ip_url=""
existing_dns_server=""

if [[ -f "$CONFIG_FILE" ]]; then
    # Read existing configuration without printing the token.
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    existing_domain="${DNSDOMAIN:-}"
    existing_token="${TOKEN:-}"
    existing_ip_url="${IP_URL:-}"
    existing_dns_server="${DNS_SERVER:-}"

    log "Existing credentials found; they will be preserved."
fi

if [[ -n "$existing_domain" ]]; then
    read -r -p "DNS domain [$existing_domain]: " DNSDOMAIN
    DNSDOMAIN="${DNSDOMAIN:-$existing_domain}"
else
    while true; do
        read -r -p "DNS domain: " DNSDOMAIN
        validate_domain "$DNSDOMAIN" && break
        echo "Please enter a valid DNS domain, e.g. mydomain.com."
    done
fi

validate_domain "$DNSDOMAIN" ||
    die "Invalid DNS domain: $DNSDOMAIN"

if [[ -n "$existing_token" ]]; then
    read -r -p "Replace existing deSEC API token? [y/N]: " replace_token
    if [[ "$replace_token" =~ ^[Yy]$ ]]; then
        read -r -s -p "deSEC API token: " TOKEN
        echo
        [[ -n "$TOKEN" ]] || die "Token cannot be empty."
    else
        TOKEN="$existing_token"
    fi
else
    read -r -s -p "deSEC API token: " TOKEN
    echo
    [[ -n "$TOKEN" ]] || die "Token cannot be empty."
fi

read -r -p "IP detection URL [${existing_ip_url:-https://api.ipify.org}]: " IP_URL
IP_URL="${IP_URL:-${existing_ip_url:-https://api.ipify.org}}"

read -r -p "DNS server [${existing_dns_server:-ns1.desec.io}]: " DNS_SERVER
DNS_SERVER="${DNS_SERVER:-${existing_dns_server:-ns1.desec.io}}"

# Keep the timer interval in a drop-in override so package updates don't
# modify the shipped unit. On subsequent installations we update it.
read -r -p "Check interval in minutes [5]: " INTERVAL
INTERVAL="${INTERVAL:-5}"

validate_interval "$INTERVAL" ||
    die "Interval must be a positive integer number of minutes."

log "Installing updater to $SCRIPT_FILE"
install -o root -g root -m 0755 \
    "${SCRIPT_DIR}/bin/update-dns-apex.sh" \
    "$SCRIPT_FILE"

log "Writing credentials to $CONFIG_FILE"

tmp_config="$(mktemp)"
trap 'rm -f "$tmp_config"' EXIT

cat > "$tmp_config" <<EOF
DNSDOMAIN=$DNSDOMAIN
TOKEN=$TOKEN
IP_URL=$IP_URL
DNS_SERVER=$DNS_SERVER
EOF

chown root:root "$tmp_config"
chmod 0600 "$tmp_config"
install -o root -g root -m 0600 "$tmp_config" "$CONFIG_FILE"
rm -f "$tmp_config"
trap - EXIT

log "Installing systemd units"

install -o root -g root -m 0644 \
    "${SCRIPT_DIR}/systemd/dyndns.service" \
    "$SERVICE_FILE"

install -o root -g root -m 0644 \
    "${SCRIPT_DIR}/systemd/dyndns.timer" \
    "$TIMER_FILE"

mkdir -p /etc/systemd/system/dyndns.timer.d

cat > /etc/systemd/system/dyndns.timer.d/interval.conf <<EOF
[Timer]
OnUnitActiveSec=${INTERVAL}min
EOF

chmod 0644 /etc/systemd/system/dyndns.timer.d/interval.conf

systemctl daemon-reload

log "Enabling timer"
systemctl enable dyndns.timer

log "Starting timer"
systemctl restart dyndns.timer

echo
log "Running an immediate test..."
echo

if systemctl start dyndns.service; then
    echo
    log "Dynamic DNS service completed successfully."
else
    echo
    warn "The test failed. Recent service logs:"
    journalctl -u dyndns.service -n 30 --no-pager || true
    exit 1
fi

echo
echo "Installation complete."
echo
echo "Timer:"
systemctl list-timers dyndns.timer --no-pager || true
echo
echo "Useful commands:"
echo "  systemctl status dyndns.timer"
echo "  sudo systemctl start dyndns.service"
echo "  journalctl -u dyndns.service -n 50 --no-pager"
echo "  journalctl -u dyndns.service -f"

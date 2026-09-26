#!/usr/bin/env bash

set -Eeuo pipefail

CONFIG="/etc/dyndns/credentials"
API_BASE="https://desec.io/api/v1/domains"

log() {
    printf '%s [INFO] %s\n' "$(date --iso-8601=seconds)" "$*"
}

error() {
    printf '%s [ERROR] %s\n' "$(date --iso-8601=seconds)" "$*" >&2
}

on_error() {
    local line="$1"
    error "Unexpected error on line ${line}"
}
trap 'on_error "$LINENO"' ERR

if [[ ! -r "$CONFIG" ]]; then
    error "Credentials file is missing or not readable: $CONFIG"
    exit 1
fi

# The credentials file is controlled by the installer and must contain only
# shell-compatible NAME=value assignments.
# shellcheck disable=SC1090
source "$CONFIG"

if [[ -z "${DNSDOMAIN:-}" ]]; then
    error "DNSDOMAIN is not configured"
    exit 1
fi

if [[ -z "${TOKEN:-}" ]]; then
    error "TOKEN is not configured"
    exit 1
fi

IP_URL="${IP_URL:-https://api.ipify.org}"
DNS_SERVER="${DNS_SERVER:-ns1.desec.io}"

API="${API_BASE}/${DNSDOMAIN}/rrsets"

for cmd in curl dig head mktemp rm; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "Required command not found: $cmd"
        exit 1
    fi
done

# Basic domain validation. This intentionally allows normal DNS names and
# prevents shell metacharacters from reaching URLs or dig.
if [[ ! "$DNSDOMAIN" =~ ^([A-Za-z0-9-]+\.)+[A-Za-z]{2,63}$ ]]; then
    error "Invalid DNSDOMAIN: $DNSDOMAIN"
    exit 1
fi

log "Checking public IPv4 address"

IP="$(
    curl \
        --fail \
        --silent \
        --show-error \
        --connect-timeout 10 \
        --max-time 30 \
        --retry 3 \
        --retry-delay 2 \
        "$IP_URL"
)"

IP="${IP//$'\r'/}"
IP="${IP//$'\n'/}"

if [[ ! "$IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    error "Invalid IPv4 address returned by $IP_URL: $IP"
    exit 1
fi

# Validate each octet.
IFS='.' read -r -a octets <<< "$IP"
for octet in "${octets[@]}"; do
    if (( octet < 0 || octet > 255 )); then
        error "Invalid IPv4 address: $IP"
        exit 1
    fi
done

log "Current public IP: $IP"

CUR="$(
    dig \
        +short \
        +time=5 \
        +tries=2 \
        A "$DNSDOMAIN" \
        "@$DNS_SERVER" |
        head -n1
)"

CUR="${CUR//$'\r'/}"
CUR="${CUR//$'\n'/}"

if [[ -z "$CUR" ]]; then
    log "No current A record found for $DNSDOMAIN"
else
    log "Current DNS A record: $CUR"
fi

if [[ "$IP" == "$CUR" ]]; then
    log "DNS record is already up to date"
    exit 0
fi

log "Updating $DNSDOMAIN A record: ${CUR:-<none>} -> $IP"

response_file="$(mktemp)"
trap 'rm -f "$response_file"' EXIT

HTTP_STATUS="$(
    curl \
        --fail-with-body \
        --silent \
        --show-error \
        --connect-timeout 10 \
        --max-time 30 \
        --retry 3 \
        --retry-delay 2 \
        --output "$response_file" \
        --write-out '%{http_code}' \
        --request PATCH \
        --header "Authorization: Token $TOKEN" \
        --header "Content-Type: application/json" \
        --data "{\"records\":[\"$IP\"]}" \
        "${API}/@/A/"
)"

if [[ "$HTTP_STATUS" != "200" ]]; then
    error "deSEC API returned HTTP $HTTP_STATUS"
    error "API response: $(cat "$response_file")"
    exit 1
fi

log "DNS update successful: ${CUR:-<none>} -> $IP"

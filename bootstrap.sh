#!/usr/bin/env bash

# Bootstrap installer for desec-dyndns.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/TitusMihu/deSEC-dynDNS/main/bootstrap.sh | sudo bash
#
# Optional overrides:
#   curl -fsSL https://raw.githubusercontent.com/TitusMihu/deSEC-dynDNS/main/bootstrap.sh |
#     sudo env DYNDNS_REPO=https://github.com/TitusMihu/deSEC-dynDNS.git DYNDNS_REF=main bash

set -Eeuo pipefail

REPO_URL="${DYNDNS_REPO:-https://github.com/TitusMihu/deSEC-dynDNS.git}"
REPO_REF="${DYNDNS_REF:-main}"
INSTALL_DIR="${DYNDNS_INSTALL_DIR:-/opt/dyndns-desec}"

log() {
    printf '[INFO] %s\n' "$*"
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

if [[ "${EUID}" -ne 0 ]]; then
    die "Run this bootstrap installer as root, e.g. with: sudo bash"
fi

if ! command -v git >/dev/null 2>&1; then
    log "Git is not installed; installing it..."
    command -v apt-get >/dev/null 2>&1 ||
        die "Git is missing and apt-get is unavailable."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y git
fi

if [[ -e "$INSTALL_DIR/.git" ]]; then
    log "Updating existing repository at $INSTALL_DIR"
    git -C "$INSTALL_DIR" fetch --tags --prune origin

    if git -C "$INSTALL_DIR" show-ref --verify --quiet "refs/remotes/origin/$REPO_REF"; then
        git -C "$INSTALL_DIR" checkout -q "$REPO_REF"
        git -C "$INSTALL_DIR" reset --hard -q "origin/$REPO_REF"
    elif git -C "$INSTALL_DIR" rev-parse --verify --quiet "$REPO_REF^{commit}"; then
        git -C "$INSTALL_DIR" checkout -q "$REPO_REF"
        git -C "$INSTALL_DIR" reset --hard -q "$REPO_REF"
    else
        die "Cannot find repository ref: $REPO_REF"
    fi
else
    if [[ -e "$INSTALL_DIR" && -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
        die "$INSTALL_DIR exists and is not an empty Git repository."
    fi

    mkdir -p "$(dirname "$INSTALL_DIR")"
    log "Cloning $REPO_URL"
    git clone --branch "$REPO_REF" --single-branch "$REPO_URL" "$INSTALL_DIR"
fi

chmod 0755 "$INSTALL_DIR/install.sh"

log "Running installer from $INSTALL_DIR"
exec "$INSTALL_DIR/install.sh"

#!/bin/bash
# System management functions

# Update system packages
update_system() {
    log "Running apt update..."
    apt update -qq

    log "Running apt upgrade..."
    apt upgrade -y -qq

    log "System packages updated"
}

# Install dependencies
install_dependencies() {
    local packages="curl socat nginx ufw cron bc"

    log "Installing: $packages"
    apt install -y -qq $packages

    log "Dependencies installed"
}

# Configure UFW firewall
configure_firewall() {
    log "Setting default policies..."

    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1

    log "Allowing essential ports..."
    ufw allow ssh >/dev/null 2>&1
    ufw allow 80/tcp >/dev/null 2>&1
    ufw allow 443/tcp >/dev/null 2>&1

    log "Enabling UFW..."
    ufw --force enable >/dev/null 2>&1

    info "SSH (22), HTTP (80), HTTPS (443) allowed"
    log "UFW firewall configured"
}

# Check DNS resolution
check_dns() {
    local domain="$1"
    local expected_ip="$2"

    log "Resolving $domain..."

    local resolved_ip=$(dig +short "$domain" | tail -n1)

    if [ -z "$resolved_ip" ]; then
        warn "Could not resolve $domain"
        warn "Make sure A-record points to $expected_ip"
        return
    fi

    info "Domain resolves to: $resolved_ip"

    if [ "$resolved_ip" != "$expected_ip" ]; then
        warn "Domain IP ($resolved_ip) != Server IP ($expected_ip)"
        warn "SSL certificate issuance may fail!"
    else
        log "DNS configuration is correct"
    fi
}

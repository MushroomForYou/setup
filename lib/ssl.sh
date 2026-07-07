#!/bin/bash
# SSL certificate management with acme.sh

CERT_DIR="/root/cert"

# Install acme.sh
install_acme() {
    local email="$1"

    log "Checking acme.sh installation..."

    if [ ! -f ~/.acme.sh/acme.sh ]; then
        log "Downloading acme.sh..."
        curl -s https://get.acme.sh | sh >/dev/null 2>&1
    fi

    log "Upgrading acme.sh..."
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1

    info "acme.sh installed at ~/.acme.sh/"
    log "acme.sh ready"
}

# Obtain SSL certificate
obtain_ssl() {
    local domain="$1"
    local email="$2"

    log "Stopping nginx for standalone mode..."
    systemctl stop nginx >/dev/null 2>&1 || true
    systemctl stop x-ui >/dev/null 2>&1 || true

    log "Setting Let's Encrypt as default CA..."
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1

    log "Registering account with email: $email"
    ~/.acme.sh/acme.sh --register-account -m "$email" --force >/dev/null 2>&1

    log "Issuing certificate for $domain..."
    info "Using standalone mode on port 80"

    if ! ~/.acme.sh/acme.sh --issue -d "$domain" --standalone --httpport 80 --force; then
        err "SSL certificate issuance failed!"
        echo ""
        err "Please check:"
        info "1. A-record for $domain points to correct IP"
        info "2. Port 80 is open and accessible from internet"
        info "3. No CDN/proxy is interfering (Cloudflare orange cloud, etc.)"
        exit 1
    fi

    log "Certificate issued successfully"
}

# Install certificate
install_cert() {
    local domain="$1"
    local cert_path="$CERT_DIR/$domain"

    log "Creating certificate directory: $cert_path"
    mkdir -p "$cert_path"

    local reload_cmd="systemctl reload nginx ; systemctl restart x-ui"

    log "Installing certificate..."
    ~/.acme.sh/acme.sh --installcert --force -d "$domain" \
        --key-file "$cert_path/privkey.pem" \
        --fullchain-file "$cert_path/fullchain.pem" \
        --reloadcmd "$reload_cmd" >/dev/null 2>&1

    chmod 600 "$cert_path/privkey.pem"
    chmod 644 "$cert_path/fullchain.pem"

    info "Key:  $cert_path/privkey.pem"
    info "Cert: $cert_path/fullchain.pem"
    info "Auto-reload: $reload_cmd"

    log "Certificate installed"
}

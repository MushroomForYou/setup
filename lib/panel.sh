#!/bin/bash

# Global variables for panel settings
PANEL_PORT=""
WEB_BASE_PATH=""
DB_TYPE=""
API_TOKEN=""

# Install 3X-UI panel
install_panel() {
    local username="$1"
    local password="$2"

    log "Downloading 3X-UI installer..."

    export XUI_NONINTERACTIVE=1
    export XUI_SSL_MODE=none
    export XUI_USERNAME="$username"
    export XUI_PASSWORD="$password"

    log "Running installer (this may take a minute)..."

    if ! bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh); then
        err "3X-UI installation failed!"
        exit 1
    fi

    log "Reading installation results..."

    if [ ! -f /etc/x-ui/install-result.env ]; then
        err "Installation result file not found at /etc/x-ui/install-result.env"
        exit 1
    fi

    source /etc/x-ui/install-result.env

    PANEL_PORT="$XUI_PANEL_PORT"
    WEB_BASE_PATH="$XUI_WEB_BASE_PATH"
    DB_TYPE="$XUI_DB_TYPE"
    API_TOKEN="$XUI_API_TOKEN"

    if [ -z "$PANEL_PORT" ] || [ -z "$WEB_BASE_PATH" ] || [ -z "$DB_TYPE" ] || [ -z "$API_TOKEN" ]; then
        err "Failed to read panel settings from install-result.env"
        exit 1
    fi

    log "Allowing panel port in firewall..."
    ufw allow "$PANEL_PORT/tcp" >/dev/null 2>&1

    info "Port:        $PANEL_PORT"
    info "Web Path:    /$WEB_BASE_PATH"
    info "Database:    $DB_TYPE"
    info "API Token:   ${API_TOKEN:0:8}..."

    log "3X-UI panel installed"
}

# Start services
start_services() {
    log "Enabling and starting Nginx..."
    systemctl enable nginx >/dev/null 2>&1
    systemctl start nginx

    log "Enabling and starting 3X-UI..."
    systemctl enable x-ui >/dev/null 2>&1
    systemctl restart x-ui

    log "All services started"
}

# Show success message
show_success() {
    local domain="$1"
    local ip="$2"
    local port="$3"
    local username="$4"
    local password="$5"
    local web_path="$6"
    local db_type="$7"
    local api_token="$8"
    local cert_path="$CERT_DIR/$domain"

    echo ""
    echo -e "${BOLD}${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${WHITE}║${NC}                                                              ${BOLD}${WHITE}║${NC}"
    echo -e "${BOLD}${WHITE}║${NC}  ${ICON_GLOBE} Domain:      ${YELLOW}$domain${NC}"
    echo -e "${BOLD}${WHITE}║${NC}  ${ICON_SERVER} Server IP:   ${YELLOW}$ip${NC}"
    echo -e "${BOLD}${WHITE}║${NC}  ${ICON_PLUG} Panel Port:  ${YELLOW}$port${NC}"
    echo -e "${BOLD}${WHITE}║${NC}  ${ICON_KEY} Username:    ${YELLOW}$username${NC}"
    echo -e "${BOLD}${WHITE}║${NC}  ${ICON_LOCK} Password:    ${YELLOW}$password${NC}"
    echo -e "${BOLD}${WHITE}║${NC}  ${ICON_FOLDER} Web Path:    ${YELLOW}/$web_path${NC}"
    echo -e "${BOLD}${WHITE}║${NC}  ${ICON_DB} Database:    ${YELLOW}$db_type (/etc/x-ui/x-ui.db)${NC}"
    echo -e "${BOLD}${WHITE}║${NC}  ${ICON_ZAP} API Token:   ${YELLOW}${api_token:0:16}...${NC}"
    echo -e "${BOLD}${WHITE}║${NC}                                                              ${BOLD}${WHITE}║${NC}"
    echo -e "${BOLD}${WHITE}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}${WHITE}║${NC}                                                              ${BOLD}${WHITE}║${NC}"
    echo -e "${BOLD}${WHITE}║${NC}  ${ICON_LOCK} SSL:         ${YELLOW}Let's Encrypt (auto-renewal enabled)${NC}"
    echo -e "${BOLD}${WHITE}║${NC}  ${ICON_FOLDER} Cert Path:   ${YELLOW}$cert_path/${NC}"
    echo -e "${BOLD}${WHITE}║${NC}  ${ICON_REFRESH} Auto-Renew:  ${YELLOW}Enabled (acme.sh cron job)${NC}"
    echo -e "${BOLD}${WHITE}║${NC}                                                              ${BOLD}${WHITE}║${NC}"
    echo -e "${BOLD}${WHITE}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}${WHITE}║${NC}                                                              ${BOLD}${WHITE}║${NC}"
    echo -e "${BOLD}${WHITE}║${NC}  ${ICON_ROCKET} Access URL: ${YELLOW}https://$domain/$web_path${NC}"
    echo -e "${BOLD}${WHITE}║${NC}                                                              ${BOLD}${WHITE}║${NC}"
    echo -e "${BOLD}${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Useful commands:${NC}"
    info "x-ui            - Manage panel"
    info "x-ui status     - Check panel status"
    info "x-ui settings   - View credentials"
    info "x-ui update     - Update panel"
    echo ""
}

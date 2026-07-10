#!/bin/bash
set -e

REPO_URL="https://raw.githubusercontent.com/MushroomForYou/setup/main"

# Detect if running locally or remotely
if [[ "${BASH_SOURCE[0]}" == "/dev/fd/"* ]]; then
    # Running via curl - download libs to temp directory
    LIB_DIR=$(mktemp -d)
    trap "rm -rf $LIB_DIR" EXIT

    download_lib() {
        local file="$1"
        curl -sL "$REPO_URL/lib/$file" -o "$LIB_DIR/$file"
    }

    download_lib "colors.sh"
    download_lib "logger.sh"
    download_lib "cli.sh"
    download_lib "validators.sh"
    download_lib "system.sh"
    download_lib "ssl.sh"
    download_lib "nginx.sh"
    download_lib "panel.sh"
    download_lib "inbounds.sh"
else
    # Running locally
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    LIB_DIR="$SCRIPT_DIR/lib"
fi

# Source library modules
source "$LIB_DIR/colors.sh"
source "$LIB_DIR/logger.sh"
source "$LIB_DIR/cli.sh"
source "$LIB_DIR/validators.sh"
source "$LIB_DIR/system.sh"
source "$LIB_DIR/ssl.sh"
source "$LIB_DIR/nginx.sh"
source "$LIB_DIR/panel.sh"
source "$LIB_DIR/inbounds.sh"

# Main entry point
main() {

    # Parse CLI arguments
    parse_args "$@"

    # Validate required arguments
    validate_args

    # Check root
    check_root

    # Show configuration
    show_config

    # Execute installation steps
    step 1 "Updating system packages"
    update_system

    step 2 "Installing dependencies"
    install_dependencies

    step 3 "Configuring firewall"
    configure_firewall

    step 4 "Checking DNS resolution"
    check_dns "$DOMAIN" "$IP"

    step 5 "Installing acme.sh"
    install_acme "$ACME_EMAIL"

    step 6 "Installing 3X-UI panel"
    install_panel "$USERNAME" "$PASSWORD"

    step 7 "Obtaining SSL certificate"
    obtain_ssl "$DOMAIN" "$ACME_EMAIL"

    step 8 "Installing certificate"
    install_cert "$DOMAIN"

    step 9 "Configuring Nginx"
    configure_nginx "$DOMAIN" "$PANEL_PORT"

    step 10 "Starting services"
    start_services

    step 11 "Creating VLESS Reality inbound"
    create_vless_inbound

    step 12 "Creating Hysteria2 inbound"
    create_hysteria_inbound

    # Show success banner
    show_success "$DOMAIN" "$IP" "$PANEL_PORT" "$USERNAME" "$PASSWORD" "$WEB_BASE_PATH" "$DB_TYPE" "$API_TOKEN"
}

main "$@"

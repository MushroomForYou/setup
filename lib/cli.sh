#!/bin/bash

# Default values
USERNAME="admin"
PASSWORD="admin"
DOMAIN=""
IP=""
ACME_EMAIL=""

# Help message
show_help() {
    cat << 'EOF'
3X-UI Auto-Installer

Usage: install.sh [OPTIONS]

Required options:
  --domain DOMAIN      Your domain name (e.g., vpn.example.com)
  --ip IP              Server IP address (e.g., 1.2.3.4)
  --email EMAIL        Email for Let's Encrypt notifications

Optional options:
  --username USER      Admin username (default: admin)
  --password PASS      Admin password (default: admin)

Other:
  -h, --help           Show this help message
  -q, --quiet          Quiet mode (errors only)
  -v, --verbose        Verbose mode (debug output)

Examples:
  # Full command
  bash install.sh --domain vpn.example.com --ip 1.2.3.4 --email admin@example.com

  # With custom credentials
  bash install.sh --domain vpn.example.com --ip 1.2.3.4 --email admin@example.com --username myuser --password mypass

  # Remote execution via curl
  bash <(curl -sL https://raw.githubusercontent.com/VPN-EXPRESS/setup-script/main/install.sh) \\
    --domain vpn.example.com --ip 1.2.3.4 --email admin@example.com

EOF
    exit 0
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --ip)
                IP="$2"
                shift 2
                ;;
            --email)
                ACME_EMAIL="$2"
                shift 2
                ;;
            --username)
                USERNAME="$2"
                shift 2
                ;;
            --password)
                PASSWORD="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                ;;
            -q|--quiet)
                CURRENT_LOG_LEVEL=$LOG_LEVEL_QUIET
                shift
                ;;
            -v|--verbose)
                CURRENT_LOG_LEVEL=$LOG_LEVEL_DEBUG
                shift
                ;;
            *)
                err "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Show configuration
show_config() {
    echo -e "${CYAN}Configuration:${NC}"
    echo -e "  ${ICON_GLOBE} Domain:  ${YELLOW}$DOMAIN${NC}"
    echo -e "  ${ICON_SERVER} IP:      ${YELLOW}$IP${NC}"
    echo -e "  ${ICON_KEY} Email:   ${YELLOW}$ACME_EMAIL${NC}"
    echo -e "  ${ICON_LOCK} User:    ${YELLOW}$USERNAME${NC}"
    echo -e "  ${ICON_LOCK} Pass:    ${YELLOW}$PASSWORD${NC}"
    echo ""
}

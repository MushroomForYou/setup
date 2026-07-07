#!/bin/bash
# Validation functions

# Validate required arguments
validate_args() {
    local has_error=0

    if [ -z "$DOMAIN" ]; then
        err "--domain is required"
        has_error=1
    fi

    if [ -z "$IP" ]; then
        err "--ip is required"
        has_error=1
    fi

    if [ -z "$ACME_EMAIL" ]; then
        err "--email is required"
        has_error=1
    fi

    # Validate IP format
    if [ -n "$IP" ]; then
        if ! [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            err "Invalid IP address format: $IP"
            has_error=1
        fi
    fi

    # Validate email format
    if [ -n "$ACME_EMAIL" ]; then
        if ! [[ "$ACME_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            err "Invalid email format: $ACME_EMAIL"
            has_error=1
        fi
    fi

    # Validate domain format
    if [ -n "$DOMAIN" ]; then
        if ! [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            err "Invalid domain format: $DOMAIN"
            has_error=1
        fi
    fi

    if [ $has_error -eq 1 ]; then
        echo ""
        echo "Use --help for usage information"
        exit 1
    fi
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        err "This script must be run as root"
        info "Run: sudo bash $0 $@"
        exit 1
    fi
}

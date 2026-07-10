#!/bin/bash

create_vless_inbound() {
    local base_url="https://$DOMAIN/$WEB_BASE_PATH"

    log "Creating VLESS Reality inbound..."
    info "  Base URL: $base_url"

    # API call with Bearer token
    api_call() {
        local method="$1"
        local url="$2"
        local data="$3"
        local extra_headers="$4"
        local max_time="${5:-30}"

        local cmd=(curl -s --max-time "$max_time" \
            -H "Authorization: Bearer $API_TOKEN" \
            -H "X-Requested-With: XMLHttpRequest")

        if [ -n "$extra_headers" ]; then
            IFS='|' read -ra HDRS <<< "$extra_headers"
            for h in "${HDRS[@]}"; do
                cmd+=(-H "$h")
            done
        fi

        if [ "$method" == "POST" ] && [ -n "$data" ]; then
            cmd+=(-X POST -d "$data")
        elif [ "$method" == "POST" ]; then
            cmd+=(-X POST)
        fi

        cmd+=("$url")
        "${cmd[@]}"
    }

    # Generate X25519 Certificate
    log "Generating X25519 certificate..."
    CERT_RESP=$(api_call GET "$base_url/panel/api/server/getNewX25519Cert")
    if ! echo "$CERT_RESP" | jq -e '.success' &>/dev/null; then
        err "Failed to generate X25519 cert: $CERT_RESP"
        return 1
    fi

    PRIVATE_KEY=$(echo "$CERT_RESP" | jq -r '.obj.privateKey')
    PUBLIC_KEY=$(echo "$CERT_RESP" | jq -r '.obj.publicKey')
    log "X25519 keys generated"
    info "  Public Key:  ${PUBLIC_KEY:0:20}..."

    # Scan Reality Targets
    log "Scanning Reality targets (this may take ~30-60s)..."
    SCAN_RESP=$(api_call POST "$base_url/panel/api/server/scanRealityTargets" "{}" "" 120)

    if ! echo "$SCAN_RESP" | jq -e '.success' &>/dev/null; then
        err "Scan failed: $SCAN_RESP"
        return 1
    fi

    # Select Best Target
    log "Selecting best Reality target..."
    BEST=$(echo "$SCAN_RESP" | jq -r '
        .obj
        | map(select(.feasible == true and .tls13 == true and .h2 == true and .x25519 == true))
        | sort_by(.latencyMs)
        | .[0]
    ')

    if [ "$BEST" == "null" ] || [ -z "$BEST" ] || [ "$BEST" == "" ]; then
        err "No suitable Reality target found (required: feasible, tls13, h2, x25519)"
        return 1
    fi

    TARGET=$(echo "$BEST" | jq -r '.target')
    SERVER_NAMES_JSON=$(echo "$BEST" | jq -c '.serverNames')
    LATENCY=$(echo "$BEST" | jq -r '.latencyMs')

    log "Best target selected:"
    info "  Target:  $TARGET"
    info "  Latency: ${LATENCY}ms"
    info "  SNI:     $(echo "$SERVER_NAMES_JSON" | jq -r '.[0]')"

    # Generate Port
    PORT=$(shuf -i 10000-65000 -n 1)
    log "Generated port: $PORT"

    # Generate Short IDs
    gen_shortid() {
        local len=$1
        local bytes=$(( (len + 1) / 2 ))
        openssl rand -hex "$bytes" | cut -c1-"$len"
    }

    SHORT_IDS_JSON=$(jq -n \
        --arg s1 "$(gen_shortid 4)" \
        --arg s2 "$(gen_shortid 2)" \
        --arg s3 "$(gen_shortid 6)" \
        --arg s4 "$(gen_shortid 8)" \
        --arg s5 "$(gen_shortid 16)" \
        --arg s6 "$(gen_shortid 10)" \
        --arg s7 "$(gen_shortid 12)" \
        --arg s8 "$(gen_shortid 14)" \
        '[$s1, $s2, $s3, $s4, $s5, $s6, $s7, $s8]')

    log "Generated short IDs"

    # Build Config JSONs
    SETTINGS=$(jq -n --argjson testseed '[900,500,900,256]' '{
        "clients": [],
        "decryption": "none",
        "encryption": "none",
        "testseed": $testseed
    }')

    STREAM_SETTINGS=$(jq -n \
        --arg target "$TARGET" \
        --argjson serverNames "$SERVER_NAMES_JSON" \
        --arg privateKey "$PRIVATE_KEY" \
        --argjson shortIds "$SHORT_IDS_JSON" \
        --arg publicKey "$PUBLIC_KEY" \
        '{
            "network": "tcp",
            "security": "reality",
            "tcpSettings": {
                "acceptProxyProtocol": false,
                "header": {
                    "type": "none"
                }
            },
            "realitySettings": {
                "show": false,
                "xver": 0,
                "target": $target,
                "serverNames": $serverNames,
                "privateKey": $privateKey,
                "minClientVer": "",
                "maxClientVer": "",
                "maxTimediff": 0,
                "shortIds": $shortIds,
                "mldsa65Seed": "",
                "settings": {
                    "publicKey": $publicKey,
                    "fingerprint": "chrome",
                    "serverName": "",
                    "spiderX": "/",
                    "mldsa65Verify": ""
                }
            }
        }')

    SNIFFING=$(jq -n '{"enabled": false}')

    # URL Encode Payload
    SETTINGS_ENC=$(echo "$SETTINGS" | jq -c . | jq -sRr @uri)
    STREAM_ENC=$(echo "$STREAM_SETTINGS" | jq -c . | jq -sRr @uri)
    SNIFFING_ENC=$(echo "$SNIFFING" | jq -c . | jq -sRr @uri)

    PAYLOAD="up=0&down=0&total=0&remark=&enable=true&expiryTime=0&trafficReset=never&lastTrafficResetTime=0&listen=&port=$PORT&protocol=vless&settings=$SETTINGS_ENC&streamSettings=$STREAM_ENC&sniffing=$SNIFFING_ENC&tag=in-${PORT}-tcp&shareAddrStrategy=listen&shareAddr=&subSortIndex=1"

    # Create Inbound
    log "Creating VLESS Reality inbound..."
    ADD_RESP=$(api_call POST "$base_url/panel/api/inbounds/add" "$PAYLOAD" "Content-Type: application/x-www-form-urlencoded")

    if ! echo "$ADD_RESP" | jq -e '.success' &>/dev/null; then
        err "Failed to create inbound: $ADD_RESP"
        return 1
    fi

    INBOUND_ID=$(echo "$ADD_RESP" | jq -r '.obj.id // empty')
    log "Inbound created successfully!"
    info "  Inbound ID: ${INBOUND_ID:-N/A}"

    # Firewall
    log "Opening port $PORT in firewall..."
    ufw allow "$PORT/tcp" >/dev/null 2>&1 || true

    # Summary
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     ✅ VLESS REALITY INBOUND CREATED                 ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  🌐 Domain:      ${YELLOW}$DOMAIN${NC}"
    echo -e "${GREEN}║${NC}  🔌 Port:        ${YELLOW}$PORT${NC}"
    echo -e "${GREEN}║${NC}  🎯 Target:      ${YELLOW}$TARGET${NC}"
    echo -e "${GREEN}║${NC}  📡 SNI:         ${YELLOW}$(echo "$SERVER_NAMES_JSON" | jq -r '.[0]')${NC}"
    echo -e "${GREEN}║${NC}  🔑 Public Key:   ${YELLOW}$PUBLIC_KEY${NC}"
    echo -e "${GREEN}║${NC}  🔒 Private Key: ${YELLOW}${PRIVATE_KEY:0:20}...${NC}"
    echo -e "${GREEN}║${NC}  🏷  Tag:         ${YELLOW}in-${PORT}-tcp${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
}


create_hysteria_inbound() {
    local base_url="https://$DOMAIN/$WEB_BASE_PATH"
    local cert_file="$CERT_DIR/$DOMAIN/fullchain.pem"
    local key_file="$CERT_DIR/$DOMAIN/privkey.pem"

    log "Creating Hysteria2 inbound..."
    info "  Base URL: $base_url"
    info "  Cert: $cert_file"

    # Verify certificates exist
    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        err "Certificate files not found:"
        err "  Cert: $cert_file"
        err "  Key:  $key_file"
        return 1
    fi

    # Helper: API call with Bearer token
    api_call() {
        local method="$1"
        local url="$2"
        local data="$3"
        local extra_headers="$4"
        local max_time="${5:-30}"

        local cmd=(curl -s --max-time "$max_time" \
            -H "Authorization: Bearer $API_TOKEN" \
            -H "X-Requested-With: XMLHttpRequest")

        if [ -n "$extra_headers" ]; then
            IFS='|' read -ra HDRS <<< "$extra_headers"
            for h in "${HDRS[@]}"; do
                cmd+=(-H "$h")
            done
        fi

        if [ "$method" == "POST" ] && [ -n "$data" ]; then
            cmd+=(-X POST -d "$data")
        elif [ "$method" == "POST" ]; then
            cmd+=(-X POST)
        fi

        cmd+=("$url")
        "${cmd[@]}"
    }

    # Generate Random Port
    PORT=$(shuf -i 10000-65000 -n 1)
    log "Generated port: $PORT"

    # Generate Salamander Password
    SALAMANDER_PASS=$(openssl rand -base64 16 | tr -d '=+/' | cut -c1-16)
    log "Generated salamander password"

    # Build Config JSONs
    SETTINGS=$(jq -n '{
        "version": 2,
        "clients": []
    }')

    STREAM_SETTINGS=$(jq -n \
        --arg certFile "$cert_file" \
        --arg keyFile "$key_file" \
        --arg salamanderPass "$SALAMANDER_PASS" \
        '{
            "network": "hysteria",
            "security": "tls",
            "hysteriaSettings": {
                "version": 2,
                "udpIdleTimeout": 60,
                "masquerade": {
                    "type": "404",
                    "dir": "",
                    "url": "",
                    "rewriteHost": false,
                    "insecure": false,
                    "content": "",
                    "headers": {},
                    "statusCode": 404
                }
            },
            "tlsSettings": {
                "serverName": "",
                "minVersion": "1.2",
                "maxVersion": "1.3",
                "cipherSuites": "",
                "rejectUnknownSni": false,
                "disableSystemRoot": false,
                "enableSessionResumption": false,
                "certificates": [
                    {
                        "useFile": true,
                        "certificateFile": $certFile,
                        "keyFile": $keyFile,
                        "certificate": [],
                        "key": [],
                        "ocspStapling": 0,
                        "oneTimeLoading": false,
                        "usage": "encipherment",
                        "buildChain": false
                    }
                ],
                "alpn": ["h3"],
                "echServerKeys": "",
                "settings": {
                    "fingerprint": "",
                    "echConfigList": "",
                    "pinnedPeerCertSha256": [],
                    "verifyPeerCertByName": ""
                }
            },
            "finalmask": {
                "udp": [
                    {
                        "type": "salamander",
                        "settings": {
                            "password": $salamanderPass
                        }
                    }
                ]
            }
        }')

    SNIFFING=$(jq -n '{"enabled": false}')

    # URL Encode Payload
    SETTINGS_ENC=$(echo "$SETTINGS" | jq -c . | jq -sRr @uri)
    STREAM_ENC=$(echo "$STREAM_SETTINGS" | jq -c . | jq -sRr @uri)
    SNIFFING_ENC=$(echo "$SNIFFING" | jq -c . | jq -sRr @uri)

    PAYLOAD="up=0&down=0&total=0&remark=&enable=true&expiryTime=0&trafficReset=never&lastTrafficResetTime=0&listen=&port=$PORT&protocol=hysteria&settings=$SETTINGS_ENC&streamSettings=$STREAM_ENC&sniffing=$SNIFFING_ENC&tag=in-${PORT}-udp&shareAddrStrategy=listen&shareAddr=&subSortIndex=1"

    # Create Inbound
    log "Creating Hysteria2 inbound..."
    ADD_RESP=$(api_call POST "$base_url/panel/api/inbounds/add" "$PAYLOAD" "Content-Type: application/x-www-form-urlencoded")

    if ! echo "$ADD_RESP" | jq -e '.success' &>/dev/null; then
        err "Failed to create inbound: $ADD_RESP"
        return 1
    fi

    INBOUND_ID=$(echo "$ADD_RESP" | jq -r '.obj.id // empty')
    log "Inbound created successfully!"
    info "  Inbound ID: ${INBOUND_ID:-N/A}"

    # Firewall
    log "Opening port $PORT in firewall (UDP)..."
    ufw allow "$PORT/udp" >/dev/null 2>&1 || true
    ufw allow "$PORT/tcp" >/dev/null 2>&1 || true

    # Summary
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     ✅ HYSTERIA2 INBOUND CREATED                     ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  🌐 Domain:           ${YELLOW}$DOMAIN${NC}"
    echo -e "${GREEN}║${NC}  🔌 Port:             ${YELLOW}$PORT${NC}"
    echo -e "${GREEN}║${NC}  📁 Certificate:      ${YELLOW}$cert_file${NC}"
    echo -e "${GREEN}║${NC}  🔒 Key File:         ${YELLOW}$key_file${NC}"
    echo -e "${GREEN}║${NC}  🎭 Masquerade:       ${YELLOW}404${NC}"
    echo -e "${GREEN}║${NC}  🐉 Salamander Pass:  ${YELLOW}$SALAMANDER_PASS${NC}"
    echo -e "${GREEN}║${NC}  🏷  Tag:              ${YELLOW}in-${PORT}-udp${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
}

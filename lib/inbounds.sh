#!/bin/bash

api_call() {
    local method="$1"
    local url="$2"
    local data="${3:-}"
    local extra_headers="${4:-}"
    local max_time="${5:-30}"

    local cmd=(curl -sS --max-time "$max_time" --connect-timeout 5 \
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

api_call_with_retry() {
    local method="$1"
    local url="$2"
    local data="${3:-}"
    local extra_headers="${4:-}"
    local max_time="${5:-30}"
    local retries="${6:-8}"
    local delay="${7:-3}"
    local attempt=1
    local response=""
    local reason=""

    while [ "$attempt" -le "$retries" ]; do
        if ! response=$(api_call "$method" "$url" "$data" "$extra_headers" "$max_time"); then
            response=""
        fi

        if response_is_successful "$response"; then
            printf '%s\n' "$response"
            return 0
        fi

        reason=$(describe_failure "$response")
        if [ "$attempt" -lt "$retries" ]; then
            warn "API call failed (${reason}), retrying ${attempt}/${retries}: $url"
            sleep "$delay"
        else
            warn "API call failed (${reason}) on final attempt ${attempt}/${retries}: $url"
        fi

        attempt=$((attempt + 1))
    done

    printf '%s\n' "$response"
    return 1
}

# Explains *why* response_is_successful rejected a response, without
# duplicating its validation logic. Used only for logging during retries,
# so it never needs to be as strict / side-effect-free as the real check.
describe_failure() {
    local data="$1"
    local docs msg

    if [ -z "$data" ]; then
        echo "empty response (curl failed, timed out, or connection refused)"
        return
    fi

    if ! printf '%s' "$data" | jq empty >/dev/null 2>&1; then
        echo "not valid JSON, first 120 chars: ${data:0:120}"
        return
    fi

    docs=$(printf '%s' "$data" | jq -rs 'length' 2>/dev/null)
    if [ "$docs" != "1" ]; then
        echo "response contained ${docs} JSON value(s) instead of exactly 1 (duplicated/concatenated body?)"
        return
    fi

    msg=$(printf '%s' "$data" | jq -r '.msg // empty' 2>/dev/null)
    if [ -n "$msg" ]; then
        echo "success=false, msg: \"$msg\""
    else
        echo "success=false (no msg field in response)"
    fi
}

response_is_successful() {
    local data="$1"
    local docs success

    if [ -z "$data" ]; then
        return 1
    fi

    if ! printf '%s' "$data" | jq empty >/dev/null 2>&1; then
        return 1
    fi

    # Require *exactly one* JSON value in the body.
    #
    # Why: if the response body ever ends up containing more than one
    # concatenated JSON document (e.g. an upstream/proxy hiccup that
    # duplicates the body), `jq -r '.success // false'` prints one line
    # PER document instead of one value total. `$success` then becomes a
    # multi-line string like "true\ntrue", which can never equal the
    # literal "true" in the comparison below -- so a response that is
    # genuinely {"success":true,...} gets silently treated as a failure
    # and retried forever. This is almost certainly what you were hitting:
    # the logged response was clearly {"success":true,...} with a real
    # keypair, yet the call kept retrying and eventually gave up.
    docs=$(printf '%s' "$data" | jq -rs 'length' 2>/dev/null)
    if [ "$docs" != "1" ]; then
        return 1
    fi

    success=$(printf '%s' "$data" | jq -r '.success // false' 2>/dev/null)
    [ "$success" = "true" ]
}

json_is_valid() {
    local data="$1"
    printf '%s' "$data" | jq empty >/dev/null 2>&1
}

json_has_success() {
    local data="$1"
    response_is_successful "$data"
}

json_get() {
    local data="$1"
    local expr="$2"
    printf '%s' "$data" | jq -r "$expr // empty" 2>/dev/null
}

create_vless_inbound() {
    local base_url="https://$DOMAIN/$WEB_BASE_PATH"
    base_url="${base_url%/}"

    log "Creating VLESS Reality inbound..."
    info "  Base URL: $base_url"

    # Generate X25519 Certificate
    log "Generating X25519 certificate..."
    if ! CERT_RESP=$(api_call_with_retry GET "$base_url/panel/api/server/getNewX25519Cert" "" "" 30 8 3); then
        err "Failed to generate X25519 cert. Raw response:"
        echo "$CERT_RESP"
        return 1
    fi

    info "API response:"
    printf '%s\n' "$CERT_RESP"

    if ! json_is_valid "$CERT_RESP" || ! json_has_success "$CERT_RESP"; then
        err "Failed to generate X25519 cert. Raw response:"
        echo "$CERT_RESP"
        return 1
    fi

    PRIVATE_KEY=$(json_get "$CERT_RESP" '.obj.privateKey')
    PUBLIC_KEY=$(json_get "$CERT_RESP" '.obj.publicKey')
    if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
        err "Received invalid X25519 cert payload: $CERT_RESP"
        return 1
    fi

    log "X25519 keys generated"
    info "  Public Key:  ${PUBLIC_KEY:0:20}..."

    # Scan Reality Targets
    log "Scanning Reality targets (this may take ~30-60s)..."
    if ! SCAN_RESP=$(api_call_with_retry POST "$base_url/panel/api/server/scanRealityTargets" "{}" "" 120 8 3); then
        err "Scan failed. Raw response:"
        echo "$SCAN_RESP"
        return 1
    fi

    info "API response:"
    printf '%s\n' "$SCAN_RESP"

    # Select Best Target
    log "Selecting best Reality target..."
    if ! json_is_valid "$SCAN_RESP" || ! json_has_success "$SCAN_RESP"; then
        err "Scan failed. Raw response:"
        echo "$SCAN_RESP"
        return 1
    fi

    BEST=$(echo "$SCAN_RESP" | jq -r '
        .obj
        | map(select(.feasible == true and .tls13 == true and .h2 == true and .x25519 == true))
        | sort_by(.latencyMs)
        | .[0]
    ' 2>/dev/null)

    if [ "$BEST" == "null" ] || [ -z "$BEST" ] || [ "$BEST" == "" ]; then
        err "No suitable Reality target found (required: feasible, tls13, h2, x25519)"
        return 1
    fi

    TARGET=$(echo "$BEST" | jq -r '.target' 2>/dev/null)
    SERVER_NAMES_JSON=$(echo "$BEST" | jq -c '.serverNames' 2>/dev/null)
    LATENCY=$(echo "$BEST" | jq -r '.latencyMs' 2>/dev/null)

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
    if ! ADD_RESP=$(api_call_with_retry POST "$base_url/panel/api/inbounds/add" "$PAYLOAD" "Content-Type: application/x-www-form-urlencoded" 60 8 3); then
        err "Failed to create inbound. Raw response:"
        echo "$ADD_RESP"
        return 1
    fi

    info "API response:"
    printf '%s\n' "$ADD_RESP"

    if ! json_is_valid "$ADD_RESP" || ! json_has_success "$ADD_RESP"; then
        err "Failed to create inbound. Raw response:"
        echo "$ADD_RESP"
        return 1
    fi

    INBOUND_ID=$(json_get "$ADD_RESP" '.obj.id')
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
    base_url="${base_url%/}"
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
    if ! ADD_RESP=$(api_call_with_retry POST "$base_url/panel/api/inbounds/add" "$PAYLOAD" "Content-Type: application/x-www-form-urlencoded" 60 8 3); then
        err "Failed to create inbound. Raw response:"
        echo "$ADD_RESP"
        return 1
    fi

    info "API response:"
    printf '%s\n' "$ADD_RESP"

    if ! json_is_valid "$ADD_RESP" || ! json_has_success "$ADD_RESP"; then
        err "Failed to create inbound. Raw response:"
        echo "$ADD_RESP"
        return 1
    fi

    INBOUND_ID=$(json_get "$ADD_RESP" '.obj.id')
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
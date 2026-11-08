#!/bin/bash

function datef() {
    # Output:
    # Sat Jun  8 20:29:08 2019
    date "+%a %b %-d %T %Y"
}

# Client ids end up in file system paths and easy-rsa commands, so only allow a
# conservative character set.
function validateClientId() {
    local id="$1"

    if [[ -z "$id" || ! "$id" =~ ^[A-Za-z0-9][A-Za-z0-9_.@-]{0,63}$ ]]; then
        echo "$(datef) ERROR: invalid client id [$id]. Allowed: letters, digits, '_', '.', '@', '-' (max 64 chars, must start with a letter or digit)"
        exit 1
    fi
}

function createConfig() {
    cd "$APP_PERSIST_DIR"

    if [ -n "$PASSWORD_PROTECTED" ]; then
        easyrsa --batch build-client-full "$CLIENT_ID"
    else
        easyrsa --batch build-client-full "$CLIENT_ID" nopass &> /dev/null
    fi

    # Writing new private key to pki/private/$CLIENT_ID.key
    # Client certificate pki/issued/$CLIENT_ID.crt
    # CA is by the path pki/ca.crt

    # Client configs embed a private key: keep them readable by root only
    mkdir -p "$CLIENT_PATH"
    chmod 700 "$CLIENT_PATH"

    cp "pki/private/$CLIENT_ID.key" "pki/issued/$CLIENT_ID.crt" pki/ca.crt /etc/openvpn/ta.key "$CLIENT_PATH"

    cd "$APP_INSTALL_PATH"
    cp config/client.ovpn "$CLIENT_PATH"
    sed -i 's/%HOST_TUN_PROTOCOL%/'"$HOST_TUN_PROTOCOL"'/g' "$CLIENT_PATH/client.ovpn"

    echo -e "\nremote $HOST_ADDR_INT $HOST_TUN_PORT" >> "$CLIENT_PATH/client.ovpn"

    # Embed client authentication files into config file
    cat <(echo -e '<ca>') \
        "$CLIENT_PATH/ca.crt" <(echo -e '</ca>\n<cert>') \
        "$CLIENT_PATH/$CLIENT_ID.crt" <(echo -e '</cert>\n<key>') \
        "$CLIENT_PATH/$CLIENT_ID.key" <(echo -e '</key>\n<tls-auth>') \
        "$CLIENT_PATH/ta.key" <(echo -e '</tls-auth>') \
        >> "$CLIENT_PATH/client.ovpn"

    # Append client id info to the config
    echo ";client-id $CLIENT_ID" >> "$CLIENT_PATH/client.ovpn"

    chmod 600 "$CLIENT_PATH"/*
}

function zipFiles() {
    local CLIENT_PATH="$1"
    local IS_QUITE="$2"

    # Plain zip archive (no password)
    # -tzip: create zip format
    # -mx=0: no compression (just store)
    (cd "$CLIENT_PATH" && 7z a -tzip -mx=0 client.zip client.ovpn > /dev/null 2>&1 && chmod 600 client.zip)
    if [ "$IS_QUITE" != "-q" ]
    then
       echo "$(datef) $CLIENT_PATH/client.zip file has been generated"
    fi
}

function zipFilesWithPassword() {
    local CLIENT_PATH="$1"
    local ZIP_PASSWORD="$2"
    local IS_QUITE="$3"
    # Use 7z with AES-256 encryption (secure encryption method)
    # -tzip: create zip format for compatibility
    # -p: password protection
    # -mem=AES256: use AES-256 encryption (NOT weak ZipCrypto)
    # -mx=0: no compression (just store)
    (cd "$CLIENT_PATH" && 7z a -tzip -p"$ZIP_PASSWORD" -mem=AES256 -mx=0 client.zip client.ovpn > /dev/null 2>&1 && chmod 600 client.zip)

    if [ "$IS_QUITE" != "-q" ]
    then
       echo "$(datef) $CLIENT_PATH/client.zip with AES-256 password protection has been generated"
    fi
}

function removeConfig() {
    local CLIENT_ID="$1"

    validateClientId "$CLIENT_ID"

    cd "$APP_PERSIST_DIR"

    if [ ! -f "pki/issued/$CLIENT_ID.crt" ]; then
        echo "$(datef) ERROR: no certificate found for client id [$CLIENT_ID]"
        exit 1
    fi

    easyrsa --batch revoke "$CLIENT_ID"
    easyrsa --batch --days="$CRL_DAYS" gen-crl

    # OpenVPN re-reads the CRL on every connection, so the new one is effective immediately
    cp "$APP_PERSIST_DIR/pki/crl.pem" /etc/openvpn/crl.pem
    chmod 644 /etc/openvpn/crl.pem

    echo "$(datef) Client [$CLIENT_ID] has been revoked"

    cd "$APP_INSTALL_PATH"
}

function getVersion() {
    local app_version="$APP_NAME $(cat "$APP_INSTALL_PATH/config/VERSION")"

    echo "$app_version"
}

function getVersionFull() {
    echo "$(datef) $(getVersion)"
}

function listConfigs() {
    if [ -d "$APP_PERSIST_DIR/clients" ]; then
        ls -1 "$APP_PERSIST_DIR/clients"
    fi
}

function getConfig() {
    local CLIENT_ID="$1"

    validateClientId "$CLIENT_ID"

    if [ ! -f "$APP_PERSIST_DIR/clients/$CLIENT_ID/client.ovpn" ]; then
        echo "$(datef) ERROR: no config found for client id [$CLIENT_ID]"
        exit 1
    fi

    cat "$APP_PERSIST_DIR/clients/$CLIENT_ID/client.ovpn"
}

function generateClientConfig() {
    #case
    #first argument  = n  use second argument as CLIENT_ID
    #first argument = np use second argument as CLIENT_ID and set PASSWORD_PROTECTED as yes
    #default generate random CLIENT_ID
    FLAGS=$1
    case $FLAGS in
        n)
            CLIENT_ID="$2"
            validateClientId "$CLIENT_ID"
            ;;
        np)
            CLIENT_ID="$2"
            validateClientId "$CLIENT_ID"
            PASSWORD_PROTECTED="yes"
            ;;
        *)
            CLIENT_ID="$(head -c 512 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 32 || true)"
            ;;
    esac

    CLIENT_PATH="$APP_PERSIST_DIR/clients/$CLIENT_ID"

    if [ -d "$CLIENT_PATH" ] || [ -f "$APP_PERSIST_DIR/pki/issued/$CLIENT_ID.crt" ]; then
        echo "$(datef) Client with this id [$CLIENT_ID] already exists"
        exit 1
    else
        createConfig
    fi

    CONTENT_TYPE=application/text
    FILE_NAME=client.ovpn
    FILE_PATH="$CLIENT_PATH/$FILE_NAME"

    if (($#))
    then

        # Parse string into chars:
        # z    Zip user config
        # p    User password for the zip archive
        FLAGS=$1

        # Switch statement
        case $FLAGS in
            z)
                zipFiles "$CLIENT_PATH"

                CONTENT_TYPE=application/zip
                FILE_NAME=client.zip
                FILE_PATH="$CLIENT_PATH/$FILE_NAME"
                ;;
            zp)
                # (()) engaes arthimetic context
                if (($# < 2))
                then
                    echo "$(datef) Not enough arguments" && exit 1
                else
                    zipFilesWithPassword "$CLIENT_PATH" "$2"

                    CONTENT_TYPE=application/zip
                    FILE_NAME=client.zip
                    FILE_PATH="$CLIENT_PATH/$FILE_NAME"
                fi
                ;;
            o|n|np)
                    cat "$FILE_PATH"
                    exit 0
                ;;
            oz)
                zipFiles "$CLIENT_PATH" -q

                FILE_NAME=client.zip
                FILE_PATH="$CLIENT_PATH/$FILE_NAME"
                cat "$FILE_PATH"
                exit 0
                ;;
            ozp)
                if (($# < 2))
                then
                    echo "$(datef) Not enough arguments" && exit 1
                else
                    zipFilesWithPassword "$CLIENT_PATH" "$2" -q

                    FILE_NAME=client.zip
                    FILE_PATH="$CLIENT_PATH/$FILE_NAME"
                    cat "$FILE_PATH"
                    exit 0
                fi
                ;;
            *) echo "$(datef) Unknown parameters $FLAGS"
                ;;

        esac
    fi
    echo "$(datef) $FILE_PATH file has been generated"

    echo "$(datef) Config server started, download your $FILE_NAME config at http://$HOST_ADDR_INT:$HOST_CONF_PORT/"
    echo "$(datef) NOTE: After you download your client config, http server will be shut down!"

    { echo -ne "HTTP/1.1 200 OK\r\nContent-Length: $(wc -c <"$FILE_PATH")\r\nContent-Type: $CONTENT_TYPE\r\nContent-Disposition: attachment; fileName=\"$FILE_NAME\"\r\nAccept-Ranges: bytes\r\n\r\n"; cat "$FILE_PATH"; } | nc -w0 -l 8080

    echo "$(datef) Config http server has been shut down"
}

function resolvePublicIP() {
    # Privacy-focused IP resolution with fallback
    # Try multiple services in order for better reliability
    local resolved_ip=""

    # Try Cloudflare's icanhazip.com first (privacy-focused, no tracking)
    resolved_ip=$(curl -s --max-time 5 https://icanhazip.com 2>/dev/null | tr -d '[:space:]')

    if [[ -n "$resolved_ip" && "$resolved_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$resolved_ip"
        return 0
    fi

    # Fallback to AWS checkip service
    resolved_ip=$(curl -s --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]')

    if [[ -n "$resolved_ip" && "$resolved_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$resolved_ip"
        return 0
    fi

    # If both failed, return empty
    echo ""
    return 1
}

if [[ -n $HOST_ADDR ]]; then
    # HOST_ADDR is set: no need to contact any external service
    export HOST_ADDR_INT=$HOST_ADDR
else
    RESOLVED_HOST_ADDR=$(resolvePublicIP || true)
    if [[ -z "$RESOLVED_HOST_ADDR" ]]; then
        echo "$(datef) WARNING: could not resolve the public IP address; set HOST_ADDR explicitly" >&2
    fi
    export HOST_ADDR_INT=$RESOLVED_HOST_ADDR
fi

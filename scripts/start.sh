#!/bin/bash
set -eo pipefail

source ./functions.sh

SHORT=rnqs
LONG="regenerate,noop,quit,skip"
OPTS=$(getopt -a -n dockovpn --options $SHORT --longoptions $LONG -- "$@") || exit 1

eval set -- "$OPTS"

while :
do
  case "$1" in
    -r | --regenerate)
      REGENERATE="1"
      shift;
      ;;
    -n | --noop)
      NOOP="1"
      shift;
      ;;
    -q | --quit)
      QUIT="1"
      shift;
      ;;
    -s | --skip)
      SKIP="1"
      shift;
      ;;
    --)
      shift;
      break
      ;;
    *)
      echo "Unexpected option: $1"
      exit 1
      ;;
  esac
done

# Drop empty positional args (the image's default CMD is an empty string)
ARGS=()
for arg in "$@"; do
    [[ -n "$arg" ]] && ARGS+=("$arg")
done
set -- "${ARGS[@]}"

ADAPTER="${NET_ADAPTER:=eth0}"

case "$HOST_TUN_PROTOCOL" in
    udp|tcp) ;;
    *)
        echo "$(datef) ERROR: HOST_TUN_PROTOCOL must be 'udp' or 'tcp' (got '$HOST_TUN_PROTOCOL')"
        exit 1
        ;;
esac

mkdir -p /dev/net

if [ ! -c /dev/net/tun ]; then
    echo "$(datef) Creating tun/tap device."
    mknod /dev/net/tun c 10 200
fi

# Replace variables in ovpn config file
sed -i 's/%HOST_TUN_PROTOCOL%/'"$HOST_TUN_PROTOCOL"'/g' /etc/openvpn/server.conf

# IPv6 leak protection: give clients an IPv6 address inside the tunnel, redirect
# their IPv6 default route into it and answer every IPv6 packet with
# "unreachable" so nothing bypasses the VPN over IPv6.
# This only works when IPv6 is enabled inside the container.
if [[ "${BLOCK_IPV6,,}" == "true" || "$BLOCK_IPV6" == "1" ]]; then
    if [[ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)" == "0" ]]; then
        if ! grep -q '^server-ipv6' /etc/openvpn/server.conf; then
            sed -i 's/^push "redirect-gateway def1 bypass-dhcp"$/push "redirect-gateway def1 bypass-dhcp ipv6"/' /etc/openvpn/server.conf
            cat >> /etc/openvpn/server.conf <<'OVPN6'

# --- IPv6 leak protection (added by start.sh) ---
server-ipv6 fd4d:6f63:6b6f:7670::/64
block-ipv6
OVPN6
        fi
        echo "$(datef) IPv6 leak protection enabled (set BLOCK_IPV6=false to disable)"
    else
        echo "$(datef) WARNING: IPv6 is disabled inside the container, IPv6 leak protection can't be enabled."
        echo "$(datef)          Run the container with --sysctl net.ipv6.conf.all.disable_ipv6=0 to enable it."
    fi
fi

# Make sure the kernel forwards packets between tun0 and the adapter
if [[ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" != "1" ]]; then
    if ! sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1; then
        echo "$(datef) WARNING: net.ipv4.ip_forward is disabled and couldn't be enabled; VPN clients won't reach the internet."
    fi
fi

# Allow ${HOST_TUN_PROTOCOL} traffic on port 1194.
iptables -A INPUT -i "$ADAPTER" -p "$HOST_TUN_PROTOCOL" -m state --state NEW,ESTABLISHED --dport 1194 -j ACCEPT
iptables -A OUTPUT -o "$ADAPTER" -p "$HOST_TUN_PROTOCOL" -m state --state ESTABLISHED --sport 1194 -j ACCEPT

# Allow traffic on the TUN interface.
iptables -A INPUT -i tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -j ACCEPT
iptables -A OUTPUT -o tun0 -j ACCEPT

# Allow forwarding traffic only from the VPN.
iptables -A FORWARD -i tun0 -o "$ADAPTER" -s 10.8.0.0/24 -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$ADAPTER" -j MASQUERADE

cd "$APP_PERSIST_DIR"

LOCKFILE=.gen

# Regenerate certs only on the first start
if [ ! -f $LOCKFILE ]; then
    IS_INITIAL="1"
    test -d pki || REGENERATE="1"
    if [[ -n $REGENERATE ]]; then
        echo "$(datef) Generating PKI and DH parameters, this may take a while..."
        easyrsa --batch init-pki
        easyrsa --batch gen-dh
        # DH parameters created at /opt/Dockovpn_data/pki/dh.pem
        # Copy DH file
        cp pki/dh.pem /etc/openvpn
    fi

    easyrsa --batch build-ca nopass
    # CA creation complete and you may now import and sign cert requests.
    # Your new CA certificate file for publishing is at:
    # /opt/Dockovpn_data/pki/ca.crt

    easyrsa --batch gen-req MyReq nopass
    # Keypair and certificate request completed. Your files are:
    # req: /opt/Dockovpn_data/pki/reqs/MyReq.req
    # key: /opt/Dockovpn_data/pki/private/MyReq.key

    easyrsa --batch sign-req server MyReq
    # Certificate created at: /opt/Dockovpn_data/pki/issued/MyReq.crt

    openvpn --genkey secret ta.key
    chmod 600 ta.key

    easyrsa --batch --days="$CRL_DAYS" gen-crl

    touch $LOCKFILE
fi

# Copy server keys and certificates
cp pki/dh.pem pki/ca.crt pki/issued/MyReq.crt pki/private/MyReq.key pki/crl.pem ta.key /etc/openvpn
chmod 600 /etc/openvpn/MyReq.key /etc/openvpn/ta.key
# The CRL is re-read on every client connection after OpenVPN dropped privileges
chmod 644 /etc/openvpn/crl.pem

# Runtime state written by OpenVPN after dropping privileges to nobody
mkdir -p /var/lib/openvpn
chown nobody:nobody /var/lib/openvpn
chmod 700 /var/lib/openvpn

cd "$APP_INSTALL_PATH"

# Print app version
getVersionFull

OPENVPN_PID=""

if ! [[ -n $NOOP ]]; then
    openvpn --config /etc/openvpn/server.conf &
    OPENVPN_PID=$!

    if [[ -n $IS_INITIAL ]]; then
        # By some strange reason we need to do echo command to get to the next command
        echo " "

        if ! [[ -n $SKIP ]]; then
          # Generate client config (own subshell without set -e: the
          # generator handles its own errors and must not be killed by SIGPIPE)
          ( set +e +o pipefail; generateClientConfig "$@" ) &
        else
          echo "$(datef) SKIP is set: skipping client generation"
        fi
    else
      echo "$(datef) Data exist: skipping client generation"
    fi
fi

if ! [[ -n $QUIT ]]; then
    if [[ -n $OPENVPN_PID ]]; then
        # Keep the container alive only while the VPN server is running
        wait "$OPENVPN_PID"
    else
        tail -f /dev/null
    fi
fi

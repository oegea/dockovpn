#!/usr/bin/env bash
# End-to-end tests for the dockovpn image.
# Usage: tests/e2e.sh <image>   (e.g. make test, or tests/e2e.sh oriolegea/dockovpn:local)
# Requires: docker, unzip. Needs internet access (public IP resolution and NAT check).
IMG="${1:-oriolegea/dockovpn:local}"
NET=dockovpn-e2e
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  [PASS] $*"; }
fail() { FAIL=$((FAIL+1)); echo "  [FAIL] $*"; }
check() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$desc"; else fail "$desc"; fi; }
cleanup() { docker rm -f dv-server dv-server2 dv-client dv-tcp dv-tcp-client dv-v6 dv-v6-client dv-flags >/dev/null 2>&1; docker volume rm dv-vol dv-vol-r >/dev/null 2>&1; docker network rm $NET >/dev/null 2>&1; }
cleanup; trap cleanup EXIT
docker network create $NET >/dev/null
CLIENT_RUN="docker run -d --cap-add=NET_ADMIN --network $NET --entrypoint sh"
export -f wait_log 2>/dev/null; wait_log() { # container pattern timeout
  for i in $(seq 1 "$3"); do docker logs "$1" 2>&1 | grep -q "$2" && return 0; sleep 1; done; return 1; }
export -f wait_log

echo "### 1. Server start (UDP, default, IPv6 disabled in container)"
docker volume create dv-vol >/dev/null
docker run -d --name dv-server --cap-add=NET_ADMIN --network $NET -v dv-vol:/opt/Dockovpn_data -e HOST_ADDR=dv-server "$IMG" >/dev/null
check "server reaches 'Initialization Sequence Completed'" wait_log dv-server "Initialization Sequence Completed" 90
check "config http server started" wait_log dv-server "Config server started" 30
check "no 'Options error' in server log" bash -c '! docker logs dv-server 2>&1 | grep -q "Options error"'
check "IPv6 warning logged when IPv6 unavailable" bash -c 'docker logs dv-server 2>&1 | grep -q "IPv6 is disabled inside the container"'
check "openvpn runs as nobody" bash -c 'docker exec dv-server ps -o user,args | grep "openvpn --config" | grep -q "^nobody"'
check "server key is 4096-bit RSA" bash -c 'docker exec dv-server openssl x509 -in /etc/openvpn/MyReq.crt -noout -text | grep -q "Public-Key: (4096 bit)"'
check "CA key is 4096-bit RSA" bash -c 'docker exec dv-server openssl x509 -in /opt/Dockovpn_data/pki/ca.crt -noout -text | grep -q "Public-Key: (4096 bit)"'
check "server key has 0600 perms" bash -c '[ "$(docker exec dv-server stat -c %a /etc/openvpn/MyReq.key)" = "600" ]'
check "ta.key has 0600 perms" bash -c '[ "$(docker exec dv-server stat -c %a /etc/openvpn/ta.key)" = "600" ]'
check "no reneg-sec 0 in server.conf" bash -c '! docker exec dv-server grep -q "reneg-sec 0" /etc/openvpn/server.conf'
check "ECDHE-only key exchange (dh none, no dh.pem)" bash -c 'docker exec dv-server grep -q "^dh none" /etc/openvpn/server.conf && ! docker exec dv-server test -e /etc/openvpn/dh.pem && ! docker exec dv-server test -e /opt/Dockovpn_data/pki/dh.pem'
check "version.sh works" bash -c 'docker exec dv-server ./version.sh | grep -q "Dockovpn v"'

echo "### 2. Client downloads config over HTTP and connects"
$CLIENT_RUN --name dv-client "$IMG" -c 'sleep 3600' >/dev/null
check "client downloads client.ovpn" docker exec dv-client sh -c 'wget -q -O /tmp/client.ovpn http://dv-server:8080/ && grep -q "<key>" /tmp/client.ovpn && grep -q "^remote dv-server 1194" /tmp/client.ovpn'
check "http server shut down after download" wait_log dv-server "Config http server has been shut down" 10
check "client config contains data-ciphers and no cipher line" docker exec dv-client sh -c 'grep -q "^data-ciphers AES-256-GCM" /tmp/client.ovpn && ! grep -q "^cipher " /tmp/client.ovpn'
check "client cert is 4096-bit" docker exec dv-client sh -c 'sed -n "/<cert>/,/<\/cert>/p" /tmp/client.ovpn | openssl x509 -noout -text | grep -q "(4096 bit)"'
docker exec dv-client sh -c 'mkdir -p /dev/net; [ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200; openvpn --config /tmp/client.ovpn --log /tmp/client.log --daemon'
check "client connects" bash -c 'for i in $(seq 1 30); do docker exec dv-client grep -q "Initialization Sequence Completed" /tmp/client.log && exit 0; sleep 1; done; docker exec dv-client cat /tmp/client.log; exit 1'
check "data channel is AES-256-GCM" docker exec dv-client grep -q "Data Channel: cipher 'AES-256-GCM'" /tmp/client.log
check "control channel is TLS 1.3 or 1.2" docker exec dv-client grep -qE "Control Channel: TLSv1\.[23]" /tmp/client.log
check "key agreement is elliptic-curve (ECDHE / X25519 / MLKEM hybrid)" docker exec dv-client grep -qE "key agreement: (X25519|secp|prime|P-[0-9]|ECDH)" /tmp/client.log
check "client has topology subnet address" docker exec dv-client sh -c 'ip addr show dev tun0 | grep -q "10.8.0.2/24"'
check "default route redirected into tunnel" docker exec dv-client sh -c 'ip route | grep -q "^0.0.0.0/1 via 10.8.0.1 dev tun0"'
check "ping server through tunnel" docker exec dv-client ping -c 2 -W 3 10.8.0.1
check "internet reachable through tunnel (NAT/forwarding)" docker exec dv-client sh -c 'ip route get 1.1.1.1 | grep -q tun0 && wget -q -T 15 -O /dev/null https://icanhazip.com'
check "server status log (written as nobody) lists the client" bash -c 'for i in $(seq 1 75); do docker exec dv-server grep -q "10.8.0.2" /var/lib/openvpn/openvpn-status.log && exit 0; sleep 1; done; exit 1'

echo "### 2b. Legacy client profile (generated by older versions: 'cipher AES-256-GCM', no data-ciphers)"
docker exec dv-client sh -c 'sed -e "/^data-ciphers/d" -e "/^auth-nocache/d" -e "s/^auth SHA512/cipher AES-256-GCM\nauth SHA512/" /tmp/client.ovpn > /tmp/legacy.ovpn && grep -q "^cipher AES-256-GCM" /tmp/legacy.ovpn && ! grep -q "^data-ciphers" /tmp/legacy.ovpn'
docker exec dv-client sh -c 'openvpn --config /tmp/legacy.ovpn --dev tun2 --pull-filter ignore redirect-gateway --log /tmp/legacy.log --daemon'
check "legacy-style client profile still connects" bash -c 'for i in $(seq 1 30); do docker exec dv-client grep -q "Initialization Sequence Completed" /tmp/legacy.log && exit 0; sleep 1; done; docker exec dv-client cat /tmp/legacy.log; exit 1'
check "legacy-style client negotiates AES-256-GCM" docker exec dv-client grep -q "Data Channel: cipher 'AES-256-GCM'" /tmp/legacy.log
docker exec dv-client sh -c 'pkill -f "legacy.ovpn"' >/dev/null 2>&1

echo "### 3. Client management commands"
check "genclient.sh n named" bash -c 'docker exec dv-server ./genclient.sh n alice | grep -q "<key>"'
check "genclient.sh o prints config" bash -c 'docker exec dv-server ./genclient.sh o | grep -q "^;client-id "'
check "genclient.sh oz prints zip" bash -c 'docker exec dv-server ./genclient.sh oz > /tmp/dv-c.zip && unzip -l /tmp/dv-c.zip | grep -q client.ovpn'
check "genclient.sh ozp prints encrypted zip" bash -c 'docker exec dv-server ./genclient.sh ozp s3cret > /tmp/dv-cp.zip && docker exec -i dv-server sh -c "cat > /tmp/x.zip && 7z t -ps3cret /tmp/x.zip" < /tmp/dv-cp.zip | grep -q "Everything is Ok" && ! (docker exec -i dv-server sh -c "cat > /tmp/y.zip && 7z t -pwrong /tmp/y.zip" < /tmp/dv-cp.zip | grep -q "Everything is Ok")'
docker exec -d dv-server ./genclient.sh z
check "genclient.sh z serves zip over http" bash -c 'sleep 4; docker exec dv-client wget -q -O /tmp/c.zip http://dv-server:8080/ && docker exec dv-client 7z l /tmp/c.zip | grep -q client.ovpn'
check "client dirs are 0700 and files 0600" bash -c '[ "$(docker exec dv-server stat -c %a /opt/Dockovpn_data/clients/alice)" = "700" ] && [ "$(docker exec dv-server stat -c %a /opt/Dockovpn_data/clients/alice/client.ovpn)" = "600" ]'
check "listconfigs.sh lists alice" bash -c 'docker exec dv-server ./listconfigs.sh | grep -qx alice'
check "getconfig.sh alice" bash -c 'docker exec dv-server ./getconfig.sh alice | grep -q "<key>"'
check "getconfig.sh unknown fails" bash -c '! docker exec dv-server ./getconfig.sh nobodyhere >/dev/null 2>&1'
check "getconfig.sh path traversal rejected" bash -c 'docker exec dv-server ./getconfig.sh "../../etc/passwd" 2>&1 | grep -q "invalid client id"'
check "genclient.sh with invalid id rejected" bash -c 'docker exec dv-server ./genclient.sh n "bad id;rm" 2>&1 | grep -q "invalid client id"'
check "genclient.sh duplicate id rejected" bash -c 'docker exec dv-server ./genclient.sh n alice 2>&1 | grep -q "already exists"'
check "rmclient.sh unknown fails" bash -c '! docker exec dv-server ./rmclient.sh ghost >/dev/null 2>&1'

echo "### 4. Revocation"
docker exec dv-server ./getconfig.sh alice > /tmp/dv-alice.ovpn
docker cp /tmp/dv-alice.ovpn dv-client:/tmp/alice.ovpn
check "rmclient.sh alice" bash -c 'docker exec dv-server ./rmclient.sh alice 2>&1 | grep -q "has been revoked"'
check "revoked cert is in CRL" bash -c 'docker exec dv-server sh -c "openssl crl -in /etc/openvpn/crl.pem -noout -text | grep -q \"Serial Number\""'
docker exec dv-client sh -c 'openvpn --config /tmp/alice.ovpn --dev tun1 --pull-filter ignore redirect-gateway --log /tmp/alice.log --daemon'
check "revoked client is rejected by server" bash -c 'for i in $(seq 1 20); do docker logs dv-server 2>&1 | grep -qiE "CRL CHECK FAILED|certificate revoked" && exit 0; sleep 1; done; exit 1'
check "revoked client never completes" bash -c '! docker exec dv-client grep -q "Initialization Sequence Completed" /tmp/alice.log'
check "regenerating a revoked id is refused" bash -c 'docker exec dv-server ./genclient.sh n alice 2>&1 | grep -q "already exists"'

echo "### 5. Persistence + restart"
check "docker stop exits promptly (SIGTERM handled)" bash -c 'docker stop -t 15 dv-server >/dev/null && [ "$(docker inspect -f {{.State.ExitCode}} dv-server)" = "143" ]'
# Simulate a volume created by an older version, which also contains DH parameters
docker run --rm -v dv-vol:/d --entrypoint sh "$IMG" -c 'openssl dhparam -out /d/pki/dh.pem 512 >/dev/null 2>&1 && test -s /d/pki/dh.pem' >/dev/null 2>&1 || fail "could not create legacy dh.pem in volume"
docker run -d --name dv-server2 --cap-add=NET_ADMIN --network $NET -v dv-vol:/opt/Dockovpn_data -e HOST_ADDR=dv-server2 --network-alias dv-server "$IMG" >/dev/null
check "second start skips generation" wait_log dv-server2 "Data exist: skipping client generation" 60
check "second start completes init (legacy dh.pem in volume is ignored)" wait_log dv-server2 "Initialization Sequence Completed" 60
check "existing client reconnects after restart" bash -c 'docker exec dv-client sh -c "pkill openvpn; sleep 1; openvpn --config /tmp/client.ovpn --log /tmp/client2.log --daemon"; for i in $(seq 1 30); do docker exec dv-client grep -q "Initialization Sequence Completed" /tmp/client2.log && exit 0; sleep 1; done; exit 1'
check "revocation persists across restart (alice still rejected)" bash -c 'docker exec dv-client sh -c "openvpn --config /tmp/alice.ovpn --dev tun1 --pull-filter ignore redirect-gateway --log /tmp/alice2.log --daemon"; for i in $(seq 1 20); do docker logs dv-server2 2>&1 | grep -qiE "CRL CHECK FAILED|certificate revoked" && exit 0; sleep 1; done; exit 1'
docker rm -f dv-server2 dv-client >/dev/null

echo "### 6. TCP mode"
docker run -d --name dv-tcp --cap-add=NET_ADMIN --network $NET -e HOST_ADDR=dv-tcp -e HOST_TUN_PROTOCOL=tcp "$IMG" -s >/dev/null
check "tcp server completes init" wait_log dv-tcp "Initialization Sequence Completed" 90
check "-s skips client generation" wait_log dv-tcp "SKIP is set" 10
check "server.conf has proto tcp" docker exec dv-tcp grep -q "^proto tcp" /etc/openvpn/server.conf
$CLIENT_RUN --name dv-tcp-client "$IMG" -c 'sleep 3600' >/dev/null
docker exec dv-tcp ./genclient.sh o > /tmp/dv-tcp.ovpn
docker cp /tmp/dv-tcp.ovpn dv-tcp-client:/tmp/c.ovpn
check "tcp client config has proto tcp" grep -q "^proto tcp" /tmp/dv-tcp.ovpn
docker exec dv-tcp-client sh -c 'mkdir -p /dev/net; [ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200; openvpn --config /tmp/c.ovpn --log /tmp/c.log --daemon'
check "tcp client connects" bash -c 'for i in $(seq 1 30); do docker exec dv-tcp-client grep -q "Initialization Sequence Completed" /tmp/c.log && exit 0; sleep 1; done; docker exec dv-tcp-client cat /tmp/c.log; exit 1'
check "tcp: ping through tunnel" docker exec dv-tcp-client ping -c 2 -W 3 10.8.0.1
docker rm -f dv-tcp dv-tcp-client >/dev/null

echo "### 7. IPv6 leak protection"
docker run -d --name dv-v6 --cap-add=NET_ADMIN --network $NET --sysctl net.ipv6.conf.all.disable_ipv6=0 -e HOST_ADDR=dv-v6 "$IMG" -s >/dev/null
check "v6 server completes init" wait_log dv-v6 "Initialization Sequence Completed" 90
check "IPv6 leak protection enabled logged" wait_log dv-v6 "IPv6 leak protection enabled" 10
check "server.conf has server-ipv6/block-ipv6/redirect ipv6" docker exec dv-v6 sh -c 'grep -q "^server-ipv6" /etc/openvpn/server.conf && grep -q "^block-ipv6" /etc/openvpn/server.conf && grep -q "redirect-gateway def1 bypass-dhcp ipv6" /etc/openvpn/server.conf'
docker run -d --cap-add=NET_ADMIN --network $NET --sysctl net.ipv6.conf.all.disable_ipv6=0 --entrypoint sh --name dv-v6-client "$IMG" -c 'sleep 3600' >/dev/null
docker exec dv-v6 ./genclient.sh o > /tmp/dv-v6.ovpn
docker cp /tmp/dv-v6.ovpn dv-v6-client:/tmp/c.ovpn
docker exec dv-v6-client sh -c 'mkdir -p /dev/net; [ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200; ip -6 route add default via fe80::1 dev eth0 2>/dev/null; openvpn --config /tmp/c.ovpn --log /tmp/c.log --daemon'
check "v6 client connects" bash -c 'for i in $(seq 1 30); do docker exec dv-v6-client grep -q "Initialization Sequence Completed" /tmp/c.log && exit 0; sleep 1; done; docker exec dv-v6-client cat /tmp/c.log; exit 1'
check "client got IPv6 address on tun0" docker exec dv-v6-client sh -c 'ip -6 addr show dev tun0 | grep -q "fd4d:6f63:6b6f:7670:"'
check "client global IPv6 routes (2000::/4, 3000::/4, ::/3, fc00::/7) go via tun0" docker exec dv-v6-client sh -c 'ip -6 route | grep -E "^2000::/4 .*dev tun0" && ip -6 route | grep -E "^3000::/4 .*dev tun0" && ip -6 route | grep -E "^::/3 .*dev tun0" && ip -6 route | grep -E "^fc00::/7 .*dev tun0"'
check "IPv6 traffic is blocked (no leak, unreachable)" bash -c '! docker exec dv-v6-client ping -6 -c 1 -W 3 2606:4700:4700::1111 >/dev/null 2>&1'
check "IPv6 traffic routed via tun0" docker exec dv-v6-client sh -c 'ip -6 route get 2606:4700:4700::1111 | grep -q tun0'
check "IPv4 still works through tunnel" docker exec dv-v6-client ping -c 2 -W 3 10.8.0.1
docker rm -f dv-v6 dv-v6-client >/dev/null
docker run -d --name dv-v6 --cap-add=NET_ADMIN --network $NET --sysctl net.ipv6.conf.all.disable_ipv6=0 -e BLOCK_IPV6=false -e HOST_ADDR=dv-v6 "$IMG" -s >/dev/null
check "BLOCK_IPV6=false disables it" bash -c 'wait_log dv-v6 "Initialization Sequence Completed" 90 && ! docker exec dv-v6 grep -q "^server-ipv6" /etc/openvpn/server.conf'
docker rm -f dv-v6 >/dev/null

echo "### 8. Flags & validation"
check "-q quits after init with exit 0" bash -c 'docker run --rm --cap-add=NET_ADMIN -e HOST_ADDR=x "$0" -q -s > /tmp/dv-q.log 2>&1 && grep -q "Dockovpn v" /tmp/dv-q.log' "$IMG"
check "-n does not start openvpn" bash -c 'docker run -d --name dv-flags --cap-add=NET_ADMIN -e HOST_ADDR=x "$0" -n >/dev/null; sleep 20; ! docker exec dv-flags pgrep -x openvpn >/dev/null && docker exec dv-flags pgrep -f "tail -f" >/dev/null' "$IMG"
docker rm -f dv-flags >/dev/null
check "invalid HOST_TUN_PROTOCOL rejected" bash -c '! docker run --rm --cap-add=NET_ADMIN -e HOST_ADDR=x -e HOST_TUN_PROTOCOL=sctp "$0" > /tmp/dv-p.log 2>&1 && grep -q "must be" /tmp/dv-p.log' "$IMG"
docker volume create dv-vol-r >/dev/null
check "-r still accepted and generates a fresh PKI (no DH)" bash -c 'docker run --rm --cap-add=NET_ADMIN -e HOST_ADDR=x -v dv-vol-r:/opt/Dockovpn_data "$0" -r -q -s > /tmp/dv-r.log 2>&1 && grep -q "Generating PKI" /tmp/dv-r.log && docker run --rm -v dv-vol-r:/opt/Dockovpn_data --entrypoint sh "$0" -c "test -f /opt/Dockovpn_data/pki/ca.crt && test -f /opt/Dockovpn_data/.gen && ! test -e /opt/Dockovpn_data/pki/dh.pem"' "$IMG"
check "interrupted first start (pki without .gen) recovers on next start" bash -c 'docker volume rm -f dv-vol-i >/dev/null 2>&1; docker volume create dv-vol-i >/dev/null; docker run --rm -v dv-vol-i:/opt/Dockovpn_data --entrypoint sh "$0" -c "cd /opt/Dockovpn_data && easyrsa --batch init-pki >/dev/null 2>&1" && docker run --rm --cap-add=NET_ADMIN -e HOST_ADDR=x -v dv-vol-i:/opt/Dockovpn_data "$0" -q -s > /tmp/dv-i.log 2>&1 && grep -q "Dockovpn v" /tmp/dv-i.log; rc=$?; docker volume rm -f dv-vol-i >/dev/null 2>&1; exit $rc' "$IMG"
check "container exits when openvpn dies" bash -c 'docker run -d --name dv-flags --cap-add=NET_ADMIN -e HOST_ADDR=x "$0" -s >/dev/null; wait_log dv-flags "Initialization Sequence Completed" 90; docker exec dv-flags pkill -x openvpn; sleep 5; [ "$(docker inspect -f {{.State.Running}} dv-flags)" = "false" ]' "$IMG"
docker rm -f dv-flags >/dev/null

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

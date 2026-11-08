# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DockOvpn is a stateless OpenVPN server Docker container that provides quick, out-of-the-box VPN functionality. The project is designed to start in seconds without requiring persistent storage, though it supports optional volume persistence.

## Build Commands

### Building Docker Images

```bash
# Build production version with auto-regenerated DH parameters
# Uses version from VERSION file with "-regen-dh" suffix
make build

# Build manual release version (uses VERSION file as-is)
make build-release

# Build for local testing
make build-local

# Build development version (tagged as "dev")
make build-dev

# Build test version (tagged as "test")
make build-test

# Build branch-specific version (tagged with sanitized branch name)
make build-branch

# Publish branch build to Docker Hub
make publish-branch
```

### Running

```bash
# Run container with Makefile
make run

# Run container directly with helper script
./run.sh [OPTIONS]

# Run with docker-compose
docker-compose up -d
```

### Testing

```bash
# Build the local image and run the end-to-end suite (tests/e2e.sh):
# UDP/TCP connection, NAT, client commands, revocation, persistence, IPv6 leak protection, flags
make test
```

### Cleanup

```bash
# Remove test reports and shared volumes
make clean
```

## Architecture

### Container Initialization Flow

The container follows a precise initialization sequence managed by `scripts/start.sh`:

1. **Option Parsing**: Supports `-r/--regenerate`, `-n/--noop`, `-q/--quit`, `-s/--skip` flags
2. **TUN Device Setup**: Creates `/dev/net/tun` if not present
3. **OpenVPN Configuration**: Replaces `%HOST_TUN_PROTOCOL%` placeholder in `/etc/openvpn/server.conf`; when `BLOCK_IPV6=true` and IPv6 is enabled in the container, appends `server-ipv6`/`block-ipv6` and pushes `redirect-gateway ipv6` (IPv6 leak protection)
4. **iptables Configuration**: Sets up NAT and forwarding rules for VPN traffic (also makes sure `net.ipv4.ip_forward` is on)
5. **PKI Generation** (first run or with `-r`):
   - Initializes PKI and generates DH parameters using easy-rsa
   - Builds CA, server certificate request, and signs server certificate
   - Generates TLS auth key and CRL
   - Creates `.gen` lockfile to prevent re-initialization
6. **Certificate Deployment**: Copies PKI files to `/etc/openvpn/`
7. **VPN Server Start**: Launches OpenVPN in background (unless `-n/--noop`); OpenVPN drops privileges to `nobody` after init and writes runtime state to `/var/lib/openvpn`. The container exits if the OpenVPN process dies.
8. **Client Config Generation**: On initial run (unless `-s/--skip`), generates first client config via HTTP server

### Directory Structure

- `/opt/Dockovpn/` - Application install path (`APP_INSTALL_PATH`)
- `/opt/Dockovpn_data/` - Persistent data directory (`APP_PERSIST_DIR`)
  - `pki/` - PKI infrastructure (CA, certificates, DH params)
  - `clients/` - Generated client configurations organized by client ID
  - `.gen` - Lockfile indicating PKI initialization complete
- `/etc/openvpn/` - Runtime OpenVPN configuration and certificates
- `scripts/` - Shell scripts for container management
- `config/` - Template configurations

### Key Scripts

- `start.sh` - Container entrypoint; handles initialization and server startup
- `functions.sh` - Shared functions library:
  - `generateClientConfig()` - Creates client certificates and `.ovpn` files
  - `createConfig()` - Generates PKI for specific client
  - `removeConfig()` - Revokes client certificate and updates CRL
  - `listConfigs()` - Lists all generated client IDs
  - `getConfig()` - Retrieves existing client config
  - `zipFiles()` / `zipFilesWithPassword()` - Archive client configs
- `genclient.sh` - Wrapper for generating client configurations
- `rmclient.sh` - Wrapper for revoking client access
- `listconfigs.sh` - Wrapper for listing clients
- `getconfig.sh` - Wrapper for retrieving client configs
- `version.sh` - Outputs version information

### Client Configuration Generation

Client configs can be generated with various flags:

- Plain generation: `docker exec dockovpn ./genclient.sh`
- With zip: `docker exec dockovpn ./genclient.sh z`
- With password-protected zip: `docker exec dockovpn ./genclient.sh zp <password>`
- Output to stdout: `docker exec dockovpn ./genclient.sh o > client.ovpn`
- Custom profile name: `docker exec dockovpn ./genclient.sh n <profile_name>`
- Password-protected connection: `docker exec dockovpn ./genclient.sh np <profile_name>`

Client configs embed all certificates inline within the `.ovpn` file for portability.

### Environment Variables

Configured via Docker `-e` flags:

- `NET_ADAPTER` - Host network adapter (default: `eth0`)
- `HOST_ADDR` - Host address override (auto-resolved via privacy-focused services if unset)
- `HOST_TUN_PORT` - VPN tunnel port advertised to clients (default: `1194`)
- `HOST_TUN_PROTOCOL` - Tunnel protocol `udp` or `tcp` (default: `udp`)
- `HOST_CONF_PORT` - HTTP port for client config download (default: `80`)
- `CRL_DAYS` - CRL expiration days (default: `3650`)
- `BLOCK_IPV6` - IPv6 leak protection, needs IPv6 enabled in the container via `--sysctl net.ipv6.conf.all.disable_ipv6=0` (default: `true`)
- `EASYRSA_KEY_SIZE` - RSA key size used by easy-rsa for CA/server/client keys and DH (default: `4096`)

### Security Configuration

OpenVPN server settings (config/server.conf):

- Data channel: AEAD only (`data-ciphers AES-256-GCM:CHACHA20-POLY1305`), SHA512 auth; no CBC fallback
- TLS version minimum: 1.2, TLS 1.2 suites restricted to ECDHE + AEAD (`tls-cipher`)
- TLS authentication using ta.key (`tls-auth`, key-direction 0 server / 1 client)
- `remote-cert-tls client` on the server, `remote-cert-tls server` on the client
- Certificate Revocation List (CRL) verification enabled
- `user nobody` / `group nobody`, `persist-tun`; `topology subnet` set explicitly
- 4096-bit RSA keys for all certificates (`EASYRSA_KEY_SIZE`)
- DNS pushed to clients: Cloudflare DNS (1.1.1.1, 1.0.0.1)
- Client ids passed to `genclient.sh`, `rmclient.sh` and `getconfig.sh` are validated (`[A-Za-z0-9][A-Za-z0-9_.@-]{0,63}`)
- Do not add `reneg-sec 0`: it disables periodic re-keying

### Client Revocation

Revoking a client permanently blacklists that certificate/profile name. Attempting to regenerate a client with the same name after revocation will result in an error. This is by design to maintain security.

## Release Process

Follow the detailed steps in `docs/RELEASE_GUIDELINE.md`:

1. Create `release-x.y.z` branch from master
2. Update `VERSION` file and `CHANGELOG.md`
3. Commit with message "Preparing release x.y.z"
4. Merge to `releases` branch
5. Create GitHub release with tag `vx.y.z` from `releases` branch
6. Automated Docker Hub build triggers on release creation
7. Merge `releases` back to `master` via PR

## Version Tagging

Docker tags follow specific conventions:

- `latest` - Most recent build (either stable or regen-dh)
- `vX.Y.Z` - Fixed release version
- `vX.Y.Z-regen-dh` - Hourly regenerated with fresh DH parameters for enhanced security
- `dev` - Latest development build from master branch

## Development Notes

- The project uses Alpine Linux 3.24.4 as the base image (OpenVPN 2.7, Easy-RSA 3.2); `apk upgrade` runs at build time so the base layer gets security fixes
- OpenVPN and easy-rsa are core dependencies
- The container requires `--cap-add=NET_ADMIN` capability for TUN device creation and iptables management
- Host address resolution uses privacy-focused services with fallback: tries Cloudflare's icanhazip.com first, then AWS checkip.amazonaws.com if needed
- HTTP config server (port 8080 internal) shuts down automatically after first client config download
- Container uses `dumb-init` as PID 1 to handle signals properly

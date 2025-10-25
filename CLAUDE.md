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

### Testing

```bash
# Run full integration test suite
# Uses alekslitvinenk/dockovpn-it:1.1.0 testing container
# Test reports saved to ./target/test-reports (configurable via TESTS_REPORT env var)
make test

# Run tests for branch builds (for macOS/Windows with Docker Desktop)
make test-branch
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
3. **OpenVPN Configuration**: Replaces `%HOST_TUN_PROTOCOL%` placeholder in `/etc/openvpn/server.conf`
4. **iptables Configuration**: Sets up NAT and forwarding rules for VPN traffic
5. **PKI Generation** (first run or with `-r`):
   - Initializes PKI and generates DH parameters using easy-rsa
   - Builds CA, server certificate request, and signs server certificate
   - Generates TLS auth key and CRL
   - Creates `.gen` lockfile to prevent re-initialization
6. **Certificate Deployment**: Copies PKI files to `/etc/openvpn/`
7. **VPN Server Start**: Launches OpenVPN in background (unless `-n/--noop`)
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

### Security Configuration

OpenVPN server settings (config/server.conf):

- Cipher: AES-256-GCM with SHA512 auth
- TLS version minimum: 1.2
- TLS authentication using ta.key
- Certificate Revocation List (CRL) verification enabled
- DNS pushed to clients: OpenDNS (208.67.222.222, 208.67.220.220)

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

- The project uses Alpine Linux 3.14.1 as the base image
- OpenVPN and easy-rsa are core dependencies
- The container requires `--cap-add=NET_ADMIN` capability for TUN device creation and iptables management
- Host address resolution uses privacy-focused services with fallback: tries Cloudflare's icanhazip.com first, then AWS checkip.amazonaws.com if needed
- HTTP config server (port 8080 internal) shuts down automatically after first client config download
- Container uses `dumb-init` as PID 1 to handle signals properly

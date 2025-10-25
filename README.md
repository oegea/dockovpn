# 🔐DockOvpn

[![Docker Pulls](https://img.shields.io/docker/pulls/oriolegea/dockovpn.svg)](https://hub.docker.com/r/oriolegea/dockovpn/)
![GitHub](https://img.shields.io/github/license/oegea/dockovpn)

> **Note:** This is a maintained fork of the [original dockovpn project](https://github.com/dockovpn/dockovpn) by [alekslitvinenk](https://github.com/alekslitvinenk), created to keep the software secure and up-to-date with the latest dependencies and security patches.
>
> **⚠️ Important:** The original project may be outdated and should be used with caution unless updated. This fork takes a different architectural approach to IP detection, using established infrastructure providers (Cloudflare, AWS) rather than a dedicated service. This is a preventive privacy measure reflecting the maintainer's personal comfort level—not a criticism of the original implementation. See our [Privacy Policy](https://github.com/oegea/dockovpn/blob/master/PRIVACY_POLICY.md) for details.

Out of the box stateless VPN server docker image which starts in just a few seconds and doesn't require persistent storage. To get it running,  just copy & paste the snippet below and follow instructions in your terminal:

```bash
docker run -it --rm --cap-add=NET_ADMIN \
-p 1194:1194/udp -p 80:8080/tcp \
--name dockovpn oriolegea/dockovpn
```

To get more detailed information, go to [Quick Start](#-quick-start) tutorial.

## Contributing

This is a community-maintained fork focused on security and keeping dependencies up-to-date. If you'd like to contribute:
- Submit pull requests with improvements or security fixes
- Report issues on [GitHub](https://github.com/oegea/dockovpn/issues)

## Content

[Resources](#resources) \
[Container properties](#container-properties) \
[Quick Start](#-quick-start) \
[Automated Deployment with GitHub Actions](#-automated-deployment-with-github-actions) \
[Persisting configuration](#persisting-configuration) \
[Alternative way. Run with docker-compose](#alternative-way-run-with-docker-compose) \
[Other resources](#other-resources)

## Resources

| Name | URL |
| :--: | :-----: |
| GitHub | <https://github.com/oegea/dockovpn> |
| Docker Hub | <https://hub.docker.com/r/oriolegea/dockovpn> |

## Container properties

### Docker Tags

| Tag    | Description |
| :----: | :---------: |
| `latest` | This tag is added to every newly built version be that `v#.#.#` or `v#.#.#-regen-dh` |
| `v#.#.#` | Standard fixed release version, where {1} is _major version_, {2} - _minor_ and {3} is a _patch_. For instance, `v1.1.0` |
| `v#.#.#-regen-dh` | Release version with newly generated Deffie Hellman security file. In order to keep security high this version is generated every hour. Tag example - `v1.1.0-regen-dh` |
| `dev` | Development build which contains the most recent changes from the active development branch (master) |

### Environment variables

| Variable | Description | Default value |
| :------: | :---------: | :-----------: |
| NET_ADAPTER | Network adapter to use on the host machine | eth0 |
| HOST_ADDR | Host address override if the resolved address doesn't work | localhost |
| HOST_TUN_PORT | Tunnel port to advertise in the client config file | 1194 |
| HOST_TUN_PROTOCOL | Tunnel protocol (`tcp` or `udp`) | udp |
| HOST_CONF_PORT | HTTP port on the host machine to download the client config file | 80 |
| CRL_DAYS | CRL days until expiration, i.e. invalid for revocation checking | 3650 |

**⚠️ Note:** In the provided code snippet we advertise the configuration suitable for the most users. We don't recommend setting custom
NET_ADAPTER and HOST_ADDR unless you absolutely have to. Now host address is resolved automatically when container starts..
More often you'd like to customize HOST_TUN_PORT, HOST_CONF_PORT or HOST_TUN_PROTOCOL. If this is the case, use the snippet below (dont forget to replace `<custom port>` and `<custom protocol>`  with your values):

```shell
DOCKOVPN_CONFIG_PORT=<custom port>
DOCKOVPN_TUNNEL_PORT=<custom port>
DOCKOVPN_TUNNEL_PROTOCOL=<custom protocol>
docker run -it --rm --cap-add=NET_ADMIN \
-p $DOCKOVPN_TUNNEL_PORT:1194/$DOCKOVPN_TUNNEL_PROTOCOL -p $DOCKOVPN_CONFIG_PORT:8080/tcp \
-e HOST_CONF_PORT="$DOCKOVPN_CONFIG_PORT" \
-e HOST_TUN_PORT="$DOCKOVPN_TUNNEL_PORT" \
-e HOST_TUN_PROTOCOL="$DOCKOVPN_TUNNEL_PROTOCOL" \
--name dockovpn oriolegea/dockovpn
```

### Container options

| Short name | Long name | Description |
| :-: | :---: | :-----: |
| `-r` | `--regenerate` | Regenerates PKI and DH file |
| `-n` | `--noop` | Initialise container, but don's start VPN server |
| `-q` | `--quit` | Quit after container was initialized |
| `-s` | `--skip` | Skip client generation on first start |

**⚠️ Note:** We strongly recommend always run your container with `-r` option, even though it will take container a bit longer to start. In future releases we will apply this option by default:

```bash
docker run -it --rm --cap-add=NET_ADMIN \
-p 1194:1194/udp -p 80:8080/tcp \
--name dockovpn oriolegea/dockovpn -r
```

### Container commands

After container was run using `docker run` command, it's possible to execute additional commands using `docker exec` command. For example, `docker exec <container id> ./version.sh`. See table below to get the full list of supported commands.

| Command  | Description | Parameters | Example |
| :------: | :---------: | :--------: | :-----: |
| `./version.sh` | Outputs full container version, i.e `Dockovpn v1.2.0` |  | `docker exec dockovpn ./version.sh` |
| `./genclient.sh` | Generates new client configuration | `z` — Optional. Puts newly generated client.ovpn file into client.zip archive.<br><br>`zp paswd` — Optional. Puts newly generated client.ovpn file into client.zip archive with password `pswd` <br><br>`o` — Optional. Prints cert to the output. <br><br>`oz` — Optional. Prints zipped cert to the output. Use with output redirection. <br><br>`ozp paswd` — Optional. Prints encrypted zipped cert to the output. Use with output redirection.  <br><br>`n profile_name` — Optional. Use specified profile_name parameter instead of random id. Prints client.ovpn to the output<br><br>`np profile_name` — Optional. Use specified profile_name parameter instead of random id and protects by password asked by stdin. Password refers to the connection and it will be asked during connection stage. Prints client.ovpn to the output | `docker exec dockovpn ./genclient.sh`<br><br>`docker exec dockovpn ./genclient.sh z`<br><br>`docker exec dockovpn ./genclient.sh zp 123` <br><br>`docker exec dockovpn ./genclient.sh o > client.ovpn`<br><br>`docker exec dockovpn ./genclient.sh oz > client.zip` <br><br>`docker exec dockovpn ./genclient.sh ozp paswd > client.zip`<br><br>`docker exec dockovpn ./genclient.sh n profile_name`<br><br>`docker exec -ti dockovpn ./genclient.sh np profile_name` |
| `./rmclient.sh` | Revokes client certificate thus making him/her anable to connect to given Dockovpn server. | Client Id, i.e `vFOoQ3Hngz4H790IpRo6JgKR6cMR3YAp` | `docker exec dockovpn ./rmclient.sh vFOoQ3Hngz4H790IpRo6JgKR6cMR3YAp` |
| `./listconfigs.sh` | List all generated available config IDs |  | `docker exec dockovpn ./listconfigs.sh` |
| `./getconfig.sh` | Return previously generated config by client ID | Client Id, i.e `vFOoQ3Hngz4H790IpRo6JgKR6cMR3YAp` | `docker exec dockovpn./getconfig.sh vFOoQ3Hngz4H790IpRo6JgKR6cMR3YAp` |

 **⚠️ Note:** If you generated a new client configuration with custom name e.g `dockovpn exec ./genclient.sh n customname` and then chose to remove this config using `dockovpn exec ./rmclient.sh customname`, the client certificate is revoked permanently in this server, therefore, you cannot create client configuration with the same name again. Doing so will result in error `Sat Oct 28 10:05:17 2023 Client with this id [customname] already exists`.

## 🔒 Security Features

DockOvpn is configured with modern security standards:

- **Encryption**: AES-256-GCM cipher with SHA512 authentication
- **TLS**: Minimum TLS 1.2 with TLS authentication enabled
- **Key Size**: 4096-bit RSA keys for all certificates
- **DH Parameters**: 4096-bit Diffie-Hellman parameters
- **Certificate Revocation**: CRL (Certificate Revocation List) support enabled
- **DNS**: Cloudflare DNS (1.1.1.1) configured for privacy-focused name resolution

## 🚀 Quick Start

### Prerequisites

1. Any hardware or vps/vds server running Linux. You should have administrative rights on this machine.
2. Docker installation on your server.
3. Public ip address assigned to your server.

### 1. Run dockovpn

Copy & paste the following command to run dockovpn:<br>

```bash
docker run -it --rm --cap-add=NET_ADMIN \
-p 1194:1194/udp -p 80:8080/tcp \
--name dockovpn oriolegea/dockovpn
```

**⚠️ Note:** This snippet runs Dockovpn in attached mode, which means if you close your terminal window, container will be stopped.
To prevent this from happening, you first need to detach container from ssh session. Type `Ctrl+P Ctrl+Q`.

If everything went well, you should be able to see the following output in your console:

```bash
Sun Jun  9 08:56:11 2019 Initialization Sequence Completed
Sun Jun  9 08:56:12 2019 Client.ovpn file has been generated
Sun Jun  9 08:56:12 2019 Config server started, download your client.ovpn config at http://example.com:8080/
Sun Jun  9 08:56:12 2019 NOTE: After you download you client config, http server will be shut down!
 ```

### 2. Get client configuration

Now, when your dockovpn is up and running you can go to `<your_host_public_ip>:8080` on your device and download ovpn client configuration.
As soon as you have your config file downloaded, you will see the following output in the console:<br>

```bash
Sun Jun  9 09:01:15 2019 Config http server has been shut down
```

Import `client.ovpn` into your favourite openvpn client. In most cases it should be enough to just doubleclick or tap on that file.

### 3. Connect to your dockovpn container

You should be able to see your newly added client configuration in the list of available configurations. Click on it, connection process should initiate and be established within few seconds.

Congratulations, now you're all set and can safely browse the internet.

## 🤖 Automated Deployment with GitHub Actions

DockOvpn works exceptionally well as an immutable containerized VPN solution. A practical use case is to deploy it automatically using GitHub Actions, which enables you to:

- **Immutable infrastructure**: Each deployment creates a fresh VPN instance with new credentials
- **Credential rotation**: Easily rotate credentials by triggering a new deployment
- **Automated distribution**: Automatically send new client configurations through your preferred method (email, messaging platforms, etc.)
- **Zero-downtime updates**: Ensure your VPN server always runs the latest security patches

### Example GitHub Actions Workflow

Below is an example workflow that deploys DockOvpn to a self-hosted runner, generates a new client configuration, and sends it via email:

```yaml
name: Deploy VPN Server

on:
  workflow_dispatch:

jobs:
  run-vpn:
    runs-on: [self-hosted, home]

    steps:
    - name: Remove existing VPN container
      run: |
        if [ "$(docker ps -aq -f ancestor=oriolegea/dockovpn)" ]; then
          docker rm -f -v $(docker ps -aq -f ancestor=oriolegea/dockovpn)
        fi

    - name: Remove VPN image
      run: |
        if [ "$(docker images -q oriolegea/dockovpn)" ]; then
          docker rmi -f oriolegea/dockovpn
        fi

    - name: Run new VPN container
      run: |
        docker run --rm -d --cap-add=NET_ADMIN \
          --device=/dev/net/tun \
          -p 1194:1194/udp -p 80:8080/tcp \
          -e HOST_ADDR=your-public-hostname.example.com \
          --name dockovpn oriolegea/dockovpn:latest

    - name: Wait for configuration generation
      run: sleep 10

    - name: Download client configuration
      run: |
        curl -o client.ovpn http://YOUR_LOCAL_SERVER_IP/

    - name: Install mutt
      run: sudo apt-get update && sudo apt-get install -y mutt

    - name: Send configuration via email
      env:
        SMTP_SERVER: ${{ secrets.SMTP_SERVER }}
        SMTP_PORT: ${{ secrets.SMTP_PORT }}
        SMTP_USERNAME: ${{ secrets.SMTP_USERNAME }}
        SMTP_PASSWORD: ${{ secrets.SMTP_PASSWORD }}
      run: |
        echo "set smtp_url = \"smtp://${{ secrets.SMTP_USERNAME }}:${{ secrets.SMTP_PASSWORD }}@${{ secrets.SMTP_SERVER }}:${{ secrets.SMTP_PORT }}\"" > ~/.muttrc
        echo "set ssl_starttls=yes" >> ~/.muttrc
        echo "set ssl_force_tls=yes" >> ~/.muttrc
        echo "set from = \"${{ secrets.SMTP_USERNAME }}\"" >> ~/.muttrc
        echo "set realname = \"VPN Service\"" >> ~/.muttrc
        cat <<EOF > email.html
        <!DOCTYPE html>
        <html>
          <body style="font-family: Arial, sans-serif; background-color: #f4f4f9; padding: 20px;">
            <div style="background-color: #fff; padding: 20px; border-radius: 8px; max-width: 600px; margin: 0 auto;">
              <h2 style="color: #0073e6;">VPN Configuration Update</h2>
              <p>Your VPN configuration has been updated. The attached file contains your new client credentials.</p>
              <p>Please import the attached <code>client.ovpn</code> file into your OpenVPN client to connect.</p>
              <p><strong>Note:</strong> Previous credentials are no longer valid.</p>
            </div>
          </body>
        </html>
        EOF
        mutt -e "set content_type=text/html" -s "VPN Configuration Updated" -a client.ovpn -- user@example.com < email.html
```

**Configuration Notes:**

1. Replace `YOUR_LOCAL_SERVER_IP` with the local IP address of your server (e.g., `192.168.1.100`)
2. Replace `your-public-hostname.example.com` with your server's public hostname or IP
3. Replace `user@example.com` with the recipient's email address
4. Configure GitHub secrets for SMTP credentials:
   - `SMTP_SERVER`: Your SMTP server address
   - `SMTP_PORT`: SMTP port (usually 587 for TLS)
   - `SMTP_USERNAME`: Your email username
   - `SMTP_PASSWORD`: Your email password or app-specific password

**Security Considerations:**

- Sending credentials via email is convenient but may not be suitable for high-security environments
- Consider using encrypted messaging platforms or secure file sharing services for sensitive deployments
- Ensure your GitHub repository is private if it contains deployment workflows
- Use GitHub encrypted secrets for all sensitive credentials

## Persisting configuration

There's a possibility to persist generated files in volume storage. Run docker with

```bash
-v openvpn_conf:/opt/Dockovpn_data
```

## Alternative way. Run with docker-compose

Sometimes it is more convenient to use [docker-compose](https://docs.docker.com/compose/).

To run dockvpn with docker-compose run:

```bash
docker-compose up -d && \
docker-compose exec -d dockovpn wget -O /opt/Dockovpn/client.ovpn localhost:8080
```

After run this command you can find your `client.ovpn` inside `openvpn_conf` folder.

## Other resources

[Privacy Policy](https://github.com/oegea/dockovpn/blob/master/PRIVACY_POLICY.md) \
[Contributing Guidelines](https://github.com/oegea/dockovpn/blob/master/CONTRIBUTING.md) \
[Code Of Conduct](https://github.com/oegea/dockovpn/blob/master/CODE_OF_CONDUCT.md) \
[Release Guideline](https://github.com/oegea/dockovpn/blob/master/docs/RELEASE_GUIDELINE.md) \
[License Agreement](https://github.com/oegea/dockovpn/blob/master/LICENSE)

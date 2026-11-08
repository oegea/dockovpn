FROM alpine:3.24.4

LABEL maintainer="Oriol Egea <imoriol@duck.com>"

# System settings. User normally shouldn't change these parameters
ENV APP_NAME=Dockovpn
ENV APP_INSTALL_PATH=/opt/${APP_NAME}
ENV APP_PERSIST_DIR=/opt/${APP_NAME}_data

# Configuration settings with default values
ENV NET_ADAPTER=eth0
ENV HOST_ADDR=""
ENV HOST_TUN_PORT=1194
ENV HOST_CONF_PORT=80
ENV HOST_TUN_PROTOCOL=udp
ENV CRL_DAYS=3650
# Push an IPv6 blackhole to clients so IPv6 traffic can't bypass the tunnel
# (requires IPv6 to be enabled inside the container, otherwise it's skipped)
ENV BLOCK_IPV6=true

# Use 4096-bit RSA keys for CA, server and client certificates (not only for DH)
ENV EASYRSA_KEY_SIZE=4096

WORKDIR ${APP_INSTALL_PATH}

COPY scripts .
COPY config ./config
COPY VERSION ./config

# Upgrade base packages (base image layer may lag behind the repo) and install deps
RUN apk upgrade --no-cache && \
    apk add --no-cache openvpn easy-rsa bash netcat-openbsd 7zip curl dumb-init iptables && \
    ln -s /usr/share/easy-rsa/easyrsa /usr/bin/easyrsa && \
    mkdir -p ${APP_PERSIST_DIR} /var/lib/openvpn && \
    cd ${APP_PERSIST_DIR} && \
    easyrsa init-pki && \
    easyrsa gen-dh && \
    # DH parameters of size 4096 created at /opt/Dockovpn_data/pki/dh.pem
    # Copy DH file
    cp pki/dh.pem /etc/openvpn && \
    # Copy FROM ./config/server.conf TO /etc/openvpn/server.conf
    cd ${APP_INSTALL_PATH} && \
    cp config/server.conf /etc/openvpn/server.conf && \
    chmod +x *.sh


EXPOSE 1194/${HOST_TUN_PROTOCOL}
EXPOSE 8080/tcp

VOLUME [ "/opt/Dockovpn_data" ]

ENTRYPOINT [ "dumb-init", "./start.sh" ]
CMD [ "" ]

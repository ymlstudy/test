#!/bin/bash
set -e

VERSION="v0.25.1"
PKG="buildkit-${VERSION}.linux-amd64.tar.gz"
URL="https://github.com/moby/buildkit/releases/download/${VERSION}/${PKG}"

cd /tmp

if [ ! -f "${PKG}" ]; then
    wget "${URL}"
else
    echo "${PKG} already exists."
fi

tar xf "${PKG}"
cp -f bin/* /usr/local/bin/

cat >/etc/systemd/system/buildkit.service <<EOF
[Unit]
Description=BuildKit
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/buildkitd
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload && systemctl enable --now buildkit

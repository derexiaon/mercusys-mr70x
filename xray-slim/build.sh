#!/bin/bash
# Build a slim Xray-core binary for MT7621 (mipsle, softfloat).
# Usage: xray-slim/build.sh <xray-tag> <output-binary>
set -euo pipefail

TAG="${1:?xray tag, e.g. v26.3.27}"
OUT="$(realpath -m "${2:?output path}")"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${XRAY_SRC:-$PWD/xray-src}"

[ -d "$SRC/.git" ] || git clone --depth 1 -b "$TAG" https://github.com/XTLS/Xray-core.git "$SRC"
cd "$SRC"

# 1. Only the features we need get registered.
cp "$HERE/all.go" main/distro/all/all.go

# 2. Drop JSON loaders that drag in gRPC, WireGuard/gVisor, Hysteria, etc.
#    and replace their types with stubs returning a clear error.
rm -f infra/conf/vmess.go infra/conf/trojan.go infra/conf/shadowsocks.go \
      infra/conf/wireguard.go infra/conf/hysteria.go infra/conf/grpc.go
rm -f infra/conf/*_test.go
cp "$HERE/stubs.go" infra/conf/zz_slim_stubs.go
if [ -f "$HERE/patch.sh" ]; then
	bash "$HERE/patch.sh" "$SRC"
fi

export CGO_ENABLED=0 GOOS=linux GOARCH=mipsle GOMIPS=softfloat
go build -trimpath \
	-ldflags "-s -w -buildid= -X github.com/xtls/xray-core/core.build=mr70x-slim" \
	-o "$OUT" ./main

echo "xray slim: $(stat -c %s "$OUT") bytes, xz: $(xz -9e -c "$OUT" | wc -c) bytes"

#!/bin/bash
# Smoke test of the firmware scripts inside the built rootfs (qemu-user chroot).
# Usage: sudo tests/smoke.sh <rootfs dir>   (needs qemu-user-static + binfmt)
set -euo pipefail

R="$(realpath "${1:?rootfs dir}")"
HERE="$(cd "$(dirname "$0")" && pwd)"
PORT=18099

mountpoint -q "$R/proc" || mount -t proc proc "$R/proc"
TLSPORT=18443
TMPD="$(mktemp -d)"
HEADERS="$TMPD/headers"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=127.0.0.1 \
	-keyout "$TMPD/key.pem" -out "$TMPD/cert.pem" 2>/dev/null
python3 "$HERE/http-server.py" "$PORT" "$HERE/data" "$HEADERS" "$TLSPORT" "$TMPD/cert.pem" "$TMPD/key.pem" &
HTTP=$!
trap 'kill $HTTP; umount "$R/proc"; rm -rf "$TMPD"' EXIT
sleep 1

run() { chroot "$R" /usr/bin/env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY XRAY_LINK_NO_RESTART=1 /bin/sh -c "$1"; }
check() { if run "$1"; then echo "ok: $2"; else echo "FAIL: $2"; exit 1; fi; }

run '/usr/bin/xray version | head -1'

# /etc/config/network and system are generated on the first boot by config_generate
run 'touch /etc/config/network; [ -s /etc/config/system ] || printf "config system\n\toption hostname OpenWrt\n" > /etc/config/system'
run '. /etc/uci-defaults/99-mr70x-xray'
check '[ "$(uci get network.xray.proto)" = static ]' 'xray interface'
check '[ "$(uci get pbr.@policy[0].name)" = "Xray server (direct)" ]' 'server policy is first'
if [ -x "$R/usr/bin/awg" ]; then
	check 'uci get pbr.config.supported_interface | grep -q awg0' 'awg0 supported by pbr'
	check '[ "$(uci get firewall.awg.network)" = awg0 ]' 'awg firewall zone'
	check 'awg --version | grep -q amneziawg' 'awg tool runs'
	check 'ls /lib/modules/*/amneziawg.ko' 'amneziawg kernel module'
else
	check '! uci -q get firewall.awg' 'no awg zone without AmneziaWG'
fi
if [ -d "$R/www/luci-static/proton2025" ]; then
	check '[ "$(uci get luci.main.mediaurlbase)" = /luci-static/proton2025 ]' 'Proton2025 is the default theme'
fi
check '[ "$(uci get dhcp.@dnsmasq[0].filter_aaaa)" = 1 ]' 'AAAA filtered'
check 'grep -q "xray-link --update" /etc/crontabs/root' 'subscription cron'

# pbr has to download the https lists with uclient-fetch (openwrt/patch-feeds.sh)
cat > "$R/tmp/pbr-dl.sh" <<'EOS'
packageName=pbr
json() { echo "pbr: $*" >&2; }
eval "$(sed -n '/^is_url[a-z_]*()/p; /^is_present()/p; /^sanitize_list()/p; /^process_url() {/,/^}/p' /etc/init.d/pbr)"
process_url "$1"
EOS
check "[ \"\$(sh /tmp/pbr-dl.sh https://127.0.0.1:$TLSPORT/list.txt)\" = 'discord.com youtube.com ' ]" 'pbr downloads https lists'
check '[ -x /etc/init.d/zram ] && [ "$(uci get system.@system[0].zram_size_mb)" = 32 ]' 'zram swap, 32 MB'

# start from a clean state (no subscription, no saved links)
run 'uci -q delete xray.main.subscription; uci -q delete xray.main.server; uci commit xray; rm -f /etc/xray/subscription /etc/xray/links'

# single REALITY link
run "xray-link 'vless://b831381d-6324-4d53-ad4f-8cda48b30811@vpn.example.com:443?type=tcp&security=reality&pbk=Z84J2IelR9ch3k8VtlVhhs5ycBUlXA7wHBWcBrjqnAw&sid=6ba85179e30d4fc2&sni=www.microsoft.com&fp=chrome&flow=xtls-rprx-vision&spx=%2F#test'"
check '[ "$(jsonfilter -i /etc/xray/config.json -e "@.outbounds[0].streamSettings.realitySettings.spiderX")" = / ]' 'reality link'
check '[ "$(jsonfilter -i /etc/xray/config.json -e "@.routing.rules[0].outboundTag")" = proxy-1 ]' 'single server routing'
check '[ "$(jsonfilter -i /etc/xray/config.json -e "@.inbounds[0].protocol")" = tun ]' 'tun inbound'

# unsupported transport must be rejected
if run "xray-link 'vless://b831381d-6324-4d53-ad4f-8cda48b30811@1.2.3.4:443?type=grpc&security=tls'"; then
	echo "FAIL: grpc link must be rejected"; exit 1
fi
echo "ok: grpc rejected"

# base64 subscription with all supported protocols + a server xray rejects
run "xray-link --set 'vless://b831381d-6324-4d53-ad4f-8cda48b30811@1.1.1.1:443?security=reality&pbk=abc#bad key' 'http://127.0.0.1:$PORT/sub.b64' auto"
check '[ "$(wc -l < /etc/xray/servers)" = 6 ]' '6 servers from the subscription, bad manual link dropped'
check '[ "$(jsonfilter -i /etc/xray/config.json -e "@.routing.balancers[0].strategy.type")" = leastPing ]' 'balancer'
check '[ -n "$(jsonfilter -i /etc/xray/config.json -e "@.observatory.probeURL")" ]' 'observatory'
check 'jsonfilter -i /etc/xray/config.json -e "@.outbounds[*].protocol" | sort -u | tr "\n" " " | grep -q "hysteria shadowsocks trojan vless"' 'all protocols present'
check '[ "$(jsonfilter -i /etc/xray/config.json -e "@.outbounds[@.protocol=\"hysteria\"].streamSettings.finalmask.quicParams.udpHop.ports")" = 443,20000-30000 ]' 'hysteria2 port hopping'
check 'uci get pbr.mr70x_server.dest_addr | grep -q hy.example.com' 'servers bypass the tunnel'
check 'xray-link --update | grep -q "не изменилась"' 'unchanged subscription is not re-applied'

# device ID headers for panels with a device limit
hwid="$(run 'uci get xray.main.hwid')"
[[ "$hwid" =~ ^[0-9a-f]{32}$ ]] || { echo "FAIL: hwid '$hwid'"; exit 1; }
last="$(grep '^/sub.b64' "$HEADERS" | tail -n1)"
for h in "x-hwid: $hwid" "x-device-os: OpenWrt" "x-ver-os: $(run '. /etc/openwrt_release; echo $DISTRIB_RELEASE')" "user-agent: v2rayN/7.0"; do
	grep -qF "$h" <<< "$last" || { echo "FAIL: subscription request lacks '$h': $last"; exit 1; }
done
echo "ok: HWID headers"
check '[ "$(xray-link --hwid)" = "$(uci get xray.main.hwid)" ] && [ "$(xray-link --hwid --new)" != '"$hwid"' ]' 'HWID kept, regenerated on request'
run "xray-link --set '' 'http://127.0.0.1:$PORT/sub.b64' auto 0" >/dev/null
grep '^/sub.b64' "$HEADERS" | tail -n1 | grep -q 'x-hwid' && { echo "FAIL: x-hwid sent with send_hwid=0"; exit 1; }
echo "ok: HWID can be turned off"
run 'uci set xray.main.send_hwid=1; uci commit xray'

# pin one server by name
run "xray-link --set '' 'http://127.0.0.1:$PORT/sub.b64' 'Trojan WS'"
t="$(run 'jsonfilter -i /etc/xray/config.json -e "@.routing.rules[0].outboundTag"')"
check "jsonfilter -i /etc/xray/config.json -e '@.outbounds[@.tag=\"$t\"].protocol' | grep -q trojan" 'server selected by name'

# the init script can extract all server hosts for dnsmasq
check '[ "$(jsonfilter -i /etc/xray/config.json -e "@.outbounds[*].settings.address" | wc -l)" -ge 6 ]' 'server hosts for dnsmasq'

echo "smoke test passed"

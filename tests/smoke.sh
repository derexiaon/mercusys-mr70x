#!/bin/bash
# Smoke test of the firmware scripts inside the built rootfs (qemu-user chroot).
# Usage: sudo tests/smoke.sh <rootfs dir>   (needs qemu-user-static + binfmt)
set -euo pipefail

R="$(realpath "${1:?rootfs dir}")"
HERE="$(cd "$(dirname "$0")" && pwd)"
PORT=18099

mountpoint -q "$R/proc" || mount -t proc proc "$R/proc"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$HERE/data" >/dev/null 2>&1 &
HTTP=$!
trap 'kill $HTTP; umount "$R/proc"' EXIT
sleep 1

run() { chroot "$R" /usr/bin/env XRAY_LINK_NO_RESTART=1 /bin/sh -c "$1"; }
check() { if run "$1"; then echo "ok: $2"; else echo "FAIL: $2"; exit 1; fi; }

run '/usr/bin/xray version | head -1'

# /etc/config/network is generated on the first boot by config_generate
run 'touch /etc/config/network'
run '. /etc/uci-defaults/99-mr70x-xray'
check '[ "$(uci get network.xray.proto)" = static ]' 'xray interface'
check '[ "$(uci get pbr.@policy[0].name)" = "Xray server (direct)" ]' 'server policy is first'
check 'uci get pbr.config.supported_interface | grep -q awg0' 'awg0 supported by pbr'
check '[ "$(uci get firewall.awg.network)" = awg0 ]' 'awg firewall zone'
check '[ "$(uci get dhcp.@dnsmasq[0].filter_aaaa)" = 1 ]' 'AAAA filtered'
check 'grep -q "xray-link --update" /etc/crontabs/root' 'subscription cron'

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

# pin one server by name
run "xray-link --set '' 'http://127.0.0.1:$PORT/sub.b64' 'Trojan WS'"
t="$(run 'jsonfilter -i /etc/xray/config.json -e "@.routing.rules[0].outboundTag"')"
check "jsonfilter -i /etc/xray/config.json -e '@.outbounds[@.tag=\"$t\"].protocol' | grep -q trojan" 'server selected by name'

# the init script can extract all server hosts for dnsmasq
check '[ "$(jsonfilter -i /etc/xray/config.json -e "@.outbounds[*].settings.address" | wc -l)" -ge 6 ]' 'server hosts for dnsmasq'

echo "smoke test passed"

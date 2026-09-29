package all

// Slim feature set for Mercusys MR70X (MT7621, 16 MB flash, 128 MB RAM).
// Client-side only: VLESS (+XTLS Vision), Trojan, Shadowsocks (incl. 2022)
// over RAW/TCP, XHTTP, WebSocket, HTTPUpgrade with TLS or REALITY; Hysteria2;
// TUN / tunnel(dokodemo) / SOCKS inbounds.

import (
	// Mandatory features.
	_ "github.com/xtls/xray-core/app/dispatcher"
	_ "github.com/xtls/xray-core/app/proxyman/inbound"
	_ "github.com/xtls/xray-core/app/proxyman/outbound"

	// Optional features.
	_ "github.com/xtls/xray-core/app/dns"
	_ "github.com/xtls/xray-core/app/log"
	_ "github.com/xtls/xray-core/app/policy"
	_ "github.com/xtls/xray-core/app/router"
	_ "github.com/xtls/xray-core/app/stats"

	// Fix dependency cycle caused by core import in internet package
	_ "github.com/xtls/xray-core/transport/internet/tagged/taggedimpl"

	// Proxies.
	_ "github.com/xtls/xray-core/proxy/blackhole"
	_ "github.com/xtls/xray-core/proxy/dns"
	_ "github.com/xtls/xray-core/proxy/dokodemo"
	_ "github.com/xtls/xray-core/proxy/freedom"
	_ "github.com/xtls/xray-core/proxy/http"
	_ "github.com/xtls/xray-core/proxy/hysteria"
	_ "github.com/xtls/xray-core/proxy/shadowsocks"
	_ "github.com/xtls/xray-core/proxy/shadowsocks_2022"
	_ "github.com/xtls/xray-core/proxy/socks"
	_ "github.com/xtls/xray-core/proxy/trojan"
	_ "github.com/xtls/xray-core/proxy/tun"
	_ "github.com/xtls/xray-core/proxy/vless/outbound"

	// Transports.
	_ "github.com/xtls/xray-core/transport/internet/httpupgrade"
	_ "github.com/xtls/xray-core/transport/internet/hysteria"
	_ "github.com/xtls/xray-core/transport/internet/reality"
	_ "github.com/xtls/xray-core/transport/internet/splithttp"
	_ "github.com/xtls/xray-core/transport/internet/tcp"
	_ "github.com/xtls/xray-core/transport/internet/tls"
	_ "github.com/xtls/xray-core/transport/internet/udp"
	_ "github.com/xtls/xray-core/transport/internet/websocket"

	// Transport headers.
	_ "github.com/xtls/xray-core/transport/internet/headers/http"
	_ "github.com/xtls/xray-core/transport/internet/headers/noop"

	// JSON config.
	_ "github.com/xtls/xray-core/main/json"

	// Load config from file.
	_ "github.com/xtls/xray-core/main/confloader/external"
)

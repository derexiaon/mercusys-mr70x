#!/bin/bash
# Source-level trimming of Xray-core that can't be done with stub files.
# Usage: patch.sh <xray-src-dir>
set -euo pipefail
cd "$1"

# stub_types FILE LABEL "STUBBED TYPES" ["OTHER REMOVED TYPES"] ["FUNCS TO KEEP"]
# Removes the declarations of the listed config types (from "type X struct" up to the
# next type that is not listed, including their methods and helpers in between,
# except the listed functions other code uses) and puts in stubs whose Build()
# returns a clear error.
stub_types() {
	local f="$1" label="$2" stubs="$3" others="${4:-}" keep="${5:-}"
	grep -q "^type ${stubs%% *} struct" "$f" || return 0
	awk -v label="$label" -v stubs="$stubs" -v others="$others" -v keep="$keep" '
		BEGIN {
			ns = split(stubs, st, " "); split(others, ot, " "); split(keep, kp, " ")
			for (i in st) rm[st[i]] = 1
			for (i in ot) rm[ot[i]] = 1
			for (i in kp) kf["func " kp[i] "("] = 1
		}
		skip && /^func [A-Za-z0-9_]+\(/ && (substr($0, 1, index($0, "(")) in kf) { keeping = 1 }
		keeping { print; if ($0 == "}") keeping = 0; next }
		/^type [A-Za-z0-9_]+ / {
			name = $2
			if (name in rm) {
				if (!skip) {
					for (i = 1; i <= ns; i++) {
						printf "type %s struct{}\n\n", st[i]
						printf "func (*%s) Build() (proto.Message, error) { return slimUnsupported(\"%s\") }\n\n", st[i], label
					}
				}
				skip = 1; next
			}
			skip = 0
		}
		!skip { print }
	' "$f" > "$f.new"
	mv "$f.new" "$f"
	for t in $stubs $others; do
		[ "$(grep -c "^type $t " "$f")" -le 1 ] || { echo "stub_types: $t left in $f" >&2; exit 1; }
	done
}

# infra/conf/serial: JSON only, drop TOML (pelletier/go-toml) and YAML (ghodss/yaml).
f=infra/conf/serial/loader.go
awk '
	/^\/\/ .*[Tt][Oo][Mm][Ll]/ || /^func (Decode|Load)(TOML|YAML)Config/ { exit }
	{ print }
' "$f" > "$f.new"
mv "$f.new" "$f"
sed -i '/"github.com\/ghodss\/yaml"/d; /"github.com\/pelletier\/go-toml"/d' "$f"
sed -i '/ReaderDecoderByFormat\["\(yaml\|toml\)"\]/d' infra/conf/serial/builder.go

grep -q 'func LoadJSONConfig' "$f"
! grep -q 'TOML\|YAML' "$f"

# infra/conf/transport_method.go (Xray >= 26.10): GRPCConfig moved here from grpc.go and
# imports transport/internet/grpc, which pulls in google.golang.org/grpc.
# Cut it out; zz_slim_stubs.go provides the stub type.
f=infra/conf/transport_method.go
if grep -q '^type GRPCConfig struct' "$f"; then
	awk '
		/^type GRPCConfig struct/ { skip = 1 }
		/^func \(g \*GRPCConfig\) Build\(\)/ { skip = 2 }
		skip { if ($0 == "}") skip = 0; next }
		{ print }
	' "$f" > "$f.new"
	mv "$f.new" "$f"
	sed -i '\#"github.com/xtls/xray-core/transport/internet/grpc"#d' "$f"
	! grep -q 'GRPCConfig\|grpc\.' "$f"
fi

# transport/internet/tls/grpc.go: uTLS credentials for the gRPC transport (not built);
# the file alone links google.golang.org/grpc.
rm -f transport/internet/tls/grpc.go

# MASQUE outbound/inbound (Xray >= 26.10) pulls in the WireGuard stack.
if [ -f infra/conf/masque.go ]; then
	rm infra/conf/masque.go
	cat >> infra/conf/zz_slim_stubs.go <<-'STUB'

		type MasqueClientConfig struct{}

		func (*MasqueClientConfig) Build() (proto.Message, error) { return slimUnsupported("masque") }

		type MasqueServerConfig struct{}

		func (*MasqueServerConfig) Build() (proto.Message, error) { return slimUnsupported("masque") }
	STUB
fi

# finalmask "realm" (NAT traversal: STUN, UPnP, NAT-PMP, DTLS) -> stub.
f=infra/conf/transport_finalmask.go
if grep -q '^type Realm struct' "$f"; then
	awk '
		/^type Realm struct/ {
			print "type Realm struct{}"
			print ""
			print "func (*Realm) Build() (proto.Message, error) { return slimUnsupported(\"realm finalmask\") }"
			print ""
			skip = 1; next
		}
		skip && /^type / { skip = 0 }
		!skip { print }
	' "$f" > "$f.new"
	mv "$f.new" "$f"
	sed -i '\#"github.com/xtls/xray-core/transport/internet/finalmask/realm"#d' "$f"
	! grep -q 'realm\.' "$f"
fi
# infra/conf/xray.go checks for the masque config types; without masque they never match.
f=infra/conf/xray.go
sed -i 's/_, ok := ts\.(\*masque\.\(Server\|Client\)Config)/ok := false/; \#"github.com/xtls/xray-core/proxy/masque"#d' "$f"
! grep -q 'masque\.' "$f"

# Lua scripting for routing/DNS (Xray >= 26.10, gopher-lua + gopher-luar): replaced by
# script engines that refuse to start, so a config with a script gets a clear error.
if [ -f app/router/script.go ] && grep -q gopher-lua app/router/script.go; then
	rm -f app/router/lua.go app/dns/lua.go common/log/lua.go common/geodata/lua.go
	cat > app/router/script.go <<-'STUB'
		package router

		import (
			"github.com/xtls/xray-core/common/errors"
			"github.com/xtls/xray-core/features/routing"
		)

		type scriptEngine struct{}

		func newScriptEngine(path string, router *Router) (*scriptEngine, error) {
			return nil, errors.New("routing scripts (Lua) are not included in this slim Xray build (mercusys-mr70x)")
		}

		func (e *scriptEngine) close() {}

		func (e *scriptEngine) pickRoute(ctx routing.Context) (routing.Route, error) {
			return nil, errors.New("no script engine")
		}
	STUB
	cat > app/dns/script.go <<-'STUB'
		package dns

		import (
			"github.com/xtls/xray-core/common/errors"
			"github.com/xtls/xray-core/common/net"
			"github.com/xtls/xray-core/features/dns"
		)

		type scriptEngine struct{}

		func newScriptEngine(path string, server *DNS) (*scriptEngine, error) {
			return nil, errors.New("DNS scripts (Lua) are not included in this slim Xray build (mercusys-mr70x)")
		}

		func (e *scriptEngine) close() {}

		func (e *scriptEngine) query(domain string, option dns.IPOption) ([]net.IP, uint32, error) {
			return nil, 0, errors.New("no script engine")
		}
	STUB
fi

# transport/internet/tls/config.go: the embedded Mozilla root bundle (x509roots/fallback)
# is only a fallback for systems without CA certificates; OpenWrt ships ca-bundle.
f=transport/internet/tls/config.go
if grep -q 'x509roots/fallback/bundle' "$f"; then
	awk '
		/^var bundleCertPool = sync.OnceValue/ {
			print "var bundleCertPool = sync.OnceValue(func() *x509.CertPool { return x509.NewCertPool() })"
			skip = 1; next
		}
		skip { if ($0 == "})") skip = 0; next }
		{ print }
	' "$f" > "$f.new"
	mv "$f.new" "$f"
	sed -i '\#"golang.org/x/crypto/x509roots/fallback/bundle"#d' "$f"
	! grep -q 'bundle\.' "$f"
fi

# New transports and masks of Xray >= 26.10 that the router does not use.
stub_types infra/conf/transport_method.go "masque transport" "MasqueConfig" "MasqueWarpConfig" readFileOrString
stub_types infra/conf/transport_method.go "xdrive transport" "XDriveConfig"
stub_types infra/conf/transport_finalmask.go "sudoku finalmask" "Sudoku"
stub_types infra/conf/transport_finalmask.go "xdns finalmask" "XDNS" "XDNSDomain XDNSResolver"
stub_types infra/conf/transport_finalmask.go "xmc finalmask" "XMC" "XMCProfile"
stub_types infra/conf/transport_finalmask.go "xicmp finalmask" "Xicmp"

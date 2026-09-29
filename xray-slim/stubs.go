package conf

// Stubs used by the slim Xray build for MR70X (16 MB flash).
// The original infra/conf files for these protocols pull in gRPC,
// WireGuard and other heavy dependencies.
// The JSON loader keeps recognising the protocol names but returns a
// clear error if a config tries to use them.

import (
	"github.com/xtls/xray-core/common/errors"
	"google.golang.org/protobuf/proto"
)

func slimUnsupported(name string) (proto.Message, error) {
	return nil, errors.New(name + " is not included in this slim Xray build (mercusys-mr70x)")
}

type VMessInboundConfig struct{}

func (*VMessInboundConfig) Build() (proto.Message, error) { return slimUnsupported("vmess") }

type VMessOutboundConfig struct{}

func (*VMessOutboundConfig) Build() (proto.Message, error) { return slimUnsupported("vmess") }

type WireGuardConfig struct {
	IsClient bool
}

func (*WireGuardConfig) Build() (proto.Message, error) { return slimUnsupported("wireguard") }

type GRPCConfig struct{}

func (*GRPCConfig) Build() (proto.Message, error) { return slimUnsupported("grpc transport") }

// "api" (gRPC commander) and "metrics" (pprof/expvar HTTP server).
type APIConfig struct{}

func (*APIConfig) Build() (proto.Message, error) { return slimUnsupported("api") }

type MetricsConfig struct{}

func (*MetricsConfig) Build() (proto.Message, error) { return slimUnsupported("metrics") }

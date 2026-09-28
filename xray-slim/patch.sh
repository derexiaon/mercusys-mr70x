#!/bin/bash
# Source-level trimming of Xray-core that can't be done with stub files.
# Usage: patch.sh <xray-src-dir>
set -euo pipefail
cd "$1"

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

#!/bin/sh
# Fixes applied to the feeds after "scripts/feeds install".
# Usage: openwrt/patch-feeds.sh <openwrt source dir>
set -eu
cd "$1"

# pbr downloads list URLs (https://...) only if curl or wget-ssl is installed: with just
# uclient-fetch it reports "HTTPS is not supported" and skips every https list.
# uclient-fetch does https through libustream-ssl, which the firmware has.
f=feeds/packages/net/pbr/files/etc/init.d/pbr
if ! grep -q 'mr70x: uclient-fetch' "$f"; then
	sed -i '/^\t\tunset dl_https_supported$/{n;s#^\tfi$#&\n\t\# mr70x: uclient-fetch with libustream-ssl handles https too\n\t[ -z "$dl_https_supported" ] \&\& [ "${dl_command%% *}" = uclient-fetch ] \&\& [ -e /lib/libustream-ssl.so ] \&\& dl_https_supported=1#}' "$f"
fi
grep -q 'mr70x: uclient-fetch' "$f" || { echo "patch-feeds: pbr patch did not apply" >&2; exit 1; }

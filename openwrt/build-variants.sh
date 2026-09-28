#!/bin/bash
# Build several firmware variants from one prepared OpenWrt tree.
# The toolchain and most packages are built once, every next variant only
# rebuilds what changed (a few minutes).
#
# Usage: openwrt/build-variants.sh <openwrt src> <out dir> <variants file>
#   variants file: one variant per line, "AWG APK PROTON" (0/1 each)
# Env: OPENWRT_VERSION, FIRMWARE_LIMIT (bytes), SUMMARY (markdown file to append to)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$HERE")"
SRC="$(realpath "$1")"
OUT="$(realpath -m "$2")"
VARIANTS="$(realpath "$3")"
LIMIT="${FIRMWARE_LIMIT:-16121856}"
VERSION="${OPENWRT_VERSION:-snapshot}"
SUMMARY="${SUMMARY:-/dev/null}"
TARGET_DIR="$SRC/bin/targets/ramips/mt7621"

mkdir -p "$OUT"
cd "$SRC"

require() {
	local o
	for o in "$@"; do
		grep -qx -- "$o" .config || { echo "::error::$o was dropped by make defconfig"; exit 1; }
	done
}

vermagic() {
	python3 -c 'import json, sys; print(json.load(sys.stdin)["linux_kernel"]["vermagic"])'
}

failed=0
{
	echo "| Вариант | AmneziaWG | apk | Proton | Размер прошивки | Свободно под настройки |"
	echo "| --- | --- | --- | --- | --- | --- |"
} >> "$SUMMARY"

while read -r awg apk proton _; do
	case "$awg" in ''|\#*) continue ;; esac
	name="$(sh "$HERE/variant.sh" name "$awg" "$apk" "$proton")"
	echo "::group::variant $name"

	sh "$HERE/variant.sh" base "$awg" "$apk" "$proton" > .config
	sh "$HERE/variant.sh" config "$awg" "$apk" "$proton" >> .config
	make defconfig >/dev/null

	require CONFIG_TARGET_ramips_mt7621_DEVICE_mercusys_mr70x-v1=y CONFIG_TARGET_SQUASHFS_BLOCK_SIZE=1024 \
		CONFIG_PACKAGE_dnsmasq-full=y CONFIG_PACKAGE_pbr=y CONFIG_PACKAGE_kmod-tun=y \
		CONFIG_PACKAGE_luci-i18n-base-ru=y CONFIG_PACKAGE_ppp-mod-pppoe=y
	[ "$awg" = 1 ] && require CONFIG_PACKAGE_kmod-amneziawg=y CONFIG_PACKAGE_luci-proto-amneziawg=y
	[ "$proton" = 1 ] && require CONFIG_PACKAGE_luci-theme-proton2025=y
	if [ "$apk" = 1 ]; then
		require CONFIG_PACKAGE_apk-mbedtls=y CONFIG_PACKAGE_luci-app-package-manager=y '# CONFIG_USE_MKLIBS is not set' \
			CONFIG_ALL_KMODS=y CONFIG_COLLECT_KERNEL_DEBUG=y
	else
		require '# CONFIG_PACKAGE_apk-mbedtls is not set' CONFIG_USE_MKLIBS=y
	fi

	rm -f "$TARGET_DIR"/*.bin
	if ! make -j"$(nproc)" >"build-$name.log" 2>&1; then
		tail -50 "build-$name.log"
		echo "::endgroup::"
		echo "::group::verbose rebuild of $name"
		make -j1 V=s 2>&1 | tail -200
		echo "::endgroup::"
		exit 1
	fi

	if [ "$apk" = 1 ]; then
		# official kmod-* packages only install into the official kernel
		ours="$(vermagic < "$TARGET_DIR/profiles.json")"
		official="$(curl -fsSL "https://downloads.openwrt.org/releases/$VERSION/targets/ramips/mt7621/profiles.json" | vermagic)"
		echo "$name: kernel vermagic $ours, official $official"
		if [ -z "$ours" ] || [ "$ours" != "$official" ]; then
			echo "::error::$name: kernel differs from the official one ($ours != $official), official kmod-* packages would not install"
			exit 1
		fi
	fi

	sysupgrade="$(ls "$TARGET_DIR"/*-squashfs-sysupgrade.bin)"
	size=$(stat -c %s "$sysupgrade")
	free=$(( (LIMIT - size) / 1024 ))
	printf '| `%s` | %s | %s | %s | %s байт | %s КБ |\n' "$name" \
		"$([ "$awg" = 1 ] && echo да || echo нет)" "$([ "$apk" = 1 ] && echo да || echo нет)" \
		"$([ "$proton" = 1 ] && echo да || echo нет)" "$size" "$free" >> "$SUMMARY"
	echo "$name: sysupgrade $size bytes, free for settings $free KiB"

	if [ "$size" -ge "$LIMIT" ]; then
		echo "::error::$name does not fit: $size >= $LIMIT"
		failed=1
		echo "::endgroup::"
		continue
	fi

	rootfs="$(ls -d "$SRC"/build_dir/target-*/root-ramips)"
	"$REPO/tests/check-symbols.sh" "$rootfs" "$(ls "$SRC"/staging_dir/toolchain-*/bin/*-openwrt-linux-nm | head -n1)"
	# The smoke test runs as root and changes the rootfs: use a copy, so the
	# build tree stays clean for the next variant.
	testroot="$(mktemp -d /tmp/smoke-root.XXXXXX)"
	sudo cp -a "$rootfs/." "$testroot/"
	sudo "$REPO/tests/smoke.sh" "$testroot"
	sudo rm -rf --one-file-system "$testroot"

	for f in "$TARGET_DIR"/*-squashfs-factory.bin "$TARGET_DIR"/*-squashfs-sysupgrade.bin "$TARGET_DIR"/*.manifest; do
		base="$(basename "$f")"
		suffix="${base#*mercusys_mr70x-v1}"
		cp "$f" "$OUT/openwrt-$VERSION-mercusys_mr70x-v1-$name$suffix"
	done
	echo "::endgroup::"
done < "$VARIANTS"

exit "$failed"

#!/bin/sh
# Print the variant name and the extra config lines for a firmware variant.
# Usage: openwrt/variant.sh base|config|name AWG APK PROTON   (each 0 or 1)
#
#   AWG     AmneziaWG kernel module, tools and LuCI protocol
#   APK     apk package manager (+ LuCI page). Such variants use the official
#           kernel config (no slim-kernel block of diffconfig, all kmods built
#           like on the OpenWrt buildbots) so kmod-* packages from the official
#           repository install, and no mklibs, because packages installed later
#           may need library functions it strips
#   PROTON  luci-theme-proton2025 as the default LuCI theme

what="$1" awg="$2" apk="$3" proton="$4"

case "$what" in
base)
	# diffconfig, without the slim-kernel block for apk variants
	here="$(cd "$(dirname "$0")" && pwd)"
	if [ "$apk" = 1 ]; then
		sed '/^# >>> slim-kernel/,/^# <<< slim-kernel/d' "$here/diffconfig"
	else
		cat "$here/diffconfig"
	fi
	;;
name)
	name=xray
	[ "$awg" = 1 ] && name="$name-awg"
	[ "$proton" = 1 ] && name="$name-proton"
	[ "$apk" = 1 ] && name="$name-apk"
	echo "$name"
	;;
config)
	if [ "$awg" != 1 ]; then
		echo '# CONFIG_PACKAGE_kmod-amneziawg is not set'
		echo '# CONFIG_PACKAGE_amneziawg-tools is not set'
		echo '# CONFIG_PACKAGE_luci-proto-amneziawg is not set'
		echo '# CONFIG_PACKAGE_luci-i18n-amneziawg-ru is not set'
	fi
	if [ "$apk" = 1 ]; then
		echo 'CONFIG_PACKAGE_apk-mbedtls=y'
		echo 'CONFIG_PACKAGE_luci-app-package-manager=y'
		echo 'CONFIG_PACKAGE_luci-i18n-package-manager-ru=y'
		# same kernel config (and so the same kernel hash) as the buildbots
		echo 'CONFIG_ALL_KMODS=y'
		echo 'CONFIG_COLLECT_KERNEL_DEBUG=y'
		echo 'CONFIG_REPRODUCIBLE_DEBUG_INFO=y'
		echo 'CONFIG_KERNEL_BUILD_USER="builder"'
		echo 'CONFIG_KERNEL_BUILD_DOMAIN="buildhost"'
	fi
	if [ "$proton" = 1 ]; then
		echo 'CONFIG_PACKAGE_luci-theme-proton2025=y'
	fi
	;;
*)
	echo "usage: $0 base|config|name AWG APK PROTON" >&2
	exit 1
	;;
esac

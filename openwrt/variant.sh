#!/bin/sh
# Print the variant name and the extra config lines for a firmware variant.
# Usage: openwrt/variant.sh name|config AWG APK PROTON   (each 0 or 1)
#
#   AWG     AmneziaWG kernel module, tools and LuCI protocol
#   APK     apk package manager (+ LuCI page); disables mklibs, because
#           packages installed later may need library functions it strips
#   PROTON  luci-theme-proton2025 as the default LuCI theme

what="$1" awg="$2" apk="$3" proton="$4"

case "$what" in
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
		echo '# CONFIG_USE_MKLIBS is not set'
	fi
	if [ "$proton" = 1 ]; then
		echo 'CONFIG_PACKAGE_luci-theme-proton2025=y'
	fi
	;;
*)
	echo "usage: $0 name|config AWG APK PROTON" >&2
	exit 1
	;;
esac

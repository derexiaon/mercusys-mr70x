#!/bin/sh
# Print the variant name and the extra config lines for a firmware variant.
# Usage: openwrt/variant.sh official|base|config|name AWG APK PROTON   (each 0 or 1)
#
#   AWG     AmneziaWG kernel module, tools and LuCI protocol
#   APK     apk package manager (+ LuCI page). Such variants start from the
#           official config.buildinfo of the release (see "official" below and
#           build-variants.sh), which gives the official kernel config and so
#           the official kernel hash: kmod-* packages from the official
#           repository install. They also skip the slim-kernel block of
#           diffconfig and mklibs, because packages installed later may need
#           library functions it strips.
#   PROTON  luci-theme-proton2025 as the default LuCI theme

what="$1" awg="$2" apk="$3" proton="$4"

case "$what" in
official)
	# changes to the official config.buildinfo: one device instead of all,
	# no ImageBuilder/SDK/all packages, none of the extra default packages
	cat <<-'EOF'
		# CONFIG_TARGET_MULTI_PROFILE is not set
		# CONFIG_TARGET_ALL_PROFILES is not set
		# CONFIG_ALL_NONSHARED is not set
		# CONFIG_IB is not set
		# CONFIG_SDK is not set
		# CONFIG_MAKE_TOOLCHAIN is not set
		# CONFIG_AUTOREMOVE is not set
		# CONFIG_JSON_CYCLONEDX_SBOM is not set
		# CONFIG_PACKAGE_luci is not set
		# CONFIG_PACKAGE_luci-ssl is not set
		# CONFIG_PACKAGE_px5g-mbedtls is not set
		# CONFIG_PACKAGE_luci-app-attendedsysupgrade is not set
		# CONFIG_PACKAGE_attendedsysupgrade-common is not set
		# CONFIG_PACKAGE_owut is not set
		# CONFIG_PACKAGE_ucode-mod-uclient is not set
		# CONFIG_PACKAGE_rpcd-mod-rpcsys is not set
	EOF
	;;
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
	fi
	if [ "$proton" = 1 ]; then
		echo 'CONFIG_PACKAGE_luci-theme-proton2025=y'
	fi
	;;
*)
	echo "usage: $0 official|base|config|name AWG APK PROTON" >&2
	exit 1
	;;
esac

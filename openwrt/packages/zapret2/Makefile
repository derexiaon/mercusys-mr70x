# zapret2 (https://github.com/bol-van/zapret2): nfqws2 DPI bypass for direct traffic.
# Built with PUC Lua 5.3 (liblua5.3, ~140 KB) instead of LuaJIT (~500 KB); the Lua
# strategies only run on the first packets of a connection.

include $(TOPDIR)/rules.mk

PKG_NAME:=zapret2
PKG_VERSION:=1.0.5
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/bol-van/zapret2.git
PKG_SOURCE_VERSION:=0b8182d24a887059a628d7266577c4ba8e9b8f2d
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=docs/LICENSE.txt

include $(INCLUDE_DIR)/package.mk

define Package/zapret2
  SECTION:=net
  CATEGORY:=Network
  TITLE:=zapret2 nfqws2 DPI bypass (mercusys-mr70x)
  URL:=https://github.com/bol-van/zapret2
  DEPENDS:=+libnetfilter-queue +libmnl +zlib +liblua5.3 +kmod-nft-queue +kmod-nfnetlink-queue
endef

define Package/zapret2/description
 nfqws2 from zapret2 with its Lua strategy library, a procd service with its own
 nftables table (inet zapret2) and a host list for YouTube and Discord.
endef

define Package/zapret2/conffiles
/etc/config/zapret2
/etc/zapret2/hostlist.txt
endef

define Build/Compile
	# CFLAGS/LDFLAGS through the environment: nfq2/Makefile appends its own (-Os, LTO)
	CFLAGS="$(TARGET_CFLAGS) $(TARGET_CPPFLAGS)" LDFLAGS="$(TARGET_LDFLAGS)" \
	$(MAKE) -C $(PKG_BUILD_DIR)/nfq2 $(TARGET_CONFIGURE_OPTS) \
		LUA_JIT=0 \
		LUA_CFLAGS="-I$(STAGING_DIR)/usr/include/lua5.3" \
		LUA_LIB="-L$(STAGING_DIR)/usr/lib -llua5.3"
endef

FAKE_BLOBS:= \
	tls_clienthello_www_google_com.bin \
	quic_initial_www_google_com.bin \
	stun.bin \
	discord-ip-discovery-with-port.bin \
	discord-ip-discovery-without-port.bin

define Package/zapret2/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/nfq2/nfqws2 $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/usr/share/zapret2/lua
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/lua/zapret-lib.lua $(PKG_BUILD_DIR)/lua/zapret-antidpi.lua \
		$(PKG_BUILD_DIR)/lua/zapret-auto.lua $(1)/usr/share/zapret2/lua/
	$(INSTALL_DIR) $(1)/usr/share/zapret2/fake
	$(foreach f,$(FAKE_BLOBS),$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/fake/$(f) $(1)/usr/share/zapret2/fake/;)
	$(INSTALL_DIR) $(1)/etc/init.d $(1)/etc/config $(1)/etc/zapret2
	$(INSTALL_BIN) ./files/zapret2.init $(1)/etc/init.d/zapret2
	$(INSTALL_CONF) ./files/zapret2.config $(1)/etc/config/zapret2
	$(INSTALL_DATA) ./files/hostlist.txt $(1)/etc/zapret2/hostlist.txt
endef

$(eval $(call BuildPackage,zapret2))

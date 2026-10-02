include $(TOPDIR)/rules.mk

PKG_NAME:=okop

PKG_VERSION := $(if $(OKOP_VERSION),$(OKOP_VERSION),0.$(shell date +%d%m%Y))

PKG_RELEASE:=1

PKG_MAINTAINER:=Evgeny Belov <belov-e@ya.ru>
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/okop
	SECTION:=net
	CATEGORY:=Network
	DEPENDS:=+sing-box +curl +jq +kmod-nft-tproxy +coreutils-base64 +bind-dig
	CONFLICTS:=https-dns-proxy nextdns luci-app-passwall luci-app-passwall2 podkop
	TITLE:=Domain routing app
	URL:=https://github.com/trahelman/okop
	PKGARCH:=all
endef

define Package/okop/description
	Domain routing. Use of VLESS, Shadowsocks technologies
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/okop/prerm
#!/bin/sh

[ -n "$${IPKG_INSTROOT}" ] && exit 0

# Runs before the generic prerm stops the service. Stopped first: the ip rule refers to the okop routing
# table by name and cannot be deleted once the name is gone from rt_tables.
/etc/init.d/okop stop

grep -q "105 okop" /etc/iproute2/rt_tables && sed -i "/105 okop/d" /etc/iproute2/rt_tables

if [ "$$PKG_UPGRADE" != "1" ]; then
	# okop enabled sing-box with its own configuration, which refers to rule sets in /tmp. Left enabled,
	# sing-box would fail to start at every boot.
	uci -q set sing-box.main.enabled=0 && uci -q commit sing-box
	/etc/init.d/sing-box stop
fi

exit 0
endef

define Package/okop/conffiles
/etc/config/okop
endef

define Package/okop/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/okop $(1)/etc/init.d/okop

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/okop $(1)/etc/config/okop

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/okop $(1)/usr/bin/okop

	$(INSTALL_DIR) $(1)/usr/lib/okop
	$(CP) ./files/usr/lib/* $(1)/usr/lib/okop/

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/50_okop_migrate_podkop $(1)/etc/uci-defaults/50_okop_migrate_podkop

	sed -i -e 's/__COMPILED_VERSION_VARIABLE__/$(PKG_VERSION)/g' $(1)/usr/lib/okop/constants.sh
endef

$(eval $(call BuildPackage,okop))

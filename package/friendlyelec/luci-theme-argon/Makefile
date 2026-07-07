#
# Copyright (C) 2008-2019 Jerrykuku
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-theme-argon
PKG_VERSION:=2.4.3
PKG_RELEASE:=20250722

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/jerrykuku/luci-theme-argon/tar.gz/refs/tags/v$(PKG_VERSION)?
PKG_HASH:=032351d112f6a2011b6c6fbc5e621bb13bca845f845d8af8df24380d359d7227
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Jerrykuku <jerrykuku@qq.com>

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/luci-theme-argon
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Themes
  TITLE:=Argon Theme
  DEPENDS:=+luci-base +wget +jsonfilter
  PKGARCH:=all
endef

define Package/luci-theme-argon/description
  Argon is a clean and tidy OpenWrt LuCI theme.
endef

define Build/Compile
endef

define Package/luci-theme-argon/install
	$(INSTALL_DIR) $(1)/www/luci-static
	$(CP) $(PKG_BUILD_DIR)/htdocs/luci-static/* $(1)/www/luci-static/

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view
	$(CP) $(PKG_BUILD_DIR)/luasrc/view/* $(1)/usr/lib/lua/luci/view/

	$(CP) $(PKG_BUILD_DIR)/root/. $(1)/
endef

define Package/luci-theme-argon/postinst
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	killall -HUP rpcd 2>/dev/null
	exit 0
}
endef

$(eval $(call BuildPackage,luci-theme-argon))

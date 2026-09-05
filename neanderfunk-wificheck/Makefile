include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-wificheck
PKG_VERSION:=2

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  SECTION:=gluon
  CATEGORY:=Gluon
  TITLE:=WIFI-Neighborcheck
  DEPENDS:=+gluon-core +micrond
endef

define Package/$(PKG_NAME)/description
	Older sibling of neanderfunk-linkcheck, IBSS/adhoc-mesh only (not
	802.11s-compatible). Once at least 2 wifi mesh neighbours have been seen
	after boot, it arms itself; if all neighbours are then lost for two
	consecutive checks, it reboots the node to recover a wedged wifi driver.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(CP) ./files/* $(1)/
	./gluonShellDiet.sh $(1)/lib/gluon/wificheck/wificheck.sh
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-wifi-blackout
PKG_VERSION:=2

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  SECTION:=neanderfunk
  CATEGORY:=Workarounds
  TITLE:=Wifi blackout workaround (Eulenfunk, FreifunkHochstift)
  DEPENDS:=+gluon-core +micrond
  CONFLICTS:=neanderfunk-ath9kblackout eulenfunk-ath9kblackout gluon-ath9kblackout
  MAINTAINER:=Freifunk im Neanderland <projekt@neanderfunk.de>
endef

define Package/$(PKG_NAME)/description
	Detects a wifi blackout - the radios are up, but not a single station is
	associated anywhere on the node, neither client nor mesh peer, and none
	has been for hours - and restarts the wifi, rebooting if that does not
	help. Unlike the other checks in this feed it deliberately has no
	"arm once the healthy state was seen" rule, which is what makes it the
	only one that catches a radio broken from the moment it came up. Not
	restricted to any chipset. Can be switched off per node
	(uci set wifi_blackout.settings.disabled=1). See README.md.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
	$(call GluonSrcDiet,./luasrc,$(PKG_BUILD_DIR)/luadest/)
endef

define Package/$(PKG_NAME)/install
	$(CP) ./files/* $(1)/
	$(CP) $(PKG_BUILD_DIR)/luadest/* $(1)/
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
$(call GluonCheckSite,check_site.lua)
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

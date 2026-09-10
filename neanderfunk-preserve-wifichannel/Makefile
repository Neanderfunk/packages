include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-preserve-wifichannel
PKG_VERSION:=1

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  SECTION:=admin
  CATEGORY:=Workaround
  DEPENDS:=+gluon-core
  TITLE:=Keep wifi channels across updates, reapply them once after a site/domain switch
endef

define Package/$(PKG_NAME)/description
  Gluon resets channel, channel list and width to the site's values on every
  update unless the uci option gluon.wireless.preserve_channels is set. Gluon
  does not read "wifi24.preserve_channels" from the site.conf; this package
  makes that key the default for the uci option:
  - key missing on a node: set it from the site (on a fresh install only once
    the first configuration is done, so the config mode wizard still shows its
    outdoor step and a domain chosen there gets its channels)
  - key present (0 or 1): left alone
  - site or domain changed (nodeplacer, gluon-switch-domain): the site's
    channels are applied once, gluon.wireless.preserve_channels stays as it is
  - outdoor mode (or an outdoor channel width) changed: the 5 GHz channels are
    applied once, the other bands and gluon.wireless.preserve_channels stay
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
	$(CP) $(PKG_BUILD_DIR)/luadest/* $(1)/
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
$(call GluonCheckSite,check_site.lua)
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

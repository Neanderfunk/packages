include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-linkcheck
PKG_VERSION:=2

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  SECTION:=gluon
  CATEGORY:=Gluon
  TITLE:=WIFI and batman Neighborcheck
  DEPENDS:=+gluon-core +micrond
endef

define Package/$(PKG_NAME)/description
	Watches wifi/lan mesh links and batman/bridge interfaces for neighbours
	going missing after having been seen before. A link that stays an
	"island" for three checks in a row (5 minutes apart) triggers a reboot,
	which recovers crashed or wedged drivers that a plain wifi restart
	wouldn't fix. See README.md for the exact trigger logic and a sample log.
	Each check can be switched off per node (uci set linkcheck.<check>.disabled=1)
	and the reboot hold-off after a boot is adjustable
	(linkcheck.settings.reboot_uptime_min, default 60 minutes); both can be
	preset from the site.conf. The check name is part of the logged reboot
	reason, so it can be read off `logread -f`. See README.md.

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
	./gluonShellDiet.sh $(1)/lib/gluon/neanderfunk-linkcheck/linkcheck.sh
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

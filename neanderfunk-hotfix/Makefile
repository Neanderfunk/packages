include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-hotfix
PKG_VERSION:=1

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  SECTION:=gluon
  CATEGORY:=Workaround
  TITLE:=Hotfix collection: reinit wifi or reboot on various failure conditions (Ruben Kelevra & Eulenfunk)
  DEPENDS:=+gluon-core +micrond
endef

define Package/$(PKG_NAME)/description
	Four independent micrond jobs that detect and work around conditions a node
	otherwise wouldn't recover from on its own: no gateway/no wifi clients for
	a while (reboot), batman-adv/atheros driver "deadly wounded" states, too
	many stray tunneldigger instances, a hung `iw` call, or hostapd processes
	with stale pid files (restart wifi/hostapd). See README.md for details on
	each check.
	Each check can be switched off per node (uci set hotfix.<check>.disabled=1)
	and the reboot hold-off after a boot is adjustable
	(hotfix.settings.reboot_uptime_min, default 60 minutes); both can be
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
	./gluonShellDiet.sh $(1)/lib/gluon/neanderfunk-hotfix/rebootIfNoGw.sh 
	./gluonShellDiet.sh $(1)/lib/gluon/neanderfunk-hotfix/healthcheck.sh
	./gluonShellDiet.sh $(1)/lib/gluon/neanderfunk-hotfix/check_hostapd.sh
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

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
	Micrond jobs that detect and work around conditions a node otherwise
	wouldn't recover from on its own, all of them about the health of this box
	rather than the network around it: batman-adv/atheros driver "deadly
	wounded" states, too many stray tunneldigger instances, hostapd processes
	with stale pid files, an AP whose clients have all disappeared, br-client
	without an address from the site prefix, respondd or dropbear gone, and a
	deadman watchdog for micrond itself. Checks about the network - gateway,
	anycast, mesh neighbours, bridge ports - live in neanderfunk-linkcheck.
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

# Ueber Globs statt ueber eine Dateiliste: die Liste war zuletzt unvollstaendig
# (common.sh, IfNoWificlient.sh und watchdog.sh gingen ungestrippt ins Image,
# allein die common.sh mit 7 KB reinem Kommentar), und eine Liste, die man beim
# Anlegen einer Datei von Hand nachziehen muss, wird wieder unvollstaendig.
define Package/$(PKG_NAME)/install
	$(CP) ./files/* $(1)/
	./gluonShellDiet.sh $(1)/lib/gluon/neanderfunk-hotfix/*.sh \
	                    $(1)/lib/gluon/upgrade/500-neanderfunk-hotfix \
	                    $(1)/usr/lib/autoupdater/*/20neanderfunk-hotfix
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

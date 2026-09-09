include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-linkcheck
PKG_VERSION:=2

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  SECTION:=gluon
  CATEGORY:=Gluon
  TITLE:=WIFI and batman Neighborcheck
  DEPENDS:=+neanderfunk-common +gluon-core +micrond
endef

define Package/$(PKG_NAME)/description
	Watches everything about the network around the node: wifi/lan mesh links,
	batman interfaces, bridges and their ports for neighbours or members going
	missing after having been seen before, plus the batman gateway and the
	IPv6 anycast address. A link that stays an "island" escalates from a wifi
	restart to a reboot, which recovers crashed or wedged drivers that a plain
	wifi restart wouldn't fix. A check only ever arms once it has seen the
	thing working, so a node that is legitimately alone never escalates.
	See README.md for the exact trigger logic and a sample log.
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

# Glob statt Dateiliste: die common.sh fehlte in der Liste und ging mit 5,9 KB
# reinem Kommentar ungestrippt ins Image.
define Package/$(PKG_NAME)/install
	$(CP) ./files/* $(1)/
	./gluonShellDiet.sh $(1)/lib/gluon/neanderfunk-linkcheck/*.sh \
	                    $(1)/lib/gluon/upgrade/500-neanderfunk-linkcheck
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

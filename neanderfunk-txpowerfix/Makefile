include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-txpowerfix
PKG_VERSION:=1

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  SECTION:=admin
  CATEGORY:=Workaround
  DEPENDS:=+wireless-tools
  TITLE:=Fixes txpower on some wifi nodes since OpenWrt chaos calmer
endef

define Package/$(PKG_NAME)/description
  With chaoscalmer, wifi nodes seemed to be locked to less txpower than they could send.
  First suggestions are, that this is a mistake in the upstream OpenWrt-Code. Even the
  bugtrackers of OpenWrt are full of this.
  The idea of this workaround is to derive a suitable regulatory country (DE/JP/TW/US,
  based on the configured channels) and re-query the maximum available txpower/htmode
  under it, since the shipped defaults are often more conservative than necessary. Runs
  as a normal gluon-reconfigure upgrade script (every firmware upgrade, not just once),
  since whether this actually helps is chipset-dependent and can't be detected up front.
  iwinfo/iw calls are run with a 20s kill-9 timeout so a chipset that hangs on them
  can't block the whole reconfigure run.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

# Die Datei ist Lua (#!/usr/bin/lua), nicht Shell. Sie lag unter files/ und
# wurde mit gluonShellDiet.sh behandelt - einem sed, das Zeilen mit '#'
# entfernt. Lua kommentiert mit '--', der Aufruf entfernte also exakt null
# Zeilen. Jetzt liegt sie unter luasrc/ und geht durch Gluons eigenen
# Lua-Minifier, so wie es neanderfunk-wifi-blackout im selben Feed macht.
define Build/Compile
	$(call GluonSrcDiet,./luasrc,$(PKG_BUILD_DIR)/luadest/)
endef

define Package/$(PKG_NAME)/install
	$(CP) $(PKG_BUILD_DIR)/luadest/* $(1)/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

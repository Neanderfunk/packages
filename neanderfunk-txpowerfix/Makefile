include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-txpowerfix
PKG_VERSION:=1

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  SECTION:=admin
  CATEGORY:=Workaround
  DEPENDS:=+gluon-core +libiwinfo-lua
  TITLE:=Regulatory country and widest HT mode per radio, no txpower pinning
endef

define Package/$(PKG_NAME)/description
  Derives a regulatory country (DE/JP/TW/US) from the configured channels and
  sets the widest HT mode the hardware offers per radio. Runs as a normal
  gluon-reconfigure upgrade script, including the one triggered by the config
  mode's "Save & restart", and only writes config: no wifi restart, no iwinfo
  command, no sleep - uhttpd kills the config-mode CGI after 60 s.
  It no longer pins txpower and removes existing pins: without one the kernel
  already uses min(hardware, regulatory limit) for the current channel. To keep
  a deliberately set txpower across updates:
    uci set gluon.wireless.preserve_txpower='1'
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

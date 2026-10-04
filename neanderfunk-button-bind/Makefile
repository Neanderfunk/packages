include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-button-bind
PKG_VERSION:=1
PKG_RELEASE:=1

PKG_LICENSE:=MIT

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  TITLE:=Button feature set binding
  DEPENDS:=+gluon-web-admin
  # Ported from ffffm-button-bind (Freifunk Frankfurt am Main, MIT, see
  # LICENSE and README.md). Installs the same paths and takes over the same
  # rfkill handler, so the two must never end up in one image.
  CONFLICTS:=ffffm-button-bind
  MAINTAINER:=Freifunk im Neanderland <projekt@neanderfunk.de>
endef

define Package/$(PKG_NAME)/description
	Lets the node owner pick what the router's wifi button does, in config
	mode: wifi on/off, nothing at all (the default), a wifi reset, or a night
	mode that keeps the LEDs dark and only lights them while the button is
	held. Takes over /etc/rc.button/rfkill and keeps OpenWrt's original
	handler as rfkill.owrt for the default case.
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))

include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-txpowerfix
PKG_VERSION:=4

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  TITLE:=Regulatory country and htmode from the channels, no pinned txpower
  DEPENDS:=+gluon-core
  CONFLICTS:=gluon-txpowerfix
endef

define Package/$(PKG_NAME)/description
  Sets a regulatory country per radio derived from the configured channels
  (DE/JP/TW/US) and the widest HT mode the hardware offers. Removes pinned
  txpower values once per node and never sets one. Port of
  neanderfunk-txpowerfix from v2025.1.x.
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))

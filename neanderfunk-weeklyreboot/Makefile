include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-weeklyreboot
PKG_VERSION:=2

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  SECTION:=gluon
  CATEGORY:=Gluon
  TITLE:=weekly reboot scheduled on thursdays
  DEPENDS:=+gluon-core +micrond
endef

define Package/$(PKG_NAME)/description
	Reboots the node once a week, Thursday morning between 3:15 and 6:00 at a
	random time, to clear up long-running memory/state issues before they
	become a problem. Skips the reboot if the autoupdater is mid-run.
	Schedule is fixed (files/usr/lib/micron.d/weeklyreboot), not configurable
	via site.conf.
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
	./gluonShellDiet.sh $(1)/lib/gluon/weeklyreboot/weeklyreboot.sh
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

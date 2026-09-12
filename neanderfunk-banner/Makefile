include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-banner
PKG_VERSION:=3
PKG_RELEASE:=$(GLUON_VERSION).$(GLUON_SITE_CODE)-$(GLUON_RELEASE).$(GLUON_CONFIG_VERSION)

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  SECTION:=neanderfunk
  CATEGORY:=Customization
  TITLE:=Banner file replacement
  DEPENDS:=+gluon-core +gluon-neighbour-info +busybox
  # ffmuc-custom-banner also owns /etc/banner.gluon and also replaces the login
  # banner, just by templating it from an upgrade script instead of symlinking.
  # Both installed at once would clobber each other's file.
  CONFLICTS:=ffmuc-custom-banner
  MAINTAINER:=Eulenfunk www.eulenfunk.de Andreas Dorfer
  URL:=https://github.com/Neanderfunk/packages
  SOURCE:=https://github.com/Neanderfunk/packages.git
endef

define Package/$(PKG_NAME)/description
	Replaces /etc/banner and /etc/profile (as reversible symlinks, restored
	on removal) with a Gluon login banner. The profile runs OpenWrt's own
	profile first and then, in interactive shells only, nodestatus: an
	80-column overview of what is actually running - node, firmware, ports,
	VPN, gateway, clients, radios (live channel, width, mode, tx power) and
	mesh neighbours - followed by warnings. Also installs admin commands:
	nodestatus, nodeinfo (details), switch0/switchstatus (port table, also
	on DSA), lanrole/wanrole (show or set the Gluon interface role),
	reconf (gluon-reconfigure and reboot in the background), v4up (IPv4
	via the mesh, refused if the uplink has IPv4), flash (download a firmware
	image by URL, or find it in a directory URL, check it, stop services like
	the autoupdater when RAM is low, sysupgrade; in interactive shells
	"sysupgrade <url>" does the same), help.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/preinst
#!/bin/sh
cd "$${IPKG_INSTROOT}/etc/"
# Back up the original file exactly once, ever. Guarded by ".openwrt" already
# existing so a re-install/upgrade (banner/profile already our symlink from a
# prior install) can never re-run this and clobber the one true backup with
# whatever transient content happened to be there instead.
if [ ! -e "./banner.openwrt" ] && [ -f "./banner" ] && [ ! -h "./banner" ] ; then
	/bin/mv "./banner" "./banner.openwrt"
fi
if [ ! -e "./profile.openwrt" ] && [ -f "./profile" ] && [ ! -h "./profile" ] ; then
	/bin/mv "./profile" "./profile.openwrt"
fi
exit 0
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
cd "$${IPKG_INSTROOT}/etc/"
/bin/rm -f "./banner"
/bin/ln -s "./banner.gluon" "./banner"
/bin/rm -f "./profile"
/bin/ln -s "./profile.gluon" "./profile"
exit $$?
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
cd "$${IPKG_INSTROOT}/etc/"
if [ -h "./banner" ] ; then
	[[ "$$(readlink -n ./banner)" == "./banner.gluon" ]] && \
	/bin/rm -f "./banner" && \
	[ -f "./banner.openwrt" ] && \
	/bin/ln -s "./banner.openwrt" "./banner"
fi
if [ -h "./profile" ] ; then
	[[ "$$(readlink -n ./profile)" == "./profile.gluon" ]] && \
	/bin/rm -f "./profile" && \
	[ -f "./profile.openwrt" ] && \
	/bin/ln -s "./profile.openwrt" "./profile"
fi
exit 0
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/etc/
	$(INSTALL_DATA) ./files/etc/banner.gluon $(1)/etc/
	$(INSTALL_DATA) ./files/etc/profile.gluon $(1)/etc/
	$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

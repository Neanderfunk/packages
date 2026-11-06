include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-ddhcpd
PKG_VERSION:=1
PKG_RELEASE:=5

# Daemon aus unserem Fork, Zweig neanderfunk (siehe dort NEANDERFUNK.md).
# Die Paketdateien stammen aus ffgraz-ddhcpd der Gluon-community-packages
# (61fd9019e013, Maciej Krueger, MIT); siehe README.md.
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/Neanderfunk/ddhcpd.git
PKG_SOURCE_DATE:=2026-11-06
PKG_SOURCE_VERSION:=300e5ecf19d897f3210a1f36fd1e26c5f6af897f

PKG_MAINTAINER:=Freifunk im Neanderland <projekt@neanderfunk.de>
PKG_LICENSE:=GPL-3.0 MIT

PKG_BUILD_PARALLEL:=1

TARGET_CFLAGS += -DLOG_LEVEL_LIMIT=5
# Zaehler fuer Roaming und DHCP (ddhcpdctl -s/-m, respondd)
TARGET_CFLAGS += -DDDHCPD_STATISTICS

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  TITLE:=ddhcpd, verteilter DHCP-Server auf den Knoten (Fork von ffgraz-ddhcpd)
  DEPENDS:=+gluon-core +libnl-tiny
  # Beide installieren /usr/sbin/ddhcpd, /etc/init.d/ddhcpd und /etc/config/ddhcpd.
  CONFLICTS:=ffgraz-ddhcpd
endef

define Package/$(PKG_NAME)/description
	Verteilter DHCP-Server: Die Knoten einer Domain teilen sich einen
	IPv4-Bereich in Bloecken und vergeben Adressen an ihre Clients selbst.
	Ein- und ausgeschaltet, Bereich, Netzmaske, Router und DNS kommen je
	Domain aus der site/domain-Konfiguration (ddhcpd = { ... }). Ohne
	enabled = true in der Domain laeuft der Daemon nicht. Details in
	README.md.
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/ddhcpd
endef

define Build/Compile
	$(call Gluon/Build/Compile)
	CFLAGS="$(TARGET_CFLAGS)" LIBNL_NAME=libnl-tiny BUILD_DIR="$(BUILD_DIR)" $(MAKE) -C $(PKG_BUILD_DIR) $(TARGET_CONFIGURE_OPTS)
endef

define Package/$(PKG_NAME)/install
	$(call Gluon/Build/Install,$(1))
	$(INSTALL_DIR) $(1)/usr/sbin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/ddhcpd $(1)/usr/sbin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/ddhcpdctl $(1)/usr/sbin/
endef

# BuildPackageGluon, damit check_site.lua beim Bau laeuft (ffgraz-ddhcpd nahm
# BuildPackage, dort wurde check_site nie aufgerufen).
$(eval $(call BuildPackageGluon,$(PKG_NAME)))

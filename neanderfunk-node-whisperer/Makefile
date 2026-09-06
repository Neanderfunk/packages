include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-node-whisperer
PKG_RELEASE:=1

# Upstream bleibt gepinnt und unveraendert; unsere Aenderungen liegen als
# Patches daneben. Ein Backport ist damit: PKG_SOURCE_VERSION/-DATE hochziehen,
# Patches neu anwenden, Konflikte anschauen. Siehe README.md.
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL=https://github.com/blocktrron/node-whisperer.git
PKG_SOURCE_DATE:=2024-11-09
PKG_SOURCE_VERSION:=8f1e5560ce2e9319083004af4b6bfd87e4d246b3

PKG_MAINTAINER:=Freifunk im Neanderland <projekt@neanderfunk.de>
PKG_LICENSE:=GPL-2.0-or-later

include $(TOPDIR)/../package/gluon.mk

MAKE_PATH:=src
MAKE_VARS += \
	NL_LIB="libnl-tiny" \
	NL_GENL_LIB="libnl-tiny"

Build/Compile=$(call Build/Compile/Default)

define Package/$(PKG_NAME)
  TITLE:=Diagnoseinformationen ueber WLAN-Beacons (Fork von ffda-node-whisperer)
  DEPENDS:=+gluon-core +libubox +libubus +libblobmsg-json +libnl-tiny +libbatadv +libgluonutil
  # Beide gleichzeitig ergaeben zwei Daemons, die dieselben Interfaces mit
  # Vendor-Elementen bespielen. Die Dateinamen kollidieren zwar nicht mehr,
  # der Konflikt bleibt aber inhaltlich bestehen.
  CONFLICTS:=ffda-node-whisperer
endef

define Package/$(PKG_NAME)/description
	Kodiert Statusinformationen eines Gluon-Knotens in die Beacons der
	Client-WLANs, auslesbar mit der App NodeMonitor. Fork von
	ffda-node-whisperer aus den community-packages, mit zwei lokalen
	Korrekturen: eine fehlende Domain wird nicht mehr als Fehler ins Syslog
	geschrieben, und das Byte, das die App als "Gateway" anzeigt, traegt jetzt
	den TQ des tatsaechlich gewaehlten Batman-Gateways statt des TQ eines
	mesh-vpn-Nachbarn. Drahtformat und App bleiben unveraendert. Details und
	die Backport-Anleitung stehen in README.md.
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/neanderfunk-node-whisperer
endef

# Alle installierten Pfade tragen den Paketnamen, damit nichts mit
# ffda-node-whisperer oder einem anderen Paket kollidiert.
define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin $(1)/etc/init.d $(1)/etc/config $(1)/lib/gluon/upgrade
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/node-whisperer $(1)/usr/bin/neanderfunk-node-whisperer
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/openwrt/node-whisperer/files/node-whisperer.init $(1)/etc/init.d/neanderfunk-node-whisperer
	$(CP) $(PKG_BUILD_DIR)/openwrt/node-whisperer/files/node-whisperer.uci $(1)/etc/config/neanderfunk-node-whisperer
	$(INSTALL_BIN) ./files/node-whisperer.upgrade.lua $(1)/lib/gluon/upgrade/150-neanderfunk-node-whisperer
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))

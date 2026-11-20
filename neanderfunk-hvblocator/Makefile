# SPDX-License-Identifier: BSD-3-Clause
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-hvblocator
PKG_VERSION:=0.2
PKG_RELEASE:=1
PKG_LICENSE:=BSD-3-Clause

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  TITLE:=Lokator und Abschleppdienst fuer Halteverbots-Defaultdomain
  DEPENDS:=+gluon-core +neanderfunk-common +gluon-mesh-batman-adv \
	+gluon-neighbour-info +micrond +iw +uclient-fetch
  MAINTAINER:=Neanderfunk <technik@neanderfunk.de>
  URL:=https://github.com/Neanderfunk/packages
endef

define Package/$(PKG_NAME)/description
	Lokator und Abschleppdienst fuer die Halteverbots-Defaultdomain. Nur
	aktiv in einer Domain, deren Domain-Datei neanderfunk_hvblocator.urls
	setzt: Der Knoten scannt die WLANs der Umgebung, fragt seine
	LAN-Mesh-Nachbarn nach ihrer Domain und meldet beides per POST an den
	Locator, einmal bald nach dem Start und danach taeglich. Haengen am
	Kabel Nachbarn genau einer anderen Domain, die im Image steht, schaltet
	er selbst dorthin um. Verschoben wird sonst nur ueber den nodeplacer.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))

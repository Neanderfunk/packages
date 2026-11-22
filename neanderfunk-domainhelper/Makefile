# SPDX-License-Identifier: BSD-3-Clause
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-domainhelper
PKG_VERSION:=0.12
PKG_RELEASE:=1
PKG_LICENSE:=BSD-3-Clause

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk
include ../neanderfunk.mk

define Package/$(PKG_NAME)
  TITLE:=Hilfen rund um die Domain eines Knotens
  DEPENDS:=+gluon-core +neanderfunk-common +gluon-mesh-batman-adv \
	+gluon-neighbour-info +micrond +iw +uclient-fetch \
	+jsonfilter +jshn
  MAINTAINER:=Neanderfunk <technik@neanderfunk.de>
  URL:=https://github.com/Neanderfunk/packages
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/neanderfunk-domainhelper
endef

define Package/$(PKG_NAME)/description
	Hilfen rund um die Domain eines Knotens, in Shell.
	locate: Lokator und Abschleppdienst fuer die Halteverbots-Defaultdomain.
	Nur aktiv in einer Domain, deren Domain-Datei
	neanderfunk_domainhelper.locator.urls setzt: Der Knoten scannt die WLANs
	der Umgebung, fragt seine LAN-Mesh-Nachbarn nach ihrer Domain und meldet
	beides per POST an den Locator, einmal bald nach dem Start und danach
	taeglich. Haengen am Kabel Nachbarn genau einer anderen Domain, die im
	Image steht, schaltet er selbst dorthin um.
	bridge: Domain-Bruecken am LAN-Mesh erkennen und, wenn beide Seiten
	einen eigenen Uplink haben, zur Laufzeit bis zum naechsten Neustart
	trennen (ebtables bzw. ifdown, kein uci commit), in allen Domains,
	alle 91 s als procd-Dienst.
	island: steht lange kein Gateway in Sicht, Kanal auf ein Mesh der
	eigenen Domain stellen (nach 60 min) oder Domain und Kanal wechseln
	(nach 600 min, in 25_hvb beides nach 5 min), nicht zu Knoten mit
	Offline-SSID.
	follow: ohne eigenes VPN nach 60 min der Domain folgen, aus der das
	Netz ueber das Kabel kommt; WLAN-Kanaele bleiben.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))

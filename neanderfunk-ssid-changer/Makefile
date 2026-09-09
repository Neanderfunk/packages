# SPDX-FileCopyrightText: 2023 Malte Möller, Jens Viisauksena, Ruben Barkow, Andreas Ziegler, Sven Eckelmann, Andreas Dorfer and Florian Maurer
# SPDX-License-Identifier: BSD-2-Clause
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-ssid-changer
PKG_VERSION:=5
PKG_RELEASE:=1

PKG_LICENSE:=BSD-2-Clause

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  TITLE:=changes the SSID to an Offline-SSID so clients don't connect to an offline WiFi
  DEPENDS:=+neanderfunk-common +gluon-web-admin +gluon-state-check +micrond
  # This is a fork of ffac-ssid-changer and installs the exact same six paths
  # (/etc/config/ssid-changer, the micron.d entry, the upgrade script, the
  # worker and both config-mode files), shares its /tmp state files, and would
  # fight over the same SSID. gluon-ssid-changer is the older shell variant this
  # feed used to carry, same paths again. Any of them together with this one is
  # a mistake, so let the package manager say so instead of relying on whoever
  # edits image-customization.lua to know.
  CONFLICTS:=ffac-ssid-changer gluon-ssid-changer
endef

define Package/$(PKG_NAME)/description
  Script to change the SSID to an Offline-SSID when there is no connection to
  any gateway. This SSID can be generated from the node's hostname with the
  first and last part of the nodename or the mac address, to allow observers to
  recognize which node is down. The script is called once a minute by micrond
  and it will change from online to Offline-SSID once per definable timeframe at
  most.
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))

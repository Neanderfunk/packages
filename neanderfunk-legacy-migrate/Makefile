# SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
# SPDX-License-Identifier: BSD-3-Clause
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-legacy-migrate
PKG_VERSION:=1
PKG_LICENSE:=BSD-3-Clause

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  TITLE:=Migrate configs of old Gluon versions (2015.1 to 2021.1) on the jump to 2025.1
  DEPENDS:=+gluon-core
endef

define Package/$(PKG_NAME)/description
  Upgrade scripts that redo the config migrations Gluon removed (hwmode to
  band, mesh on WAN/LAN to roles, VPN switch and bandwidth limit, IBSS mesh,
  preserve_channels, old firewall zones, sysctl.conf, foreign autoupdater
  branches), and on x86 bind LAN/WAN to the network card (PCI path and
  hardware MAC) instead of ethN. See router-werkstatt
  docs/gluon-migrationspfade.md.
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))

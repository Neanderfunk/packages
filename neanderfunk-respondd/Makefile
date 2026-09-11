# SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
# SPDX-License-Identifier: BSD-3-Clause
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-respondd
PKG_VERSION:=1
PKG_LICENSE:=BSD-3-Clause

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  TITLE:=respondd module: hardware, radios, offline SSID and ethernet links
  DEPENDS:=+gluon-respondd +libiwinfo +libuci +libjson-c
endef

define Package/$(PKG_NAME)/description
  Adds "neanderfunk" to respondd nodeinfo (CPU model, flash size, BIOS,
  preserve_channels) and statistics (per radio the live channel, HT mode,
  SSID, tx power, country and mesh state; the offline-SSID counters of
  neanderfunk-ssid-changer; link, speed, duplex and a damaged-cable hint per
  ethernet port). Written in C to stay cheap: the status page polls
  statistics every 3 seconds.
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))

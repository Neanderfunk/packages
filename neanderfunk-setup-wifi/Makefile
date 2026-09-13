# SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
# SPDX-License-Identifier: BSD-3-Clause
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-setup-wifi
PKG_VERSION:=1
PKG_LICENSE:=BSD-3-Clause

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  TITLE:=Setup WLAN setup.gluon_<MAC> in config mode, configurable by site.conf
  DEPENDS:=+gluon-setup-mode
endef

define Package/$(PKG_NAME)/description
  In config mode, an AP setup.gluon_<last 4 hex digits of the primary MAC>
  in a bridge of its own (198.51.100.1/24) with a dnsmasq that answers every
  name with the node, so phones open the setup page as a captive portal.
  site.conf setup_mode.wifi: start 'off' | 'boot' | 'button' (short press),
  security 'wpa2' | 'open' (open only with 'button'), key (WPA2: key plus
  the first MAC byte), timeout in seconds. Without the block: at boot, WPA2
  freifunk_<byte>, off after 1200 s. Needs the firmware patch that binds the
  first dnsmasq of the config mode to br-setup.
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))

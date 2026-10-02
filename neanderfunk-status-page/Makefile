# SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
# SPDX-License-Identifier: BSD-3-Clause
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-status-page
PKG_VERSION:=1
PKG_LICENSE:=BSD-3-Clause

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  TITLE:=Translations and helpers for the Neanderfunk additions to the status page
  DEPENDS:=+gluon-status-page +gluon-neighbour-info
endef

define Package/$(PKG_NAME)/description
  Translation catalog for the lines the Neanderfunk status-page patches add
  (gluon-patches-packages, status-page/): temperature, offline SSID and its
  counters, extra hardware details. The patched template reads them with
  i18n('neanderfunk-status-page'), so Gluon's own gluon-status-page catalog
  stays untouched. Without this package the lines fall back to English.

  Also ships cgi-bin/dyn/gateway-name: the hostname of a batman gateway,
  asked from the gateway itself via respondd (patch
  statuspage-gateway-name). Without it the page shows the MAC as before.
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))

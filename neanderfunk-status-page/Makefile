# SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
# SPDX-License-Identifier: BSD-3-Clause
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-status-page
PKG_VERSION:=1
PKG_LICENSE:=BSD-3-Clause

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  TITLE:=Translations for the Neanderfunk additions to the status page
  DEPENDS:=+gluon-status-page
endef

define Package/$(PKG_NAME)/description
  Translation catalog for the lines the Neanderfunk status-page patches add
  (gluon-patches-packages, status-page/): temperature, offline SSID and its
  counters, extra hardware details. The patched template reads them with
  i18n('neanderfunk-status-page'), so Gluon's own gluon-status-page catalog
  stays untouched. Without this package the lines fall back to English.
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))

# SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
# SPDX-License-Identifier: BSD-3-Clause
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-config-mode-theme
PKG_VERSION:=1
PKG_LICENSE:=BSD-3-Clause

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  TITLE:=Config mode theme: responsive, dark mode, Freifunk colours
  DEPENDS:=+gluon-core +gluon-web
  PROVIDES:=gluon-config-mode-theme
endef

define Package/$(PKG_NAME)/description
  Replaces gluon-config-mode-theme: layout and stylesheet of the config mode,
  responsive down to phone width, with a dark mode that follows the browser.
  Covers every page that goes through the layout - wizard, advanced
  settings, information, firmware upgrade and the error pages.
  Both packages ship view/theme/layout.html, so the site has to drop
  Gluon's theme: packages {'-gluon-config-mode-theme', '$(PKG_NAME)'}.
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))

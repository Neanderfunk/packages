# SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
# SPDX-License-Identifier: BSD-3-Clause
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-setup-mode
PKG_VERSION:=1
PKG_LICENSE:=BSD-3-Clause

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  TITLE:=Config mode on one page: wizard and advanced settings, one save
  DEPENDS:=+gluon-config-mode-core +gluon-web-model +neanderfunk-config-mode-theme
endef

define Package/$(PKG_NAME)/description
  Replaces the wizard page of the config mode by one page holding the wizard
  and every form of "Advanced settings", saved together by a single
  "Save & restart": all forms valid or nothing is written, only changed
  forms are written, the wizard last. The forms themselves are Gluon's and
  the packages' own; information and firmware upgrade stay pages of their
  own. Needs neanderfunk-config-mode-theme (and so -gluon-config-mode-theme).
  Without this package the regular wizard is back.
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))

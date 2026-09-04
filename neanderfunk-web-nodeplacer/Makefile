# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Neanderfunk / Eulenfunk
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-web-nodeplacer
PKG_VERSION:=0.1
PKG_RELEASE:=1
PKG_LICENSE:=BSD-2-Clause

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/neanderfunk-web-nodeplacer
  TITLE:=Config-mode web UI for nodeplacer (owner opt-out)
  DEPENDS:=+gluon-web-admin +neanderfunk-nodeplacer
  MAINTAINER:=Neanderfunk <technik@neanderfunk.de>
endef

define Package/neanderfunk-web-nodeplacer/description
	Adds a tab to the config-mode "Advanced settings" page that lets the
	node owner allow or forbid automatic domain moves controlled by
	nodeplacer (nodeplacer.settings.disable).
endef

$(eval $(call BuildPackageGluon,neanderfunk-web-nodeplacer))

# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Neanderfunk / Eulenfunk
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-common
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_LICENSE:=BSD-2-Clause

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/neanderfunk-common
  SECTION:=gluon
  CATEGORY:=Workaround
  TITLE:=Shared helpers for the neanderfunk packages
  DEPENDS:=+gluon-core
  MAINTAINER:=Neanderfunk <technik@neanderfunk.de>
endef

define Package/neanderfunk-common/description
	Bausteine, die mehrere neanderfunk-Pakete brauchen und die deshalb nicht
	in jedem einzelnen liegen sollen. Derzeit die Prozesssuche: nf-ps und
	nf-pgrep blenden die eigene Prozessgruppe aus, damit ein Check nicht sich
	selbst oder den aufrufenden Shell-Prozess findet. Siehe README.md.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(CP) ./files/* $(1)/
	./gluonShellDiet.sh $(1)/lib/gluon/neanderfunk/*.sh $(1)/usr/bin/nf-ps $(1)/usr/bin/nf-pgrep
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

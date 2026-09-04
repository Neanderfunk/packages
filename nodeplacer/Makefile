# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Neanderfunk / Eulenfunk
include $(TOPDIR)/rules.mk

PKG_NAME:=nodeplacer
PKG_VERSION:=0.1
PKG_RELEASE:=1
PKG_LICENSE:=BSD-2-Clause

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/nodeplacer
  TITLE:=Move individual nodes to another domain, controlled by a signed manifest
  DEPENDS:=+gluon-core +autoupdater +micrond \
	+libgluonutil +libjson-c +libubox +libuclient +libuci +libecdsautil
  CONFLICTS:=+gluon-hoodselector
  MAINTAINER:=Neanderfunk <technik@neanderfunk.de>
endef

define Package/nodeplacer/description
	Nodes periodically fetch a signed manifest (same signing tools and keys
	as the autoupdater manifest) from the community's servers. A node that
	finds its own node id listed switches to the requested domain: either
	locally (multi-domain firmware, gluon-switch-domain) or by installing
	the target domain's firmware via the regular autoupdater.
endef

define Package/nodeplacer/conffiles
/etc/config/nodeplacer
endef

$(eval $(call BuildPackageGluon,nodeplacer))

# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Neanderfunk / Eulenfunk
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-nodeplacer
PKG_VERSION:=0.1
PKG_RELEASE:=1
PKG_LICENSE:=BSD-2-Clause

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/neanderfunk-nodeplacer
  TITLE:=Move individual nodes to another domain, controlled by a signed manifest
  DEPENDS:=+gluon-core +autoupdater +micrond +gluon-web-admin \
	+libgluonutil +libjson-c +libubox +libuclient +libuci +libecdsautil
  CONFLICTS:=gluon-hoodselector
  MAINTAINER:=Neanderfunk <technik@neanderfunk.de>
endef

define Package/neanderfunk-nodeplacer/description
	Nodes periodically fetch a signed manifest (same signing tools and keys
	as the autoupdater manifest) from the community's servers. A node that
	finds its own node id listed switches to the requested domain: either
	locally (multi-domain firmware, gluon-switch-domain) or by installing
	the target domain's firmware via the regular autoupdater. Adds a tab
	to the config-mode "Advanced settings" page so node owners can opt out
	(nodeplacer.settings.disable); set nodeplacer.config_mode = false in
	site.conf to not register that tab at all. Without a nodeplacer block
	in site.conf the package is active with defaults: mirrors, keys and
	threshold of the autoupdater branch the node is running.
endef

define Package/neanderfunk-nodeplacer/conffiles
/etc/config/nodeplacer
endef

$(eval $(call BuildPackageGluon,neanderfunk-nodeplacer))

# SPDX-License-Identifier: BSD-3-Clause
# SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-default-hostname
PKG_VERSION:=1
PKG_LICENSE:=BSD-3-Clause

include $(TOPDIR)/../package/gluon.mk

define Package/neanderfunk-default-hostname
  TITLE:=Default hostname from the model short name and the last four digits of the node ID
  DEPENDS:=+gluon-core
  MAINTAINER:=Neanderfunk <technik@neanderfunk.de>
endef

define Package/neanderfunk-default-hostname/description
  New nodes get <hostname_prefix><model>-<last 4 of node_id> as their first
  hostname, e.g. "dias-WDR3600-1b8c" instead of "dias-6466b3ce1b8c". The model
  short name is derived from the Gluon image name. Needs the patch
  hostname/default-hostname from gluon-patches-packages, which makes
  gluon.util.default_hostname() call this module; without the patch the
  package does nothing. Existing nodes keep their hostname.
  Written for Gluon 2025.1.
endef

$(eval $(call BuildPackageGluon,neanderfunk-default-hostname))

# SPDX-License-Identifier: BSD-3-Clause
# SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-domain-from-legacy
PKG_VERSION:=1
PKG_LICENSE:=BSD-3-Clause

include $(TOPDIR)/../package/gluon.mk

define Package/neanderfunk-domain-from-legacy
  TITLE:=Pick the mesh domain of a node coming from a single-domain firmware
  DEPENDS:=+gluon-core
  MAINTAINER:=Neanderfunk <technik@neanderfunk.de>
endef

define Package/neanderfunk-domain-from-legacy/description
  On the first upgrade from a single-domain firmware to a multidomain one,
  Gluon has no gluon.core.domain and falls back to default_domain. This
  package recognises the old domain from the previous config (mesh ID,
  falling back to the next_node IPv4 address) by comparing it with the
  domain files in the image, and sets gluon.core.domain before Gluon's
  005-set-domain runs. Does nothing on single-domain images and once a
  domain is set. Written for Gluon 2025.1.
endef

$(eval $(call BuildPackageGluon,neanderfunk-domain-from-legacy))

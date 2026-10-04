# SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
# SPDX-License-Identifier: BSD-3-Clause
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-status-page
PKG_VERSION:=1
PKG_LICENSE:=BSD-3-Clause

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  TITLE:=Gateway hostname for the Neanderfunk status page
  DEPENDS:=+gluon-status-page +gluon-neighbour-info
endef

define Package/$(PKG_NAME)/description
  Ships cgi-bin/dyn/gateway-name: the hostname of a batman gateway, asked
  from the gateway itself via respondd (patch status-page/
  statuspage-neanderfunk in gluon-patches-packages v2021.1.x). Without it
  the page shows the MAC as before. Unlike v2025.1.x no translation
  catalog: the Sackgasse image is English only.
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))

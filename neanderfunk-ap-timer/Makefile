# SPDX-FileCopyrightText: 2023 kb-light, Michael Schwarz, Florian Maurer
# SPDX-License-Identifier: BSD-2-Clause
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-ap-timer
PKG_VERSION:=1
PKG_LICENSE:=BSD-2-Clause

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  TITLE:=Timer for the client wifi, with its config-mode page
  DEPENDS:=+gluon-core +gluon-web-admin +micrond
  # Fork of ff-ap-timer and ff-web-ap-timer (community-packages 91e5fa8), merged
  # into one package. Same paths (/etc/config/ap-timer, micron.d, the worker,
  # both config-mode files) and the same uci config - either original together
  # with this one would run the timer twice.
  CONFLICTS:=ff-ap-timer ff-web-ap-timer
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/ap-timer
endef

define Package/$(PKG_NAME)/description
  Turns the client wifi on and off on a set schedule (daily, weekly, monthly),
  with a config-mode page for the daily schedule. Mesh and private wifi are
  not touched.
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))

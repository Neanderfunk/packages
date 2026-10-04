# SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
# SPDX-License-Identifier: BSD-3-Clause
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-legacy-migrate
PKG_VERSION:=1
PKG_LICENSE:=BSD-3-Clause

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  TITLE:=Migrate configs of old Gluon versions (2015.1 to 2020.x) on the jump to 2021.1
  DEPENDS:=+gluon-core
endef

define Package/$(PKG_NAME)/description
  Upgrade script that redoes the config migrations Gluon removed before
  2021.1 (gluon-simple-tc, old firewall zones, sysctl.conf) and moves a
  foreign autoupdater branch to the site default. Backport of the v2025.1.x
  package; see router-werkstatt docs/gluon-migrationspfade.md.
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))

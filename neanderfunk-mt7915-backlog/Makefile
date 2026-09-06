# SPDX-FileCopyrightText: 2024 Felix Baumann, Florian Maurer (FFAC)
# SPDX-License-Identifier: MIT
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-mt7915-backlog
PKG_VERSION:=1
PKG_RELEASE:=1

PKG_LICENSE:=MIT

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  SECTION:=gluon
  CATEGORY:=Gluon
  TITLE:=reboot device if mt7915e driver shows known failure symptom
  DEPENDS:=@(TARGET_mediatek_filogic||TARGET_ramips_mt7621||TARGET_mediatek_mt7622) kmod-mt7915e +gluon-core +micrond
  MAINTAINER:=Freifunk im Neanderland <projekt@neanderfunk.de>
endef

define Package/$(PKG_NAME)/description
	Works around a known mt7915e firmware bug (freifunk-gluon/gluon#3154):
	once the driver's txq backlog fills up past 50 packets, the radio stops
	responding reliably over wifi. A micrond job checks the backlog every
	two minutes and restarts wifi before it gets that far. Only installed on
	mediatek-filogic/ramips-mt7621/mt7622 targets, and at runtime it looks
	only at radios actually driven by mt7915 - an mt7621 board may well
	carry different wifi. A cool-down keeps a backlog that does not clear
	from restarting wifi every two minutes; threshold, cool-down and the two
	uptime thresholds are configurable, and the check can be switched off
	per node (uci set mt7915backlog.settings.disabled=1). See README.md.
endef

# BuildPackageGluon would install ./files by itself; we take the default and add
# the comment stripping the other shell packages of this feed use. Measured on
# backlog.sh: 5265 -> 2138 bytes raw, 2400 -> 904 compressed. The comments stay
# in the repository, only the installed copy is stripped.
# $(Gluon/Build/Install) is Gluon's own default, used the same way by
# gluon-core, gluon-autoupdater and others.
define Package/$(PKG_NAME)/install
	$(Gluon/Build/Install)
	./gluonShellDiet.sh $(1)/lib/gluon/neanderfunk-mt7915-backlog/backlog.sh
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))

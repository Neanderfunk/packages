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

$(eval $(call BuildPackageGluon,$(PKG_NAME)))

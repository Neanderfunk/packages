# SPDX-License-Identifier: BSD-3-Clause
# SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-port-roles
PKG_VERSION:=1
PKG_LICENSE:=BSD-3-Clause

include $(TOPDIR)/../package/gluon.mk

define Package/neanderfunk-port-roles
  TITLE:=One role per network port, and how wired mesh ports are joined
  DEPENDS:=+gluon-core +gluon-web-admin
  MAINTAINER:=Neanderfunk <technik@neanderfunk.de>
endef

define Package/neanderfunk-port-roles/description
  Splits Gluon's interface sections that hold several ports (gluon.iface_lan
  with all LAN ports) into one section per port, so every port can have its
  own role (uplink, mesh, client, none) - on DSA switches and separate network
  interfaces; ports behind swconfig are left as they are.
  gluon.port_roles.mesh_mode chooses how LAN ports with the mesh role are
  joined: bridge, isolate (Gluon's default), separate (one bridge and one
  batman-adv interface per port) or auto (isolate where the switch can do it
  in hardware - mt7530/qca8k on kernel 6.6 - otherwise separate).
  Adds a "Ports" page to the config mode's Advanced settings.
  Written for Gluon 2025.1.
endef

$(eval $(call BuildPackageGluon,neanderfunk-port-roles))

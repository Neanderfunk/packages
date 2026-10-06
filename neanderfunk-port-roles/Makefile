# SPDX-License-Identifier: BSD-3-Clause
# SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-port-roles
PKG_VERSION:=2
PKG_LICENSE:=BSD-3-Clause

include $(TOPDIR)/../package/gluon.mk

define Package/neanderfunk-port-roles
  TITLE:=One role per network port, and how wired mesh ports are joined
  DEPENDS:=+gluon-core +gluon-web-admin
  MAINTAINER:=Neanderfunk <technik@neanderfunk.de>
endef

define Package/neanderfunk-port-roles/description
  A "Ports" page in the config mode's Advanced settings: one role per network
  port (uplink, mesh, client, none) on DSA switches and separate network
  interfaces, plus VLANs per port. Nothing changes until someone sets a port
  to a role other than its group's; then that port gets its own section
  gluon.iface_<port> (the same scheme as the portrole command), and setting
  it back puts it into the group again. Ports behind swconfig keep one role
  per group.
  gluon.port_roles.mesh_mode chooses how LAN ports with the mesh role are
  joined: isolate (Gluon's own way, the default), bridge, separate (one bridge
  and one batman-adv interface per port) or auto (isolate where the switch can
  do it in hardware - mt7530/qca8k on kernel 6.6 - otherwise separate).
  Written for Gluon 2025.1.
endef

$(eval $(call BuildPackageGluon,neanderfunk-port-roles))

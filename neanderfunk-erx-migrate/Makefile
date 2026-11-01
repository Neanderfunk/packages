include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-erx-migrate
PKG_VERSION:=1

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  SECTION:=gluon
  CATEGORY:=Gluon
  TITLE:=EdgeRouter X: Flash-Layout unattended migrieren
  DEPENDS:=+gluon-core +micrond +ecdsautils
endef

define Package/$(PKG_NAME)/description
	Stage 2 der ERX-Migration auf Gluon 2025.1.

	Der Kernel 6.6 aus OpenWrt 24.10 passt um 27 KB nicht mehr in einen der
	beiden alten 3-MB-Slots. OpenWrt gatet den Wechsel ueber compat_version
	1.x -> 2.0, und dieses Gate greift erst in "sysupgrade --test", also nach
	dem kompletten Download: ein nicht migrierter Knoten zieht bei jedem
	Autoupdater-Run dieselben 7 MB und bekommt denselben Reject.

	Dieses Paket reist in einem 2023.2-Intermediate-Image mit, das der ganz
	normale Autoupdater ausliefert (compat 1.x -> 1.x, funktioniert heute). Nach
	einer Stunde Uptime holt es das 2025.1-Image aus dem Manifest des Branches,
	prueft Signaturen und SHA256 und uebergibt an erx-migrate.sh, das Kernel und
	Rootfs ueber das alte Slot-Limit schreibt und den UBNT-Boot-Index umsetzt.

	Ohne Eintrag in /lib/gluon/erx-migrate/ziel.conf tut das Paket nichts. Kein
	Flash-Write, solange die Migration nicht wirklich laeuft; Log und Image
	liegen im RAM und werden bei jedem Failure weggeraeumt. Nach einem Reboot
	faengt alles von vorn an.

	Das Log ist ueber http://[<knoten>]/cgi-bin/erx-migrate-log abrufbar.

endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

# Globs statt Dateiliste, wie bei neanderfunk-hotfix: eine Liste, die beim
# Anlegen einer Datei von Hand nachgezogen werden muss, wird irgendwann
# unvollstaendig.
#
# ziel.conf ist absichtlich NICHT gestrippt - wer sie auf dem Geraet liest, soll
# die Erklaerung dazu finden.
define Package/$(PKG_NAME)/install
	$(CP) ./files/* $(1)/
	./gluonShellDiet.sh $(1)/usr/sbin/erx-migrate-run \
	                    $(1)/lib/gluon/status-page/www/cgi-bin/erx-migrate-log
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

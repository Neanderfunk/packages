include $(TOPDIR)/rules.mk

PKG_NAME:=neanderfunk-erx-migrate
PKG_VERSION:=1

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  SECTION:=gluon
  CATEGORY:=Gluon
  TITLE:=EdgeRouter X: Flash-Layout unbeaufsichtigt migrieren
  DEPENDS:=+gluon-core +micrond
endef

define Package/$(PKG_NAME)/description
	Stufe 2 der ERX-Migration auf Gluon 2025.1.

	Der Kernel 6.6 aus OpenWrt 24.10 passt um 27 KB nicht mehr in einen der
	beiden alten 3-MB-Slots. OpenWrt riegelt den Wechsel ueber compat_version
	1.x -> 2.0 ab, und dieser Riegel greift erst in "sysupgrade --test", also
	nach dem vollstaendigen Download: ein nicht migrierter Knoten zieht bei
	jedem Autoupdater-Lauf dieselben 7 MB und bekommt dieselbe Absage.

	Dieses Paket reist in einem 2023.2-Zwischenimage mit, das der ganz normale
	Autoupdater ausliefert (compat 1.x -> 1.x, funktioniert heute). Nach dem
	Boot holt es das 2025.1-Image, prueft die eingebackene SHA256 und uebergibt
	an erx-migrate.sh, das Kernel und Rootfs ueber die alte Slotgrenze schreibt
	und den UBNT-Boot-Index umsetzt.

	Ohne Eintrag in /lib/gluon/erx-migrate/ziel.conf tut das Paket nichts. Es
	schreibt nichts ins Flash, solange die Migration nicht wirklich laeuft; Log
	und Image liegen im RAM und werden bei jedem Fehlschlag weggeraeumt. Nach
	einem Neustart faengt alles von vorn an.

	Das Log ist ueber http://[<knoten>]/cgi-bin/erx-migrate-log?t=<token>
	abrufbar, wenn in ziel.conf ein Token steht.

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
# ziel.conf ist absichtlich NICHT gestrippt - sie wird beim Bau des
# Zwischenimages gefuellt, und wer sie auf dem Geraet liest, soll die
# Erklaerung dazu finden.
define Package/$(PKG_NAME)/install
	$(CP) ./files/* $(1)/
	./gluonShellDiet.sh $(1)/usr/sbin/erx-migrate-run \
	                    $(1)/lib/gluon/status-page/www/cgi-bin/erx-migrate-log
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
#
# Ein neues Gluon-Firmware-Verzeichnis (z. B. stable) aus zwei vorhandenen
# bauen: alles aus der Basis (z. B. einer aktuellen Gluon-Version), dazu aus
# dem Zusatz (z. B. der letzten Version fuer Geraete, die die Basis nicht mehr
# unterstuetzt) die Modelle, die in der Basis fehlen. Nur Symlinks, die
# Quellen bleiben unangetastet. Fuer jede Gluon-Community nutzbar: erwartet
# wird nur die uebliche Ablage <wurzel>/<domain>/{sysupgrade,factory,other}.
# Hilfe: manifeste-zusammenfuehren.sh --help

set -o nounset -o pipefail

hilfe() {
	cat <<'EOT'
manifeste-zusammenfuehren.sh - neues Firmware-Verzeichnis aus Basis + Zusatz
per Symlinks, mit neu erzeugten (unsignierten) Manifesten.

WAS DAS SKRIPT TUT
  Fuer jeden Domain-Ordner (auch die .key-Varianten), den Basis oder Zusatz
  hat, legt es im Ausgabeverzeichnis an:
    sysupgrade/  Symlinks auf alle Images der Basis, dazu die Images des
                 Zusatzes fuer Modelle, die im Basis-Manifest NICHT stehen
                 (Vergleich ueber den Modellnamen, also auch ueber die
                 Alias-Zeilen, die Gluon ins Manifest schreibt).
                 Dazu ein neues <branch>.manifest:
                   - Kopf BRANCH=<branch>, DATE=jetzt, PRIORITY aus der Basis
                   - alle 5-Feld-Zeilen der Basis und der ergaenzten Zusatz-
                     Modelle: <modell> <version> <sha256> <groesse> <datei>
                   - fuer Modellnamen, die es schon in der 4-Feld-Zeit gab
                     (Gluon v2014.1 bis v2017.1.x, Array ALT_MODELLE im
                     Skript), dazu wie Gluon 2018.1-2020.2:
                       <modell> <version> <sha256> <datei>   (2016.2.4-2017.1)
                       <modell> <version> <sha512> <datei>   (bis 2016.2)
                     Ausnahme CPE210/220/510/520 v1: deren 2016.2-sysupgrade
                     lehnt ath79-Images ab und der Knoten bleibt offline.
                   - alte Namen aus ALIAS_ALT (und -a), deren neuer Name in
                     der Basis steht, bekommen deren Image (vor dem Zusatz);
                     sonst, wenn weder Basis noch Zusatz sie fuehren, das
                     Image des neuen Namens aus dem Zusatz. Je nach Zeit
                     mit allen drei Zeilenformaten.
                   - x86 (generic, legacy, 64): siehe X86-ALTKNOTEN
                   - "---" ohne Unterschriften
                   Fuer jede Datei mit 4-Feld-Zeilen wird die sha256 gegen die
                   Datei geprueft und die sha512 aus der Datei berechnet.
    factory/, other/  Symlinks auf alle Dateien der Basis, dazu die Dateien
                 des Zusatzes, die zu einem ergaenzten Modell gehoeren
                 (Dateiname "...-<version>-<modell>.xxx" bzw. "-<modell>-xxx",
                 laengster passender Modellname gewinnt).
    andere Ordner (site/ usw.) und Dateien: Symlink auf die Basis, sonst auf
                 den Zusatz.
  Symlinks sind relativ und zeigen auf den Pfad in der Quelle (auch wenn der
  dort selbst ein Symlink ist). Die Quellverzeichnisse werden nur gelesen.

DANACH
  Die neuen Manifeste tragen KEINE Unterschrift. Neu unterschreiben:
  manifeste-unterschreiben.sh (beim Signer), dann
  manifest-signaturen-einspielen.sh (hier). Vorher pruefen:
  manifest-pruefen.sh <ausgabe>.

X86-ALTKNOTEN
  Gluon baut fuer x86 seit 2023.2 das EFI-Image (Bootpartition FAT). Gluon bis
  2021.1 (OpenWrt bis 19.07) legt beim sysupgrade die Konfiguration per
  "mount -t ext4" auf Partition 1 ab und verliert sie dort: der Knoten startet
  im Setup-Mode (Gluon #2967). Liegt in <basis>/<domain>/other/ zum
  x86-sysupgrade-Image ein "...-<target>-mbr-sysupgrade.img.gz" (MBR,
  Bootpartition ext4; Neanderfunk baut es seit gluon-patches-hardware
  a50d4b3), zeigen x86-Zeilen auf dieses Image, und es wird in sysupgrade/
  verlinkt:
    Vorgabe (-x alt): nur die 4-Feld-Zeilen; die lesen nur Knoten bis 2017.1.
      Fuer x86-generic nimmt das Skript dort das x86-legacy-MBR-Image, wenn
      die Basis eines hat: "generic" war bis Gluon 2016.2 i486-Klasse, seit
      2017.1 braucht es SSE2.
    -x alle: auch die 5-Feld-Zeilen. Nur fuer ein Verzeichnis, das allein
      alte Knoten lesen (eigene Mirror-URL oder eigener Zweig), denn neuere
      Knoten lesen dieselben Zeilen; ein UEFI-only-Rechner bootet kein MBR.
    -x aus: nichts umlenken.
  Fehlt das MBR-Image, meldet das Skript es fuer jede Domain mit x86 als
  Fehler (ausser -x aus). Danach wechselt der Knoten mit dem naechsten
  Release von selbst auf das EFI-Image (OpenWrt ab 21.02 erkennt FAT).
  Ablauf: router-werkstatt docs/howto-x86-altknoten-2025.md

GRENZEN
  - Ob die Basis-Firmware den Sprung von einem alten Stand aushaelt (Migration
    der Konfiguration), prueft das Skript nicht; das Manifest macht ihn nur
    moeglich. Alte Gluon-Versionen haben keine Versionssperre; was eine
    neuere Version an Konfiguration nicht mehr migriert, muss ein eigenes
    Skript in deren Image erledigen.
  - Alte Namen ohne Image (weder in den Manifesten noch per Alias) zaehlt das
    Skript am Ende auf; fuer sie hilft nur eine Zuordnung per -a.
  - Alte Lua-Autoupdater (bis 2016.2) pruefen BRANCH= gegen ihren Zweig:
    Das Manifest wirkt fuer sie nur, wenn <branch> ihr Zweig ist.

AUFRUF
  manifeste-zusammenfuehren.sh [optionen] -b <basis> -z <zusatz> -o <ausgabe>

  -b dir     Basis, z. B. /var/www/firmware/stable-v2023.2
  -z dir     Zusatz, z. B. /var/www/firmware/eol-v2021.1
  -o dir     Ausgabe, darf noch nicht existieren
  -B name    Zweig des neuen Manifests (Vorgabe: stable)
  -m datei   Manifest-Name in der Basis (Vorgabe: <branch>.manifest)
  -M datei   Manifest-Name im Zusatz (Vorgabe: das einzige *.manifest im
             sysupgrade-Ordner der Domain, sonst <branch>.manifest)
  -g dir     Abdeckung pruefen gegen einen Gluon-Quellbaum (Version des
             Zusatzes, z. B. ein Checkout von v2021.1.x): Am Ende stehen die
             Geraete aus dessen targets/, die im Ergebnis kein Image haben,
             je Target. Zeigt, welche Targets fuer den Zusatz noch gebaut
             werden muessten. Liest nur targets/ (Lua-Format ab v2019.1).
  -x modus   x86-Altknoten: alt (Vorgabe), alle oder aus, siehe X86-ALTKNOTEN
  -a datei   zusaetzliche Zuordnungen alter -> neuer Modellnamen, "alt neu"
             je Zeile, "#" als Kommentar. Die bekannten stehen schon im
             Skript (Array ALIAS_ALT), die Datei kommt nur dazu.
  -n         Probelauf: nur zaehlen und pruefen, nichts anlegen
  -h, --help diese Hilfe

BEISPIEL
  manifeste-zusammenfuehren.sh -n \
      -b /var/www/firmware/stable-v2023.2 \
      -z /var/www/firmware/eol-v2021.1 -M eol.manifest \
      -g ~/gluon-v2021.1.x \
      -o /var/www/firmware/stable-v2023.2+eol
  (dann ohne -n; den Symlink "stable" erst nach dem Unterschreiben umstellen)

VORAUSSETZUNGEN
  bash, awk, GNU realpath (coreutils), sha256sum/sha512sum

EXIT-CODES
  0  fertig
  1  Pruefung fehlgeschlagen (Image fehlt, sha256 passt nicht, Link kaputt)
  2  falscher Aufruf
EOT
}

# Modellnamen der 4-Feld-Zeit: alle Namen aus GluonModel/GluonModelAlias
# (bis v2016.2.x) bzw. device/alias/manifest_alias/factory_image/
# sysupgrade_image (v2017.1.x) in targets/ aller Gluon-Tags v2014.1 bis
# v2017.1.8. Nur diese Namen melden Knoten, deren Autoupdater 4-Feld-Zeilen
# liest. Ermittelt am 05.10.2026 aus freifunk-gluon/gluon; aendert sich nicht
# mehr. Je Eintrag: Name, erster Tag, Target(s).
declare -ra ALT_MODELLE=(
	"8devices-carambola2-board v2016.1.4 ar71xx-generic"
	"a5-v11 v2017.1.1 ramips-rt305x"
	"alfa-ap121 v2016.1.3 ar71xx-generic"
	"alfa-ap121u v2016.1.3 ar71xx-generic"
	"alfa-hornet-ub v2016.1.3 ar71xx-generic"
	"alfa-network-ap121 v2016.2 ar71xx-generic"
	"alfa-network-ap121u v2016.2 ar71xx-generic"
	"alfa-network-hornet-ub v2016.2 ar71xx-generic"
	"alfa-network-n2-n5 v2016.2 ar71xx-generic"
	"alfa-network-tube2h v2016.2 ar71xx-generic"
	"allnet-all0315n v2015.1 ar71xx-generic"
	"buffalo-whr-hp-g300n v2016.1 ar71xx-generic"
	"buffalo-wzr-600dhp v2016.1 ar71xx-generic"
	"buffalo-wzr-hp-ag300h v2016.1 ar71xx-generic"
	"buffalo-wzr-hp-ag300h-wzr-600dhp v2014.4 ar71xx-generic"
	"buffalo-wzr-hp-g300nh v2016.1 ar71xx-generic"
	"buffalo-wzr-hp-g300nh2 v2016.2 ar71xx-generic"
	"buffalo-wzr-hp-g450h v2014.4 ar71xx-generic"
	"d-link-dir-505-rev-a1 v2016.1 ar71xx-generic"
	"d-link-dir-505-rev-a2 v2016.2 ar71xx-generic"
	"d-link-dir-615-rev-c1 v2015.1 ar71xx-generic,ar71xx-tiny"
	"d-link-dir-615-rev-e1 v2014.2 ar71xx-generic"
	"d-link-dir-825-rev-b1 v2014.2 ar71xx-generic"
	"d-link-dir-860l-b1 v2016.2 ramips-mt7621"
	"gl-ar150 v2016.2 ar71xx-generic"
	"gl-ar300m v2017.1.4 ar71xx-generic"
	"gl-ar750 v2017.1.8 ar71xx-generic"
	"gl-inet-6408a-v1 v2015.1 ar71xx-generic"
	"gl-inet-6416a-v1 v2015.1 ar71xx-generic"
	"lamobo-r1 v2017.1 sunxi"
	"lemaker-banana-pi v2016.1 sunxi"
	"lemaker-banana-pro v2016.2 sunxi"
	"lemaker-lamobo-r1 v2016.2 sunxi"
	"linksys-wrt1200ac v2017.1 mvebu"
	"linksys-wrt160nl v2014.3 ar71xx-generic"
	"meraki-mr12 v2016.1.4 ar71xx-generic"
	"meraki-mr16 v2016.1.4 ar71xx-generic"
	"meraki-mr62 v2016.1.4 ar71xx-generic"
	"meraki-mr66 v2016.1.4 ar71xx-generic"
	"mikrotik v2016.2 ar71xx-mikrotik"
	"mikrotik-nand-64m v2017.1 ar71xx-mikrotik"
	"mikrotik-nand-large v2017.1 ar71xx-mikrotik"
	"netgear-wndr3700 v2015.1 ar71xx-generic"
	"netgear-wndr3700v2 v2015.1 ar71xx-generic"
	"netgear-wndr3700v4 v2015.1 ar71xx-nand"
	"netgear-wndr3800 v2015.1 ar71xx-generic"
	"netgear-wndr4300 v2015.1 ar71xx-nand"
	"netgear-wndrmac v2015.1 ar71xx-generic"
	"netgear-wndrmacv2 v2015.1 ar71xx-generic"
	"netgear-wnr2200 v2016.2 ar71xx-generic"
	"onion-omega v2016.1.1 ar71xx-generic"
	"openmesh-mr1750 v2016.2 ar71xx-generic"
	"openmesh-mr1750v2 v2016.2 ar71xx-generic"
	"openmesh-mr600 v2016.1.5 ar71xx-generic"
	"openmesh-mr600v2 v2016.1.5 ar71xx-generic"
	"openmesh-mr900 v2016.1.5 ar71xx-generic"
	"openmesh-mr900v2 v2016.1.5 ar71xx-generic"
	"openmesh-om2p v2016.1.5 ar71xx-generic"
	"openmesh-om2p-hs v2016.1.5 ar71xx-generic"
	"openmesh-om2p-hsv2 v2016.1.5 ar71xx-generic"
	"openmesh-om2p-hsv3 v2016.2 ar71xx-generic"
	"openmesh-om2p-lc v2016.1.5 ar71xx-generic"
	"openmesh-om2pv2 v2016.1.5 ar71xx-generic"
	"openmesh-om5p v2016.1.5 ar71xx-generic"
	"openmesh-om5p-ac v2016.2 ar71xx-generic"
	"openmesh-om5p-acv2 v2016.2 ar71xx-generic"
	"openmesh-om5p-an v2016.1.5 ar71xx-generic"
	"raspberry-pi v2016.1 brcm2708-bcm2708"
	"raspberry-pi-2 v2016.1 brcm2708-bcm2709"
	"tp-link-archer-c25-v1 v2017.1.4 ar71xx-generic"
	"tp-link-archer-c2600 v2017.1 ipq806x"
	"tp-link-archer-c5-v1 v2015.1 ar71xx-generic"
	"tp-link-archer-c7-v2 v2014.4 ar71xx-generic"
	"tp-link-archer-c7-v4 v2017.1.8 ar71xx-generic"
	"tp-link-cpe210-v1.0 v2014.4 ar71xx-generic"
	"tp-link-cpe210-v1.1 v2016.1 ar71xx-generic"
	"tp-link-cpe220-v1.0 v2014.4 ar71xx-generic"
	"tp-link-cpe220-v1.1 v2016.1 ar71xx-generic"
	"tp-link-cpe510-v1.0 v2014.4 ar71xx-generic"
	"tp-link-cpe510-v1.1 v2016.1 ar71xx-generic"
	"tp-link-cpe520-v1.0 v2014.4 ar71xx-generic"
	"tp-link-cpe520-v1.1 v2016.1 ar71xx-generic"
	"tp-link-re450 v2017.1 ar71xx-generic"
	"tp-link-tl-mr13u-v1 v2016.1.1 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-mr3020-v1 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-mr3040-v1 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-mr3040-v2 v2014.4 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-mr3220-v1 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-mr3220-v2 v2015.1 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-mr3420-v1 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-mr3420-v2 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wa701n-nd-v1 v2015.1 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wa701n-nd-v2 v2015.1 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wa7210n-v2 v2017.1 ar71xx-tiny"
	"tp-link-tl-wa730re-v1 v2017.1 ar71xx-tiny"
	"tp-link-tl-wa750re-v1 v2014.4 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wa7510n-v1 v2016.1.3 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wa801n-nd-v1 v2015.1.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wa801n-nd-v2 v2014.4 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wa801n-nd-v3 v2016.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wa830re-v1 v2015.1.1 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wa830re-v2 v2015.1 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wa850re-v1 v2014.4 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wa860re-v1 v2015.1 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wa901n-nd-v1 v2016.1 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wa901n-nd-v2 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wa901n-nd-v3 v2015.1 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wa901n-nd-v4 v2016.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wdr3500-v1 v2014.2 ar71xx-generic"
	"tp-link-tl-wdr3600-v1 v2014.2 ar71xx-generic"
	"tp-link-tl-wdr4300-v1 v2014.2 ar71xx-generic"
	"tp-link-tl-wdr4900-v1 v2014.4 mpc85xx-generic"
	"tp-link-tl-wr1043n-nd-v1 v2014.2 ar71xx-generic"
	"tp-link-tl-wr1043n-nd-v2 v2014.4 ar71xx-generic"
	"tp-link-tl-wr1043n-nd-v3 v2016.1 ar71xx-generic"
	"tp-link-tl-wr1043n-nd-v4 v2016.2.3 ar71xx-generic"
	"tp-link-tl-wr1043n-v5 v2017.1.5 ar71xx-generic"
	"tp-link-tl-wr2543n-nd-v1 v2015.1 ar71xx-generic"
	"tp-link-tl-wr703n-v1 v2014.4 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr710n-v1 v2014.4 ar71xx-generic"
	"tp-link-tl-wr710n-v2 v2016.1 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr710n-v2.1 v2016.2 ar71xx-generic"
	"tp-link-tl-wr740n-nd-v1 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr740n-nd-v3 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr740n-nd-v4 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr740n-nd-v5 v2015.1.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr741n-nd-v1 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr741n-nd-v2 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr741n-nd-v4 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr741n-nd-v5 v2015.1.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr743n-nd-v1 v2015.1 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr743n-nd-v2 v2015.1 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr841n-nd-v10 v2016.1 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr841n-nd-v11 v2016.1.5 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr841n-nd-v12 v2016.2.6 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr841n-nd-v3 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr841n-nd-v5 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr841n-nd-v7 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr841n-nd-v8 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr841n-nd-v9 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr842n-nd-v1 v2014.2 ar71xx-generic"
	"tp-link-tl-wr842n-nd-v2 v2014.2 ar71xx-generic"
	"tp-link-tl-wr842n-nd-v3 v2016.2 ar71xx-generic"
	"tp-link-tl-wr843n-nd-v1 v2016.1 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr940n-nd-v1 v2016.1 ar71xx-generic"
	"tp-link-tl-wr940n-nd-v2 v2016.1 ar71xx-generic"
	"tp-link-tl-wr940n-nd-v3 v2016.1 ar71xx-generic"
	"tp-link-tl-wr940n-v1 v2017.1 ar71xx-tiny"
	"tp-link-tl-wr940n-v2 v2017.1 ar71xx-tiny"
	"tp-link-tl-wr940n-v3 v2017.1 ar71xx-tiny"
	"tp-link-tl-wr940n-v4 v2016.2.3 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr940n-v5 v2017.1.8 ar71xx-tiny"
	"tp-link-tl-wr940n-v6 v2017.1.8 ar71xx-tiny"
	"tp-link-tl-wr941n-nd-v2 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr941n-nd-v3 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr941n-nd-v4 v2014.2 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr941n-nd-v5 v2015.1 ar71xx-generic,ar71xx-tiny"
	"tp-link-tl-wr941n-nd-v6 v2015.1 ar71xx-generic,ar71xx-tiny"
	"tp-link-wbs210-v1.20 v2017.1 ar71xx-generic"
	"tp-link-wbs510-v1.20 v2017.1 ar71xx-generic"
	"ubiquiti-airgateway v2016.1 ar71xx-generic"
	"ubiquiti-airgateway-lr v2017.1 ar71xx-generic"
	"ubiquiti-airgateway-pro v2017.1 ar71xx-generic"
	"ubiquiti-airrouter v2016.1 ar71xx-generic"
	"ubiquiti-bullet-m v2014.2 ar71xx-generic"
	"ubiquiti-bullet-m2 v2016.2 ar71xx-generic"
	"ubiquiti-bullet-m5 v2016.2 ar71xx-generic"
	"ubiquiti-loco-m v2015.1.2 ar71xx-generic"
	"ubiquiti-loco-m-xw v2014.4 ar71xx-generic"
	"ubiquiti-ls-sr71 v2015.1 ar71xx-generic"
	"ubiquiti-nanostation-loco-m2 v2016.2 ar71xx-generic"
	"ubiquiti-nanostation-loco-m2-xw v2017.1 ar71xx-generic"
	"ubiquiti-nanostation-loco-m5 v2016.2 ar71xx-generic"
	"ubiquiti-nanostation-loco-m5-xw v2017.1 ar71xx-generic"
	"ubiquiti-nanostation-m v2014.2 ar71xx-generic"
	"ubiquiti-nanostation-m-xw v2014.4 ar71xx-generic"
	"ubiquiti-nanostation-m2 v2016.2 ar71xx-generic"
	"ubiquiti-nanostation-m2-xw v2017.1 ar71xx-generic"
	"ubiquiti-nanostation-m5 v2016.2 ar71xx-generic"
	"ubiquiti-nanostation-m5-xw v2017.1 ar71xx-generic"
	"ubiquiti-picostation-m v2015.1.2 ar71xx-generic"
	"ubiquiti-picostation-m2 v2016.2 ar71xx-generic"
	"ubiquiti-rocket-m v2015.1.2 ar71xx-generic"
	"ubiquiti-rocket-m-ti v2017.1 ar71xx-generic"
	"ubiquiti-rocket-m-xw v2016.1.5 ar71xx-generic"
	"ubiquiti-rocket-m2 v2016.2 ar71xx-generic"
	"ubiquiti-rocket-m2-ti v2017.1 ar71xx-generic"
	"ubiquiti-rocket-m2-xw v2017.1 ar71xx-generic"
	"ubiquiti-rocket-m5 v2016.2 ar71xx-generic"
	"ubiquiti-rocket-m5-ti v2017.1 ar71xx-generic"
	"ubiquiti-rocket-m5-xw v2017.1 ar71xx-generic"
	"ubiquiti-unifi v2014.2 ar71xx-generic"
	"ubiquiti-unifi-ac-lite v2016.2 ar71xx-generic"
	"ubiquiti-unifi-ac-mesh v2017.1.8 ar71xx-generic"
	"ubiquiti-unifi-ac-pro v2016.2 ar71xx-generic"
	"ubiquiti-unifi-ap v2017.1 ar71xx-generic"
	"ubiquiti-unifi-ap-lr v2017.1 ar71xx-generic"
	"ubiquiti-unifi-ap-pro v2014.4 ar71xx-generic"
	"ubiquiti-unifiap-outdoor v2014.2 ar71xx-generic"
	"ubiquiti-unifiap-outdoor+ v2015.1 ar71xx-generic"
	"ubnt-erx v2017.1 ramips-mt7621"
	"ubnt-erx-sfp v2017.1.5 ramips-mt7621"
	"vocore v2015.1 ramips-rt305x"
	"vocore-16 v2017.1 ramips-rt305x"
	"vocore-8 v2017.1 ramips-rt305x"
	"vocore2 v2017.1 ramips-mt7628"
	"wd-my-net-n600 v2016.1 ar71xx-generic"
	"wd-my-net-n750 v2016.1 ar71xx-generic"
	"x86-64 v2016.1 x86-64"
	"x86-64-virtualbox v2016.1 x86-64"
	"x86-64-vmware v2016.1 x86-64"
	"x86-generic v2015.1 x86-generic"
	"x86-geode v2017.1 x86-geode"
	"x86-kvm v2015.1 x86-generic,x86-kvm_guest"
	"x86-virtualbox v2015.1 x86-generic"
	"x86-vmware v2015.1 x86-generic"
	"x86-xen v2016.1 x86-xen_domu"
	"x86-xen_domu v2017.1.1 x86-generic"
	"zbt-wg3526 v2017.1.5 ramips-mt7621"
)

# Diese Namen bekommen nie 4-Feld-Zeilen: Das sysupgrade von OpenWrt 15.05
# (Gluon 2016.2) lehnt ath79-Images dieser Geraete ab (support-list an anderem
# Offset). Der Autoupdater hat das Netz dann schon gestoppt, der Knoten bleibt
# bis zum Stromreset offline.
declare -ra OHNE_4FELD=(
	"tp-link-cpe210-v1.0"
	"tp-link-cpe210-v1.1"
	"tp-link-cpe220-v1.0"
	"tp-link-cpe220-v1.1"
	"tp-link-cpe510-v1.0"
	"tp-link-cpe510-v1.1"
	"tp-link-cpe520-v1.0"
	"tp-link-cpe520-v1.1"
)

# Alte -> heutige Modellnamen ("alt neu"), Stand 05.10.2026, gleich wie in
# manifest-altformat.sh: manifest_aliases aus Gluon v2023.2.6 (in v2025.1 entfernt),
# Namen nur aus v2022.1/v2023.1 und die Namen der 4-Feld-Zeit, wie Gluon sie
# damals selbst zugeordnet hat. Abgeschlossen; Ergaenzungen per -a.
declare -ra ALIAS_ALT=(
	# Alte Gluon-Modellnamen -> heutige, aus den manifest_aliases von Gluon v2023.2.6
	# (targets/*, "upgrade from OpenWrt 19.07"; in v2025.1 entfernt, Gluon 4e2bf620).
	# Am Ende ergaenzt: Namen, die nur v2022.1/v2023.1 kannten.
	# Die alten Namen sind die der ar71xx-/ramips-Zeit, so wie sie auch Gluon
	# 2016.2 bis 2020.2 meldet (z. B. tp-link-tl-wr1043n-nd-v4). Format: alt neu
	"asus-rt-ac57u asus-rt-ac57u-v1"
	"buffalo-wzr-hp-g300nh buffalo-wzr-hp-g300nh-rtl8366s"
	"cudy-wr1300 cudy-wr1300-v1"
	"d-link-dir-505-rev-a1 d-link-dir-505"
	"d-link-dir-505-rev-a2 d-link-dir-505"
	"d-link-dir-825-rev-b1 d-link-dir825b1"
	"gl-inet-6416a-v1 gl.inet-6416"
	"gl.inet-gl-ar300m gl.inet-gl-ar300m-nor"
	"netgear-ex3700-ex3800 netgear-ex3700"
	"netgear-wndr3700v2 netgear-wndr3700-v2"
	"netgear-wndr3700v5 netgear-wndr3700-v5"
	"netgear-wndr3800chmychart netgear-wndr3800ch"
	"netgear-wnr2200 netgear-wnr2200-8m"
	"openmesh-mr1750 openmesh-mr1750-v1"
	"openmesh-mr1750v2 openmesh-mr1750-v2"
	"openmesh-mr600 openmesh-mr600-v1"
	"openmesh-mr600v2 openmesh-mr600-v2"
	"openmesh-mr900 openmesh-mr900-v1"
	"openmesh-mr900v2 openmesh-mr900-v2"
	"openmesh-om2p openmesh-om2p-v1"
	"openmesh-om2p-hs openmesh-om2p-hs-v1"
	"openmesh-om2p-hsv2 openmesh-om2p-hs-v2"
	"openmesh-om2p-hsv3 openmesh-om2p-hs-v3"
	"openmesh-om2p-hsv4 openmesh-om2p-hs-v4"
	"openmesh-om2pv2 openmesh-om2p-v2"
	"openmesh-om2pv4 openmesh-om2p-v4"
	"openmesh-om5p-ac openmesh-om5p-ac-v1"
	"openmesh-om5p-acv2 openmesh-om5p-ac-v2"
	"raspberry-pi-2-model-b-rev-1.1 raspberrypi-2-model-b"
	"raspberry-pi-3-model-b-plus-rev-1.3 raspberrypi-3-model-b"
	"raspberry-pi-3-model-b-rev-1.2 raspberrypi-3-model-b"
	"raspberry-pi-4-model-b-rev-1.1 raspberrypi-4-model-b"
	"raspberry-pi-4-model-b-rev-1.2 raspberrypi-4-model-b"
	"raspberry-pi-4-model-b-rev-1.4 raspberrypi-4-model-b"
	"raspberry-pi-4-model-b-rev-1.5 raspberrypi-4-model-b"
	"raspberry-pi-model-b-plus-rev-1.2 raspberrypi-model-b"
	"raspberry-pi-model-b-rev-1 raspberrypi-model-b"
	"raspberry-pi-model-b-rev-2 raspberrypi-model-b"
	"raspberrypi-3-model-b-plus raspberrypi-3-model-b"
	"raspberrypi-model-b-plus raspberrypi-model-b"
	"raspberrypi-model-b-rev2 raspberrypi-model-b"
	"tp-link-archer-c50 tp-link-archer-c50-v1"
	"tp-link-archer-c6-v2 tp-link-archer-c6-v2-eu-ru-jp"
	"tp-link-cpe210-v1.0 tp-link-cpe210-v1"
	"tp-link-cpe210-v1.1 tp-link-cpe210-v1"
	"tp-link-cpe210-v2.0 tp-link-cpe210-v2"
	"tp-link-cpe210-v3.0 tp-link-cpe210-v3"
	"tp-link-cpe210-v3.1 tp-link-cpe210-v3"
	"tp-link-cpe210-v3.20 tp-link-cpe210-v3"
	"tp-link-cpe510-v1.0 tp-link-cpe510-v1"
	"tp-link-cpe510-v1.1 tp-link-cpe510-v1"
	"tp-link-tl-wr1043n-nd-v2 tp-link-tl-wr1043nd-v2"
	"tp-link-tl-wr1043n-nd-v3 tp-link-tl-wr1043nd-v3"
	"tp-link-tl-wr1043n-nd-v4 tp-link-tl-wr1043nd-v4"
	"tp-link-tl-wr2543n-nd-v1 tp-link-tl-wr2543n-nd"
	"tp-link-tl-wr842n-nd-v3 tp-link-tl-wr842n-v3"
	"tp-link-wbs210-v1.20 tp-link-wbs210-v1"
	"tp-link-wbs510-v1.20 tp-link-wbs510-v1"
	"ubiquiti-unifi ubiquiti-unifi-ap"
	"ubiquiti-unifi-6-lr ubiquiti-unifi-6-lr-v1"
	"ubiquiti-unifiap-outdoor+ ubiquiti-unifi-ap-outdoor+"
	"ubnt-erx ubiquiti-edgerouter-x"
	"ubnt-erx-sfp ubiquiti-edgerouter-x-sfp"
	"x86-kvm x86-generic"
	"x86-xen_domu x86-generic"
	"zbt-wg3526 zbtlink-zbt-wg3526-16m"
	"zbt-wg3526-16m zbtlink-zbt-wg3526-16m"
	"zbt-wg3526-32m zbtlink-zbt-wg3526-32m"
	# Ergaenzt 04.10.2026: nur in v2022.1.4 und v2023.1.2, in v2023.2 schon entfernt
	"tp-link-re355 tp-link-re355-v1"
	"tp-link-re450 tp-link-re450-v1"
	# Bewusst NICHT (05.10.2026):
	# - netgear-wndr3700v4 -> netgear-wndr3700-v4: Upgrade-Pfad nie gegangen
	#   (Kernelpartition gewachsen), Gluon e1437781 / OpenWrt 0d28e5d6.
	# Ergaenzt 05.10.2026: Gluon hat keinen Alias, OpenWrt ath79 fuehrt den
	# ar71xx-Namen aber in SUPPORTED_DEVICES (sysupgrade nimmt das Image an):
	"d-link-dap-1330-rev-a1 d-link-dap-1330-a1"
	"netgear-wndrmacv2 netgear-wndrmac-v2"
	# Ubiquiti NanoStation XW (ar71xx -> ath79), ergaenzt 05.10.2026 (adorfer): Gluon hat
	# die Aliase mit dem AirMax-Ausbau (a0f5b4e9, Gefahr eines schreibgeschuetzten
	# Flash, betrifft die Erstinstallation aus AirOS) entfernt und beim Wiedereinbau
	# (37bbab91) nicht zurueckgeholt. Der Sprung Sackgasse -> 2023.1.5 ging aber per
	# handgemachtem Manifest an einer Station in RDV ohne Eingriff durch.
	# ubiquiti-nanostation-m-xw heisst in beiden gleich und braucht keinen Alias.
	# Rocket M XW nicht: ath79 baut dafuer kein Gluon-Image.
	"ubiquiti-loco-m-xw ubiquiti-nanostation-loco-m-xw"
	"ubiquiti-nanostation-loco-m2-xw ubiquiti-nanostation-loco-m-xw"
	"ubiquiti-nanostation-loco-m5-xw ubiquiti-nanostation-loco-m-xw"
	"ubiquiti-nanostation-m2-xw ubiquiti-nanostation-m-xw"
	"ubiquiti-nanostation-m5-xw ubiquiti-nanostation-m-xw"
	# Achtung fuer Manifeste, die Gluon-2016.2-Knoten lesen: tp-link-cpe210-v1.x und
	# tp-link-cpe510-v1.x NICHT aufnehmen. Das sysupgrade von OpenWrt 15.05 lehnt das
	# ath79-Image ab (support-list fehlt), nachdem der Autoupdater das Netz schon
	# gestoppt hat; der Knoten bleibt bis zum Stromreset offline.
	# Ergaenzt 05.10.2026: Namen der 4-Feld-Zeit (Gluon 2015.1-2017.1), die weder
	# 2023.2 noch die Sackgasse fuehren, abgebildet wie damals in Gluon selbst
	# (fuer manifeste-zusammenfuehren.sh / manifest-altformat.sh -a).
	# WR940N v1-v3 liefen bis 2016.2 als GluonModelAlias der WR941N/ND v4-v6:
	"tp-link-tl-wr940n-nd-v1 tp-link-tl-wr941n-nd-v4"
	"tp-link-tl-wr940n-nd-v2 tp-link-tl-wr941n-nd-v5"
	"tp-link-tl-wr940n-nd-v3 tp-link-tl-wr941n-nd-v6"
	# Gluon 2015.1: Loco M und PicoStation M (XM) bekamen das ubnt-bullet-m-Image:
	"ubiquiti-loco-m ubiquiti-bullet-m"
	"ubiquiti-picostation-m ubiquiti-bullet-m"
	# x86-Varianten: dasselbe combined-Image wie generic bzw. 64 (VDI/VMDK nur
	# als Factory-Format verschieden):
	"x86-virtualbox x86-generic"
	"x86-vmware x86-generic"
	"x86-64-virtualbox x86-64"
	"x86-64-vmware x86-64"
	# x86-xen (Ziel x86-xen_domu, bis Gluon 2016.2) hat KEINEN Weg: x86-xen_domu steht in
	# keinem heutigen Manifest, der Knoten meldet "No matching firmware found". Ein Alias
	# auf x86-generic waere ungetestet und bricht vermutlich (domU paravirtualisiert, heute
	# GRUB). Solche Knoten von Hand umstellen.
	"x86-xen x86-xen_domu"
)

falsch() { echo "$1" >&2; echo "Hilfe: $0 --help" >&2; exit 2; }

for arg in "$@"; do
	case "$arg" in --help|-h) hilfe; exit 0 ;; esac
done

BASIS=""; ZUSATZ=""; AUS=""; BRANCH="stable"; MB=""; MZ=""; GLUON=""; PROBE=0
ALIASE=""; X86="alt"
while getopts "b:z:o:B:m:M:a:g:x:n" opt; do
	case "$opt" in
		b) BASIS="$OPTARG" ;;
		z) ZUSATZ="$OPTARG" ;;
		o) AUS="$OPTARG" ;;
		B) BRANCH="$OPTARG" ;;
		m) MB="$OPTARG" ;;
		M) MZ="$OPTARG" ;;
		a) ALIASE="$OPTARG" ;;
		g) GLUON="$OPTARG" ;;
		x) X86="$OPTARG" ;;
		n) PROBE=1 ;;
		*) falsch "Unbekannte Option." ;;
	esac
done
shift $((OPTIND - 1))
[ $# -eq 0 ] || falsch "Unerwartete Argumente: $*"
[ -n "$BASIS" ] && [ -n "$ZUSATZ" ] && [ -n "$AUS" ] || falsch "-b, -z und -o sind Pflicht."
[ -d "$BASIS" ] || falsch "$BASIS ist kein Verzeichnis."
[ -d "$ZUSATZ" ] || falsch "$ZUSATZ ist kein Verzeichnis."
[ -e "$AUS" ] && falsch "$AUS existiert schon; bitte einen neuen Namen nehmen."
[ -n "$MB" ] || MB="$BRANCH.manifest"
case "$X86" in alt|alle|aus) ;; *) falsch "-x kennt nur alt, alle oder aus." ;; esac
[ -z "$ALIASE" ] || [ -r "$ALIASE" ] || falsch "$ALIASE nicht lesbar."
[ -z "$GLUON" ] || [ -d "$GLUON/targets" ] || falsch "$GLUON hat kein targets/."
realpath -s --relative-to=/ / >/dev/null 2>&1 || falsch "GNU realpath fehlt."
BASIS="$(realpath -s "$BASIS")"; ZUSATZ="$(realpath -s "$ZUSATZ")"
AUS="$(realpath -sm "$AUS")"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
printf '%s\n' "${ALT_MODELLE[@]}" | awk '{ print $1 }' | sort -u > "$TMP/alt"
printf '%s\n' "${OHNE_4FELD[@]}" | sort -u > "$TMP/ohne4"
: > "$TMP/alias"
{ printf '%s\n' "${ALIAS_ALT[@]}"; [ -n "$ALIASE" ] && cat "$ALIASE"; } \
	| sed 's/#.*//' | awk 'NF >= 2 { print $1, $2 }' > "$TMP/alias"
: > "$TMP/unbedient"; : > "$TMP/bedient"
FEHLER=0
SUMME_B=0; SUMME_Z=0; SUMME_DOM=0

# verlinken <quelle> <zielordner>: relativer Symlink im Zielordner
verlinken() {
	local q="$1" zo="$2"
	[ "$PROBE" = 1 ] && return 0
	mkdir -p "$zo" || exit 1
	ln -s "$(realpath -s --relative-to="$zo" "$q")" "$zo/$(basename "$q")" || exit 1
}

# kopf_wert <manifest> <schluessel>
kopf_wert() { sed '/^---$/,$d' "$1" | sed -n "s/^$2=//p" | head -n 1; }

# Modell zu einem Dateinamen: laengster Modellname aus <liste>, der hinter
# "-<version>-" steht und von "." oder "-" oder Ende gefolgt wird
modell_zu_datei() {
	awk -v f="$1" -v v="$2" '
		{ m[NR] = $1 }
		END {
			i = index(f, "-" v "-"); if (!i) exit
			rest = substr(f, i + length(v) + 2); best = ""
			for (k in m) {
				n = m[k]; l = length(n)
				if (substr(rest, 1, l) == n) {
					c = substr(rest, l + 1, 1)
					if ((c == "" || c == "." || c == "-") && l > length(best)) best = n
				}
			}
			if (best != "") print best
		}' "$3"
}

# Domain-Ordner: Vereinigung aus Basis und Zusatz
{ ( cd "$BASIS" && find . -mindepth 1 -maxdepth 1 -type d -printf '%f\n' )
  ( cd "$ZUSATZ" && find . -mindepth 1 -maxdepth 1 -type d -printf '%f\n' ); } | sort -u > "$TMP/domains"

# Dateien direkt in der Basis-Wurzel (README u. a.) mitnehmen
while IFS= read -r f; do
	verlinken "$BASIS/$f" "$AUS"
done < <(cd "$BASIS" && find . -mindepth 1 -maxdepth 1 ! -type d -printf '%f\n' | sort)

while IFS= read -r dom; do
	B="$BASIS/$dom"; Z="$ZUSATZ/$dom"; O="$AUS/$dom"
	SUMME_DOM=$((SUMME_DOM + 1))
	MBF="$B/sysupgrade/$MB"
	if [ -n "$MZ" ]; then
		MZF="$Z/sysupgrade/$MZ"
	else
		# einziges *.manifest im Zusatz, sonst <branch>.manifest
		MZF="$(find "$Z/sysupgrade" -maxdepth 1 -name '*.manifest' 2>/dev/null)"
		[ "$(printf '%s' "$MZF" | grep -c .)" = 1 ] || MZF="$Z/sysupgrade/$BRANCH.manifest"
	fi

	# Modelle der Basis (5- und 4-Feld-Zeilen)
	: > "$TMP/b.modelle"
	if [ -f "$MBF" ]; then
		sed '/^---$/,$d' "$MBF" | awk 'NF == 4 || NF == 5 { print $1 }' | sort -u > "$TMP/b.modelle"
	elif [ -d "$B" ]; then
		echo "$dom: Basis ohne $MB, nur der Zusatz zaehlt." >&2
	fi

	# Zusatz-Zeilen fuer fehlende Modelle
	: > "$TMP/z.zeilen"; : > "$TMP/z.modelle.alle"
	if [ -f "$MZF" ]; then
		sed '/^---$/,$d' "$MZF" | awk 'NF == 5' > "$TMP/z.alle"
		awk '{ print $1 }' "$TMP/z.alle" | sort -u > "$TMP/z.modelle.alle"
		# Zusatz-Modell nur, wenn die Basis es weder unter diesem Namen noch
		# ueber einen Alias (alt -> neu, neu in der Basis) fuehrt; im zweiten
		# Fall kommt spaeter die Alias-Zeile auf das Basis-Image.
		# (nicht NR == FNR: bei leerer Basis-Liste waere das auch fuer z.alle wahr)
		awk -v bf="$TMP/b.modelle" -v af="$TMP/alias" '
			BEGIN { while ((getline z < bf) > 0) b[z] = 1
			        while ((getline z < af) > 0) { split(z, a, " "); neu[a[1]] = a[2] } }
			!($1 in b) && !(($1 in neu) && (neu[$1] in b))' \
			"$TMP/z.alle" > "$TMP/z.zeilen"
	fi
	awk '{ print $1 }' "$TMP/z.zeilen" | sort -u > "$TMP/z.modelle"
	nb="$(wc -l < "$TMP/b.modelle" | tr -d ' ')"; nz="$(wc -l < "$TMP/z.modelle" | tr -d ' ')"
	SUMME_B=$((SUMME_B + nb)); SUMME_Z=$((SUMME_Z + nz))
	echo "$dom: Basis $nb Modelle, aus dem Zusatz $nz dazu" >&2

	# Alle Zeilen mit Herkunft: "B|Z modell version sha256 groesse datei"
	{ [ -f "$MBF" ] && sed '/^---$/,$d' "$MBF" | awk 'NF == 5 { print "B", $0 }'
	  awk '{ print "Z", $0 }' "$TMP/z.zeilen"; } > "$TMP/zeilen"
	# alte Namen per Alias-Datei, die weder Basis noch Zusatz fuehren
	awk -v af="$TMP/alias" -v altf="$TMP/alt" -v ohne="$TMP/ohne4" '
		BEGIN { while ((getline z < altf) > 0) alt[z] = 1
		        while ((getline z < ohne) > 0) aus[z] = 1 }
		{ hat[$2] = 1; zeile[$2] = $0 }
		END {
			while ((getline z < af) > 0) {
				split(z, a, " ")
				# jeder bekannte alte Name; 4-Feld-Zeilen bekommt er unten nur,
				# wenn er aus der 4-Feld-Zeit stammt
				if (!(a[1] in aus) && !(a[1] in hat) && (a[2] in zeile) && !(a[1] in schon)) {
					split(zeile[a[2]], f, " ")
					print f[1], a[1], f[3], f[4], f[5], f[6]; schon[a[1]] = 1
				}
			}
		}' "$TMP/zeilen" > "$TMP/aliaszeilen"
	cat "$TMP/aliaszeilen" >> "$TMP/zeilen"
	na="$(wc -l < "$TMP/aliaszeilen" | tr -d ' ')"
	# Dateien, die 4-Feld-Zeilen brauchen
	awk -v altf="$TMP/alt" -v ohne="$TMP/ohne4" '
		BEGIN { while ((getline z < altf) > 0) alt[z] = 1
		        while ((getline z < ohne) > 0) aus[z] = 1 }
		($2 in alt) && !($2 in aus) { print $1, $4, $6 }' "$TMP/zeilen" | sort -u -k3,3 > "$TMP/vier"
	n4="$(awk '{ print $2 }' "$TMP/zeilen" | sort -u | awk -v altf="$TMP/alt" -v ohne="$TMP/ohne4" '
		BEGIN { while ((getline z < altf) > 0) alt[z] = 1; while ((getline z < ohne) > 0) aus[z] = 1 }
		($1 in alt) && !($1 in aus)' | wc -l | tr -d ' ')"
	echo "  davon $n4 Namen mit 4-Feld-Zeilen, $na alte Namen per Alias" >&2
	awk -v d="$dom" '{ print d, $2 }' "$TMP/zeilen" >> "$TMP/bedient"
	# alte Namen, fuer die es in dieser Domain kein Image gibt
	awk '{ print $2 }' "$TMP/zeilen" | sort -u | comm -23 "$TMP/alt" - | comm -23 - "$TMP/ohne4" >> "$TMP/unbedient"

	# sha256 pruefen und sha512 berechnen (je Datei einmal, "vier" ist eindeutig)
	: > "$TMP/sha512"
	while read -r q h256 f; do
		if [ "$q" = B ]; then d="$B/sysupgrade/$f"; else d="$Z/sysupgrade/$f"; fi
		if [ ! -f "$d" ]; then
			echo "  fehlt: $d" >&2; FEHLER=1; continue
		fi
		ist="$(sha256sum "$d" | cut -d' ' -f1)"
		if [ "$ist" != "$h256" ]; then
			echo "  sha256 passt nicht: $f (Datei $ist, Manifest $h256)" >&2; FEHLER=1; continue
		fi
		echo "$f $(sha512sum "$d" | cut -d' ' -f1)" >> "$TMP/sha512"
	done < "$TMP/vier"

	# x86-Altknoten: Abbildung EFI-Image -> MBR-Image, siehe X86-ALTKNOTEN.
	# Je Zeile: <datei> <4feld-datei> <sha256> <sha512> <5feld-datei> <sha256> <groesse>
	: > "$TMP/mbr"
	if [ "$X86" != aus ]; then
		leg="$( [ -d "$B/other" ] && cd "$B/other" && find . -maxdepth 1 -name '*-x86-legacy-mbr-sysupgrade.img.gz' -printf '%f\n' | head -n 1)"
		while IFS= read -r f; do
			m="${f%-sysupgrade.img.gz}-mbr-sysupgrade.img.gz"
			if [ ! -f "$B/other/$m" ]; then
				echo "  x86: other/$m fehlt; x86-Knoten bis 2021.1 verlieren mit $f die Konfiguration (-x aus, wenn gewollt)" >&2
				FEHLER=1; continue
			fi
			m4="$m"
			case "$f" in
				*-x86-generic-sysupgrade.img.gz)
					if [ -n "$leg" ]; then m4="$leg"
					else echo "  x86: kein x86-legacy-MBR-Image; Knoten bis 2016.2 ohne SSE2 bekaemen x86-generic (pentium4)" >&2; fi ;;
			esac
			echo "$f $m4 $(sha256sum "$B/other/$m4" | cut -d' ' -f1) $(sha512sum "$B/other/$m4" | cut -d' ' -f1)" \
				"$m $(sha256sum "$B/other/$m" | cut -d' ' -f1) $(stat -c %s "$B/other/$m")" >> "$TMP/mbr"
			for x in "$m4" "$m"; do
				[ "$PROBE" = 1 ] || [ -e "$O/sysupgrade/$x" ] || verlinken "$B/other/$x" "$O/sysupgrade"
			done
		done < <(awk '$1 == "B" { print $6 }' "$TMP/zeilen" | sort -u | grep -E -- '-x86-(generic|legacy|64)-sysupgrade\.img\.gz$')
		[ -s "$TMP/mbr" ] && echo "  x86: $(wc -l < "$TMP/mbr" | tr -d ' ') Image(s) auf MBR umgelenkt ($( [ "$X86" = alle ] && echo '4- und 5-Feld-Zeilen' || echo 'nur 4-Feld-Zeilen'))" >&2
	fi

	# Unterordner: Vereinigung
	{ [ -d "$B" ] && ( cd "$B" && find . -mindepth 1 -maxdepth 1 -printf '%f\n' )
	  [ -d "$Z" ] && ( cd "$Z" && find . -mindepth 1 -maxdepth 1 -printf '%f\n' ); } | sort -u > "$TMP/teile"
	while IFS= read -r t; do
		case "$t" in
			sysupgrade|factory|other)
				# Basis komplett (ohne Manifeste und Editor-Reste)
				if [ -d "$B/$t" ]; then
					while IFS= read -r f; do verlinken "$B/$t/$f" "$O/$t"
					done < <(cd "$B/$t" && find . -mindepth 1 -maxdepth 1 ! -type d -printf '%f\n' \
						| grep -v -e '\.manifest$' -e '\.manifest\.' -e '~$' | sort)
				fi
				[ -d "$Z/$t" ] || continue
				if [ "$t" = sysupgrade ]; then
					awk '{ print $5 }' "$TMP/z.zeilen" | sort -u | while IFS= read -r f; do
						[ -e "$O/$t/$f" ] && { echo "  $t/$f gibt es schon aus der Basis" >&2; continue; }
						verlinken "$Z/$t/$f" "$O/$t"
					done
				else
					v="$(awk 'NR == 1 { print $2 }' "$TMP/z.zeilen")"
					[ -n "$v" ] || continue
					while IFS= read -r f; do
						m="$(modell_zu_datei "$f" "$v" "$TMP/z.modelle.alle")"
						[ -n "$m" ] && grep -qxF "$m" "$TMP/z.modelle" || continue
						[ -e "$O/$t/$f" ] && { echo "  $t/$f gibt es schon aus der Basis" >&2; continue; }
						verlinken "$Z/$t/$f" "$O/$t"
					done < <(cd "$Z/$t" && find . -mindepth 1 -maxdepth 1 ! -type d -printf '%f\n' | sort)
				fi
				;;
			*)
				if [ -e "$B/$t" ]; then verlinken "$B/$t" "$O"; else verlinken "$Z/$t" "$O"; fi
				;;
		esac
	done < "$TMP/teile"

	# neues Manifest
	[ -f "$MBF" ] || [ -s "$TMP/z.zeilen" ] || continue
	prio="$( [ -f "$MBF" ] && kopf_wert "$MBF" PRIORITY )"
	{
		echo "BRANCH=$BRANCH"
		echo "DATE=$(date '+%Y-%m-%d %H:%M:%S%:z')"
		echo "PRIORITY=${prio:-0}"
		echo
		awk -v shafile="$TMP/sha512" -v altf="$TMP/alt" -v ohne="$TMP/ohne4" \
		    -v mbrf="$TMP/mbr" -v alle="$( [ "$X86" = alle ] && echo 1 || echo 0)" '
			BEGIN { while ((getline z < shafile) > 0) { split(z, a, " "); s512[a[1]] = a[2] }
			        while ((getline z < altf) > 0) alt[z] = 1
			        while ((getline z < ohne) > 0) aus[z] = 1
			        while ((getline z < mbrf) > 0) { split(z, a, " ")
			                m4[a[1]] = a[2]; m4s[a[1]] = a[3]; m4x[a[1]] = a[4]
			                m5[a[1]] = a[5]; m5s[a[1]] = a[6]; m5g[a[1]] = a[7] } }
			{
				if (alle && ($6 in m5)) print $2, $3, m5s[$6], m5g[$6], m5[$6]
				else print $2, $3, $4, $5, $6
				if (($2 in alt) && !($2 in aus)) {
					if ($6 in m4) {
						print $2, $3, m4s[$6], m4[$6]
						print $2, $3, m4x[$6], m4[$6]
					} else if ($6 in s512) {
						print $2, $3, $4, $6
						print $2, $3, s512[$6], $6
					}
				}
			}' "$TMP/zeilen"
		echo "---"
	} > "$TMP/manifest"
	if [ "$PROBE" = 0 ]; then
		mkdir -p "$O/sysupgrade" && cp "$TMP/manifest" "$O/sysupgrade/$BRANCH.manifest" || exit 1
		# jede Datei im Manifest muss als Link da sein und aufloesen
		awk 'NF == 4 { print $4 } NF == 5 { print $5 }' "$TMP/manifest" | sort -u | while IFS= read -r f; do
			[ -e "$O/sysupgrade/$f" ] || { echo "  kaputt oder fehlt: $O/sysupgrade/$f" >&2; echo x >> "$TMP/kaputt"; }
		done
	fi
done < "$TMP/domains"

[ -s "$TMP/kaputt" ] && FEHLER=1
if [ -s "$TMP/unbedient" ]; then
	echo "Alte Namen (4-Feld-Zeit) ohne Image in mindestens einer Domain:" >&2
	sort "$TMP/unbedient" | uniq -c | awk '{ printf "  %s (%d Domains)\n", $2, $1 }' >&2
fi
echo "Domains: $SUMME_DOM, Modelle aus der Basis: $SUMME_B, aus dem Zusatz ergaenzt: $SUMME_Z" >&2

if [ -n "$GLUON" ]; then
	# Geraete aus targets/: Hauptname plus aliases/manifest_aliases, dazu
	# factory_image/sysupgrade_image-Namen (x86). Eine Zeile je Geraet:
	# "<target> <name> [alias ...]"
	for tf in "$GLUON"/targets/*; do
		case "$(basename "$tf")" in *.mk|*.inc|generic) continue ;; esac
		awk -v t="$(basename "$tf")" -v q="'" '
			BEGIN {
				re_kopf = "(device|factory_image|sysupgrade_image)[(]" q "[^" q "]+" q
				re_str = q "[^" q "]+" q
			}
			{ sub(/--.*/, ""); s = s $0 " " }
			END {
				while (match(s, re_kopf)) {
					kopf = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
					n = kopf; sub(/^[a-z_]+[(]/, "", n); n = substr(n, 2, length(n) - 2)
					if (kopf !~ /^device/) { if (!(n in x86)) { x86[n] = 1; print t, n }; continue }
					tiefe = 1; j = 1
					while (tiefe > 0 && j <= length(s)) {
						c = substr(s, j, 1)
						if (c == "(") tiefe++; else if (c == ")") tiefe--
						j++
					}
					body = substr(s, 1, j); zeile = t " " n
					while (match(body, /aliases[ \t]*=[ \t]*[{][^}]*[}]/)) {
						l = substr(body, RSTART, RLENGTH); body = substr(body, RSTART + RLENGTH)
						while (match(l, re_str)) { zeile = zeile " " substr(l, RSTART + 1, RLENGTH - 2); l = substr(l, RSTART + RLENGTH) }
					}
					print zeile
				}
			}' "$tf"
	done > "$TMP/geraete"
	sort -u "$TMP/bedient" > "$TMP/bedient.s"
	ndom="$(awk '{ print $1 }' "$TMP/bedient.s" | sort -u | wc -l | tr -d ' ')"
	echo "Abdeckung gegen $GLUON ($(git -C "$GLUON" describe --tags 2>/dev/null || echo 'Version unbekannt'), $ndom Domains mit Manifest):" >&2
	awk -v bf="$TMP/bedient.s" -v nd="$ndom" '
		BEGIN { while ((getline z < bf) > 0) { split(z, a, " "); if (!((a[1] SUBSEP a[2]) in g)) { g[a[1] SUBSEP a[2]] = 1; dn[a[2]]++ } } }
		{
			best = 0; for (i = 2; i <= NF; i++) if (dn[$i] > best) best = dn[$i]
			n[$1]++
			if (best == 0) fehl[$1] = fehl[$1] " " $2
			else if (best < nd) teil[$1] = teil[$1] " " $2 "(" best "/" nd ")"
		}
		END {
			for (t in n) {
				if (!(t in fehl) && !(t in teil)) continue
				printf "%s\t0\t  %s (%d Geraete)\n", t, t, n[t]
				if (t in fehl) printf "%s\t1\t    ohne Image:%s\n", t, fehl[t]
				if (t in teil) printf "%s\t2\t    nur in manchen Domains:%s\n", t, teil[t]
			}
		}' "$TMP/geraete" | sort -t "$(printf '\t')" -k1,1 -k2,2n | cut -f3- >&2
	[ -s "$TMP/geraete" ] || echo "  (keine Geraete in $GLUON/targets gefunden)" >&2
fi
if [ "$FEHLER" != 0 ]; then
	echo "Es gab Fehler (siehe oben)." >&2
	exit 1
fi
if [ "$PROBE" = 1 ]; then
	echo "Probelauf, nichts angelegt." >&2
else
	echo "Fertig: $AUS. Manifeste sind unsigniert -> manifest-pruefen.sh, dann neu unterschreiben." >&2
fi
exit 0

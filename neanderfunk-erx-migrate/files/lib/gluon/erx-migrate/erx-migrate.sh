#!/bin/sh
# erx-migrate.sh - EdgeRouter X vom alten auf das neue Flash-Layout bringen
#
# Nachbau von https://github.com/darkxst/erx-migration, angepasst auf unsere
# Lage: das Image kommt aus einer Datei oder von unserem Firmware-Server, nicht
# von downloads.openwrt.org.
#
# Warum ueberhaupt: das alte Layout hat zwei Kernel-Slots zu je 3 MB. Der
# Kernel 6.6 aus OpenWrt 24.10 (und damit Gluon 2025.1) passt da nicht mehr
# hinein. Das neue Layout hat einen Slot mit 6 MB.
#
# Der Trick dabei: es wird *nicht* umpartitioniert. kernel1 und kernel2 grenzen
# physisch aneinander, der neue Kernel wird ueber beide geschrieben, und der
# UBNT-Boot-Index in der factory-Partition (Offset 160) wird auf Slot 1
# gesetzt, damit U-Boot immer dort startet. Die neue Partitionstabelle kommt
# aus der DTS der neuen Firmware.
#
# Aufruf auf dem Geraet:
#   sh erx-migrate.sh --check                  nur pruefen, nichts aendern
#   sh erx-migrate.sh /tmp/gluon-erx.bin       migrieren
#   SHA256=<summe> sh erx-migrate.sh /tmp/gluon-erx.bin
#   UNBEAUFSICHTIGT=1 sh erx-migrate.sh ...    ohne Rueckfrage (fuer das Paket)
#
# Unsere eigenen Pakete koennen mitten in die Migration hineinrebooten. Sie
# haengen an ZWEI verschiedenen Waechtern, und keiner deckt alle ab (Notiz aus
# der Paket-Session, erx-migration-hinweis.md):
#
#   * hotfix/watchdog.sh, Deadman fuer micrond, Frist 15 Minuten. Haelt
#     ausschliesslich /tmp/hotfix.autoupdater-flashing zurueck - nicht der
#     Lock, nicht ein laufender Prozess. Er rebootet ueber
#     /proc/sysrq-trigger, also ohne sauberes Herunterfahren.
#   * linkcheck, gateway, weeklyreboot, wifi-blackout. Die sehen den Marker
#     nicht, sie halten auf /var/lock/autoupdater.lock oder einen laufenden
#     autoupdater-/sysupgrade-Prozess.
#
# Beide Marker legen sonst nur die Autoupdater-Hooks an; ein Skriptlauf erzeugt
# sie nicht. Deshalb setzt dieses Skript beide selbst.
#
# ACHTUNG: der Marker entwaffnet das gesamte Sicherheitsnetz, solange er
# existiert. /tmp liegt im tmpfs, ein Neustart raeumt ihn weg - bricht die
# Migration aber ohne Neustart ab, muss er weg. Genau das macht die
# aufraeumen()-Trap unten.

. /lib/functions.sh
include /lib/upgrade
. /usr/share/libubox/jshn.sh

export VERBOSE=1
IMAGE="${1:-}"
STAGE2="${STAGE2:-/tmp/erx-migrate-stage2.sh}"

rot()  { printf '\033[0;31m%s\033[0m\n' "$*"; }
gruen(){ printf '\033[0;32m%s\033[0m\n' "$*"; }

fehler() { rot "FEHLER: $*"; exit 1; }

LOCK="/var/lock/autoupdater.lock"
MARKER="/tmp/hotfix.autoupdater-flashing"

# Den Lock halten, solange das Skript laeuft. Einmal wieder eintreten, damit
# der ganze Ablauf darin steckt - auch die Uebergabe an Stufe 2.
if [ -z "${ERX_HAT_LOCK:-}" ]; then
    if ! command -v flock >/dev/null 2>&1; then
        fehler "flock nicht gefunden. Ohne den Lock rebooten linkcheck, gateway, weeklyreboot oder wifi-blackout mitten in die Migration."
    fi
    export ERX_HAT_LOCK=1
    # Mit Interpreter und absolutem Pfad: flock fuehrt sein Argument ueber den
    # PATH aus, und "erx-migrate.sh" steht dort nicht - der Wiedereintritt
    # scheiterte sonst still mit Exitcode 111.
    SELBST="$0"
    case "$SELBST" in /*) ;; *) SELBST="$PWD/$SELBST" ;; esac
    exec flock "$LOCK" /bin/sh "$SELBST" "$@"
fi

# Der Marker haelt den Deadman-Watchdog. Er wird beim Verlassen wieder
# entfernt - ausser wir sind ueber den Punkt hinaus, ab dem ohnehin nur noch
# ein Neustart folgt (dort wird der Trap abgeschaltet). Bliebe er liegen,
# liefe der Knoten unbewacht weiter, ohne dass irgendwo etwas auffaellt.
MARKER_VON_UNS=0
aufraeumen() {
    [ "$MARKER_VON_UNS" = "1" ] || return 0
    rm -f "$MARKER"
    echo "  Watchdog-Marker wieder entfernt."
}
trap aufraeumen EXIT INT TERM

# --- Pruefungen, die alle bestehen muessen -------------------------------

pruefe_board() {
    case "$(board_name)" in
        ubnt,edgerouter-x|ubnt,edgerouter-x-sfp) ;;
        *) fehler "falsches Board: $(board_name)" ;;
    esac
    echo "  Board:            $(board_name)"
}

pruefe_layout() {
    local compat="$(uci -q get system.@system[0].compat_version)"
    if [ "$compat" = "2.0" ]; then
        fehler "Geraet ist bereits migriert (compat_version 2.0), nichts zu tun."
    fi
    echo "  compat_version:   ${compat:-<nicht gesetzt>}  (erwartet: leer oder 1.x)"

    # Zwei Layouts sind zulaessig. Bricht ein Lauf nach dem Kernel ab, laesst
    # er das Geraet mit dem NEUEN Layout zurueck - dann heisst die Partition
    # "kernel" statt "kernel1"/"kernel2", und ein Skript, das nur die alten
    # Namen kennt, verweigert die Fortsetzung. Genau das ist am 2026-09-09
    # passiert und hat das Geraet mit neuem Kernel auf altem Rootfs stehen
    # lassen.
    for p in factory ubi; do
        find_mtd_part "$p" >/dev/null 2>&1 || fehler "Partition '$p' nicht gefunden."
    done
    if [ -n "$(find_mtd_part kernel)" ]; then
        LAYOUT=neu
        echo "  Layout:           NEU (ein Slot 'kernel'), Migration teilweise erfolgt"
        echo "                    -> es fehlt nur noch das Rootfs"
    elif [ -n "$(find_mtd_part kernel1)" ] && [ -n "$(find_mtd_part kernel2)" ]; then
        LAYOUT=alt
        echo "  Layout:           alt (kernel1 + kernel2), vollstaendige Migration"
    else
        fehler "Weder 'kernel' noch 'kernel1'/'kernel2' gefunden - unbekanntes Layout."
    fi
    local idx
    idx="$(hexdump -s 160 -n 1 -e '/1 "%X"' "/dev/mtd$(find_mtd_index factory)")"
    echo "  Boot-Index:       $idx (0 = Slot 1)"
    if [ "$LAYOUT" = neu ] && [ "$idx" != "0" ]; then
        fehler "Neues Layout, aber Boot-Index steht auf $idx. U-Boot laese dann 3 MB versetzt, mitten in den Kernel hinein."
    fi
}

pruefe_image() {
    [ -n "$IMAGE" ] || fehler "kein Image angegeben."
    [ -f "$IMAGE" ] || fehler "$IMAGE nicht gefunden."

    if [ -n "$SHA256" ]; then
        local ist="$(sha256sum "$IMAGE" | cut -d' ' -f1)"
        [ "$ist" = "$SHA256" ] || fehler "Pruefsumme stimmt nicht:
    erwartet $SHA256
    ist      $ist"
        echo "  Pruefsumme:       stimmt"
    else
        rot  "  Pruefsumme:       NICHT geprueft (SHA256= setzen)"
    fi

    board_dir="$( (tar tf "$IMAGE" | grep -m1 '^sysupgrade-.*/$') 2>/dev/null)"
    board_dir="${board_dir%/}"
    [ -n "$board_dir" ] || fehler "$IMAGE ist kein sysupgrade-tar."

    tar xC /tmp -f "$IMAGE" 2>/dev/null
    [ -f "/tmp/$board_dir/kernel" ] || fehler "kein kernel im Image."
    [ -f "/tmp/$board_dir/root" ]   || fehler "kein root im Image."

    local klen="$(wc -c < "/tmp/$board_dir/kernel")"
    echo "  Image:            $board_dir"
    echo "  Kernelgroesse:    $klen Bytes"
    if [ "$klen" -le 3145728 ]; then
        rot "  -> Kernel passt in einen 3-MB-Slot. Das ist kein Image fuer das"
        rot "     neue Layout; eine Migration waere sinnlos. Abbruch."
        exit 1
    fi
    [ "$klen" -le 6291456 ] || fehler "Kernel groesser als 6 MB, passt auch neu nicht."
    echo "  -> braucht das neue Layout, richtig so"
}

# Ein Marker aus einem frueheren, abgebrochenen Lauf ist ein stiller Defekt:
# der Knoten laeuft unbewacht, ohne dass irgendwo etwas auffaellt.
pruefe_waechter() {
    if [ -e "$MARKER" ]; then
        rot "  Watchdog-Marker:  $MARKER liegt schon da!"
        rot "                    Der Knoten laeuft derzeit UNBEWACHT - kein Check"
        rot "                    und kein Deadman rebootet noch. Stammt aus einem"
        rot "                    abgebrochenen Lauf. Nach der Migration pruefen,"
        rot "                    sonst von Hand entfernen."
    else
        echo "  Watchdog-Marker:  nicht vorhanden (gut)"
    fi
    echo "  Autoupdater-Lock: gehalten (dieses Skript laeuft unter flock $LOCK)"
}

pruefe_stage2() {
    [ -f "$STAGE2" ] || fehler "$STAGE2 fehlt - beide Skripte aufs Geraet kopieren."
    echo "  Stufe 2:          $STAGE2"
}

# Die compat_version ist der einzige Schutz davor, dass ein migrierter Knoten
# spaeter wieder ein Image fuer das ALTE Layout annimmt. fwtool_check_image
# vergleicht die Hauptversion des Images mit der des Geraets und verweigert bei
# Ungleichheit - vorausgesetzt, das Geraet meldet ueberhaupt die neue.
#
# Genau da hat die uebernommene Konfiguration ein Loch: /etc/config/system
# liegt im Overlay und wandert damit in die Sicherung. /bin/config_generate
# schreibt seine eigene compat_version nur, wenn die Datei fehlt oder leer ist
# ("[ ! -s /etc/config/system ]"), eine wiederhergestellte Datei gewinnt also.
# Ohne den folgenden Eingriff stuende der migrierte Knoten wieder auf 1.1 und
# wuerde ein 2023.2-Image *annehmen*: ein 3-MB-Kernel landet im 6-MB-Slot, und
# das alte rootfs schreibt beim naechsten Update wieder auf kernel2, das es
# nicht mehr gibt. Das faellt erst beim uebernaechsten Boot auf.
compat_version_des_images() {
    local meta="/tmp/erx-image-meta.json"
    rm -f "$meta"
    # Wie in fwtool_check_image: -i liest die angehaengten Metadaten heraus,
    # ohne das Image anzufassen. Ohne -t bleibt die Datei unveraendert.
    fwtool -q -i "$meta" "$IMAGE" || return 1
    [ -s "$meta" ] || return 1
    jsonfilter -i "$meta" -e '@.compat_version' 2>/dev/null
}

hebe_compat_version() {
    local tar="$1"
    local neu="$2"
    local arbeit="/tmp/erx-conf-patch"

    rm -rf "$arbeit"
    mkdir -p "$arbeit" || return 1
    ( cd "$arbeit" && tar xzf "$tar" ) || return 1
    [ -f "$arbeit/etc/config/system" ] || return 1

    # uci -c arbeitet auf einem beliebigen Konfigurationsverzeichnis, ohne das
    # laufende System zu beruehren. Auf dem Geraet geprueft.
    uci -c "$arbeit/etc/config" set "system.@system[0].compat_version=$neu" || return 1
    uci -c "$arbeit/etc/config" commit system || return 1

    # Mit "." als Argument tragen die Pfade ein fuehrendes "./". Der Preinit
    # packt mit "tar xzf /sysupgrade.tgz" im Wurzelverzeichnis aus, dem ist das
    # gleich.
    ( cd "$arbeit" && tar czf "$tar.neu" . ) || return 1
    mv "$tar.neu" "$tar" || return 1
    rm -rf "$arbeit"
}

echo "=== EdgeRouter-X-Migration, Vorpruefung ==="
pruefe_board
pruefe_layout
pruefe_waechter
pruefe_stage2
if [ "$IMAGE" = "--check" ]; then
    echo
    gruen "Vorpruefung ohne Image bestanden. Mit Imagepfad erneut aufrufen."
    exit 0
fi
pruefe_image

# Konfiguration sichern, bevor das System sich abbaut.
#
# Die Vorlage tut das nicht, und genau deshalb verliert sie die Einstellungen:
# stage2 baut die UBI-Volumes neu auf, rootfs_data ist danach leer. Die Datei
# liegt im tmpfs und ueberlebt den Wechsel in den RAM-Root; stage2 legt sie mit
# nand_restore_config in das frische rootfs_data, wo der Preinit des neuen
# Systems sie findet - derselbe Weg, den ein normales sysupgrade nimmt.
#
# KEIN_CONFIG=1 schaltet das ab, wenn man bewusst mit leerer Konfiguration
# starten will.
CONF_TAR="/tmp/sysupgrade.tgz"
if [ "${KEIN_CONFIG:-0}" = "1" ]; then
    echo "  Konfiguration:    wird auf Wunsch NICHT uebernommen (KEIN_CONFIG=1)"
    rm -f "$CONF_TAR"
else
    rm -f "$CONF_TAR"
    if sysupgrade -b "$CONF_TAR" >/dev/null 2>&1 && [ -s "$CONF_TAR" ]; then
        echo "  Konfiguration:    gesichert nach $CONF_TAR ($(wc -c < "$CONF_TAR") Bytes)"

        IMAGE_COMPAT="$(compat_version_des_images)"
        [ -n "$IMAGE_COMPAT" ] || fehler "Das Image nennt keine compat_version.
    Ohne sie laesst sich der Downgrade-Schutz nicht setzen, und der migrierte
    Knoten wuerde spaeter ein Image fuer das alte Layout annehmen."
        if hebe_compat_version "$CONF_TAR" "$IMAGE_COMPAT"; then
            echo "  compat_version:   in der Sicherung auf $IMAGE_COMPAT gehoben"
        else
            fehler "compat_version liess sich nicht auf $IMAGE_COMPAT heben.
    Nach der Migration von Hand nachziehen:
      uci set system.@system[0].compat_version=$IMAGE_COMPAT && uci commit system"
        fi
    else
        fehler "Konfiguration liess sich nicht sichern. Mit KEIN_CONFIG=1 bewusst ohne starten."
    fi
fi

echo
if [ "${KEIN_CONFIG:-0}" = "1" ]; then
    rot "Dies loescht alle Einstellungen des Geraets."
else
    rot "Dies schreibt Kernel und Rootfs neu. Die Konfiguration wird uebernommen,"
    rot "der Versuch kann aber fehlschlagen - dann kommt das Geraet im Config-Mode hoch."
fi
# UNBEAUFSICHTIGT=1 ueberspringt die Rueckfrage. Gedacht fuer den Aufruf aus
# neanderfunk-erx-migrate heraus, wo niemand am Terminal sitzt. Von Hand bitte
# nicht setzen - die Rueckfrage ist die letzte Stelle, an der ein Tippfehler im
# Imagepfad noch auffaellt.
#
# Alles, was vor dieser Zeile steht, ist Pruefung ohne Schreibzugriff. Ab hier
# wird das Geraet angefasst.
if [ "${UNBEAUFSICHTIGT:-0}" = "1" ]; then
    echo "Fortfahren? (ja/nein) ja   [UNBEAUFSICHTIGT=1]"
else
    printf 'Fortfahren? (ja/nein) '
    read -r antwort
    [ "$antwort" = "ja" ] || { echo "Abgebrochen."; exit 0; }
fi

# Ab hier haelt der Marker den Deadman-Watchdog. Ohne ihn rebootet
# hotfix/watchdog.sh nach 15 Minuten ohne micrond hart ueber
# /proc/sysrq-trigger - mitten in die Repartitionierung hinein.
touch "$MARKER" || fehler "Watchdog-Marker $MARKER liess sich nicht anlegen."
MARKER_VON_UNS=1
echo "  Watchdog-Marker:  gesetzt ($MARKER)"

# Der Marker allein genuegt NICHT, und das hat vier Fehlversuche gekostet.
#
# /lib/gluon/neanderfunk-hotfix/watchdog.sh laeuft in einer Schleife:
#
#     while : ; do
#         if ! sleep "$slice" ; then
#             reboot_now "unable to fork (out of memory?)"
#         fi
#
# Beim Abbau schickt sysupgrade TERM und dann KILL an alle Prozesse. Damit
# stirbt dieses "sleep", die Bedingung greift, und der Watchdog rebootet hart
# ueber /proc/sysrq-trigger - mitten in die Migration. Es ist gar kein
# Speichermangel, es ist das Signal.
#
# Den Marker prueft er nur VOR der Schleife. Eine Instanz, die schon laeuft und
# schlaeft, sieht ihn also nie. Deshalb muss micrond angehalten und die
# laufende Instanz beendet werden, nicht bloss eine Datei angelegt.
if [ -x /etc/init.d/micrond ]; then
    /etc/init.d/micrond stop >/dev/null 2>&1 && echo "  micrond:          angehalten"
fi
# Bewusst OHNE -f. "pgrep -f" durchsucht die ganze Kommandozeile und findet
# damit auch jeden Prozess, in dessen Aufruf der Pfad bloss vorkommt - im
# Zweifel dieses Skript selbst, das sich dann mitten in der Migration
# erschiesst. Hinweis aus der Paket-Session, am 2026-09-09 am Knoten
# nachgeprueft:
#
#   pgrep    watchdog.sh  -> nur das Skript          (comm=watchdog.sh)
#   pgrep -f watchdog.sh  -> zusaetzlich die Shell   (comm=ash), die es startete
#
# BusyBox setzt comm bei Skripten auf den Skriptnamen, deshalb genuegt der
# Name ohne Pfad.
WD_PIDS="$(pgrep watchdog.sh 2>/dev/null | tr '\n' ' ')"
if [ -n "$WD_PIDS" ]; then
    # shellcheck disable=SC2086
    kill $WD_PIDS 2>/dev/null
    sleep 1
    # shellcheck disable=SC2086
    kill -9 $WD_PIDS 2>/dev/null
    echo "  Watchdog-Instanz: beendet (PID $WD_PIDS)"
else
    echo "  Watchdog-Instanz: laeuft gerade keine"
fi

install_bin /sbin/upgraded

# Punkt ohne Wiederkehr. Ab jetzt endet der Vorgang nur noch mit einem
# Neustart, und der raeumt das tmpfs samt Marker ohnehin weg. Der Trap muss
# hier weg, sonst nimmt er beim Abbau des Systems den Marker mit - und der
# Watchdog waere waehrend Stufe 2 wieder scharf.
trap - EXIT INT TERM

v "Uebergabe an Stufe 2, alle Sitzungen werden beendet."

json_init
json_add_string prefix "/tmp/root"
json_add_string path "$IMAGE"
json_add_boolean force 1
json_add_string command "sh $STAGE2"
json_add_object options
json_add_int save_partitions 0
json_close_object
ubus call system sysupgrade "$(json_dump)"

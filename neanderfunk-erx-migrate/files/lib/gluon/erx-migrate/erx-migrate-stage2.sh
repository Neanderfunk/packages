#!/bin/sh
# erx-migrate-stage2.sh - laeuft aus dem RAM-Root, nachdem Stufe 1 das System
# abgebaut hat. Ab hier gibt es kein Zurueck.
#
# Nachbau von ubnt_erx_stage2.sh aus https://github.com/darkxst/erx-migration.
# Die Reihenfolge und die Schreibvorgaenge sind uebernommen - an dieser Stelle
# etwas "verbessern" zu wollen, macht das Geraet kaputt. Zwei Dinge kommen
# bewusst hinzu:
#
#  * Der Kernel wird nach dem Schreiben zurueckgelesen und verglichen, und der
#    Boot-Index erst danach umgesetzt. "mtd write" ueberspringt Bad Blocks;
#    liegt einer in kernel1, wird der Kernel still zerschnitten. Die Markierung
#    laesst sich mit den Werkzeugen im Image nicht abfragen, ihre Folge schon.
#
#  * Die Konfiguration wird uebernommen. Die Vorlage verliert sie, weil sie kein
#    Archiv anlegt und nach dem Neuaufbau der UBI-Volumes nichts zurueckspielt.

. /lib/functions.sh
include /lib/upgrade

CI_KERNPART="none"          # Kernel wird hier von Hand geschrieben

tar_file="$IMAGE"
board_dir="$( (tar tf "$tar_file" | grep -m1 '^sysupgrade-.*/$') 2>/dev/null)"
board_dir="${board_dir%/}"

# UBNT legt in der factory-Partition ab Offset 160 ab, aus welchem Kernel-Slot
# gebootet wird. 0 = Slot 1. Geschrieben wird eine 0x00 ohne vorheriges
# Loeschen - auf NAND ist das zulaessig, weil dabei nur Bits von 1 auf 0
# kippen.
ubnt_update_kernel_flag() {
    local OFFSET=160
    # Gelesen wird ueber das CHAR-Geraet: das Block-Geraet ist seitengepuffert
    # und kann einen alten Wert liefern.
    local factory_c="/dev/mtd$(find_mtd_index factory)"
    # Geschrieben wird ueber das BLOCK-Geraet. Ein einzelnes Byte aufs
    # Char-Geraet lehnt der NAND-Treiber ab ("attempt to write non page aligned
    # data"); mtdblock macht das noetige Lesen-Aendern-Schreiben der Seite.
    local factory_b="$(find_mtd_part factory)"
    [ -c "$factory_c" ] || { echo "factory ($factory_c) nicht gefunden" >&2; return 1; }
    [ -b "$factory_b" ] || { echo "factory ($factory_b) nicht gefunden" >&2; return 1; }

    # Ohne hexdump, ohne od: im RAM-Root von sysupgrade sind sie nicht
    # vorhanden. hexdump lieferte dort einen LEEREN Wert, der Vergleich schlug
    # fehl, und das Skript schrieb den Index, obwohl nichts zu tun war.
    # Verglichen wird deshalb ueber die Pruefsumme des einen Bytes - dd und
    # md5sum sind im RAM-Root belegt vorhanden.
    local NULL_MD5=93b885adfe0da089cdf634904fd59f71   # md5 von 0x00
    local ist
    ist="$(dd if="$factory_c" bs=1 skip=$OFFSET count=1 2>/dev/null | md5sum | cut -d" " -f1)"
    if [ "$ist" = "d41d8cd98f00b204e9800998ecf8427e" ] || [ -z "$ist" ]; then
        echo "Boot-Index liess sich nicht lesen (leere Eingabe) - dd defekt?" >&2
        return 1
    fi
    if [ "$ist" = "$NULL_MD5" ]; then
        v "Boot-Index steht bereits auf Slot 1, nichts zu tun"
        return 0
    fi
    v "Boot-Index auf 0 setzen"
    printf '\000' | dd of="$factory_b" bs=1 count=1 seek=$OFFSET conv=notrunc 2>/dev/null || {
        echo "Boot-Index liess sich nicht setzen" >&2; return 1; }
    sync
    local nachher
    nachher="$(dd if="$factory_c" bs=1 skip=$OFFSET count=1 2>/dev/null | md5sum | cut -d" " -f1)"
    [ "$nachher" = "$NULL_MD5" ] || {
        echo "Boot-Index steht nach dem Schreiben nicht auf 0" >&2; return 1; }
    v "Boot-Index gesetzt und geprueft"
}

# Der neue Kernel ist groesser als ein Slot. kernel1 und kernel2 grenzen
# physisch aneinander, deshalb wird er ueber beide geschrieben.
prepare_kernel() {
    # Zwei Layouts, und das Skript muss beide beherrschen: ein Lauf, der nach
    # dem Kernel abbricht, laesst das Geraet mit dem NEUEN Layout zurueck. Beim
    # naechsten Versuch heisst die Partition dann "kernel" statt
    # "kernel1"/"kernel2", und ein Skript, das nur die alten Namen kennt,
    # bricht ab ("kernel1/kernel2 nicht gefunden"). Genau das ist am
    # 2026-09-09 passiert.
    local kf="/tmp/$board_dir/kernel"
    local klen="$( (cat "$kf" | wc -c) 2>/dev/null)"

    # Verglichen werden die vollen 4-KiB-Bloecke. Die letzten paar hundert
    # Bytes bleiben aussen vor - fuer den Zweck reicht das: ein uebersprungener
    # Bad Block verschiebt alles ab seiner Stelle, das faellt lange vorher auf.
    #
    # Bewusst OHNE "head": im RAM-Root von sysupgrade ist es nicht vorhanden,
    # und der Vergleich lief dann gegen eine leere Eingabe - md5 d41d8cd9...,
    # also ein Fehlalarm bei einwandfrei geschriebenem Kernel.
    local bl=$((klen / 4096))
    local soll="$(dd if="$kf" bs=4096 count="$bl" 2>/dev/null | md5sum | cut -d" " -f1)"
    [ -n "$soll" ] && [ "$soll" != "d41d8cd98f00b204e9800998ecf8427e" ] \
        || { echo "Sollsumme liess sich nicht bilden - dd oder md5sum fehlen?" >&2; exit 1; }

    if [ -n "$(find_mtd_part kernel)" ]; then
        prepare_kernel_neu "$kf" "$klen" "$soll" "$bl"
    else
        prepare_kernel_alt "$kf" "$klen" "$soll" "$bl"
    fi
}

# Neues Layout: ein Slot ueber 6 MB, kein Slotwechsel, kein Indexspiel. Der
# Boot-Index muss allerdings auf 0 stehen - bei 1 laese U-Boot 3 MB versetzt,
# also mitten in den Kernel hinein.
prepare_kernel_neu() {
    local kf="$1" klen="$2" soll="$3" bl="$4"
    local kc="/dev/mtd$(find_mtd_index kernel)"
    [ -c "$kc" ] || { echo "$kc nicht gefunden" >&2; exit 1; }

    local versuch=1
    while : ; do
        v "Kernel schreiben (neues Layout), $klen Bytes (Versuch $versuch)"
        mtd write "$kf" kernel || { echo "mtd write fehlgeschlagen" >&2; exit 1; }
        sync
        local ist
        ist="$(dd if="$kc" bs=4096 count="$bl" 2>/dev/null | md5sum | cut -d" " -f1)"
        if [ "$ist" = "$soll" ]; then
            v "Kernel zurueckgelesen und geprueft: $soll"
            break
        fi
        echo "Kernel im Flash weicht ab (soll $soll, ist $ist)" >&2
        if [ "$versuch" -ge 2 ]; then
            echo "Abbruch. Rettung ueber die serielle Konsole, Bootmenue Ziffer 2 (TFTP)." >&2
            exit 1
        fi
        versuch=$((versuch + 1))
    done
    ubnt_update_kernel_flag || exit 1
}

prepare_kernel_alt() {
    local kf="$1" klen="$2" soll="$3" bl="$4"
    local k1="$(find_mtd_part kernel1)"
    local k2="$(find_mtd_part kernel2)"
    local k1c="/dev/mtd$(find_mtd_index kernel1)"
    local k2c="/dev/mtd$(find_mtd_index kernel2)"
    [ -n "$k1" ] && [ -n "$k2" ] || { echo "weder kernel noch kernel1/kernel2 gefunden" >&2; exit 1; }
    [ -c "$k1c" ] && [ -c "$k2c" ] || { echo "Char-Geraete $k1c/$k2c nicht gefunden" >&2; exit 1; }

    local versuch=1
    while : ; do
        v "Kernel schreiben (altes Layout), $klen Bytes (Versuch $versuch)"
        dd if="$kf" bs=1024 count=3072 | mtd write - "kernel1"
        if [ "$klen" -ge 3145728 ]; then
            v "Rest nach kernel2"
            dd if="$kf" bs=1024 skip=3072 | mtd write - "kernel2"
        fi
        sync
        # Ueber die Char-Geraete lesen: die Block-Geraete sind seitengepuffert
        # und liefern den alten Inhalt - das hat einmal einen Fehlalarm mitten
        # in der Migration ausgeloest.
        local ist
        ist="$( { dd if="$k1c" bs=4096 count=768; \
                  dd if="$k2c" bs=4096 count=$((bl - 768)); } 2>/dev/null \
                | md5sum | cut -d" " -f1 )"
        if [ "$ist" = "$soll" ]; then
            v "Kernel zurueckgelesen und geprueft: $soll"
            break
        fi
        echo "Kernel im Flash weicht ab (soll $soll, ist $ist)" >&2
        if [ "$versuch" -ge 2 ]; then
            echo "" >&2
            echo "Abbruch. ACHTUNG: der alte Kernel in Slot 2 ist beim Schreiben" >&2
            echo "ueberschrieben worden, das Geraet startet so nicht mehr." >&2
            echo "Rettung ueber die serielle Konsole, Bootmenue Ziffer 2 (TFTP)." >&2
            exit 1
        fi
        versuch=$((versuch + 1))
    done
    ubnt_update_kernel_flag || exit 1
}

prepare_rootfs() {
    v "Auf Reste der Stockfirmware pruefen"
    local ubidev="$(nand_find_ubi "$CI_UBIPART")"
    if [ -z "$ubidev" ]; then
        local mtdnum="$(find_mtd_index "$CI_UBIPART")"
        [ -n "$mtdnum" ] || { echo "ubi-Partition $CI_UBIPART nicht gefunden" >&2; exit 1; }
        ubiattach -m "$mtdnum"
        sync
        ubidev="$(nand_find_ubi "$CI_UBIPART")"
    fi
    if [ -n "$ubidev" ]; then
        local troot="$(nand_find_volume $ubidev troot)"
        [ -n "$troot" ] && ubirmvol /dev/$ubidev -N troot || true
    fi

    v "Rootfs schreiben"
    local rf="/tmp/$board_dir/root"
    local rlen="$( (cat "$rf" | wc -c) 2>/dev/null)"
    local rtype="$(identify_tar "$tar_file" "$board_dir/root" "")"

    nand_upgrade_prepare_ubi "$rlen" "$rtype" "" "0" || return 1

    ubidev="$(nand_find_ubi "$CI_UBIPART")"
    local rootvol="$(nand_find_volume $ubidev "$CI_ROOTPART")"
    ubiupdatevol /dev/$rootvol -s "$rlen" "$rf"
}

# Konfiguration in das neue rootfs_data legen, damit der Preinit des neuen
# Systems sie aufnimmt. Genau dieser Weg fehlt in der Vorlage, und deshalb
# verliert sie die Konfiguration. nand_restore_config kommt aus
# /lib/upgrade/nand.sh und macht nichts anderes als ein normales sysupgrade.
restore_config() {
    local conf="/tmp/sysupgrade.tgz"
    if [ ! -f "$conf" ]; then
        v "Keine gesicherte Konfiguration gefunden - das neue System startet im Config-Mode"
        return 0
    fi
    v "Konfiguration in das neue rootfs_data legen ($(wc -c < "$conf") Bytes)"
    if nand_restore_config "$conf"; then
        v "Konfiguration uebernommen"
    else
        # Kein Abbruch: das Geraet ist startfaehig, es kommt nur im
        # Config-Mode hoch. Das ist aergerlich, aber kein Schaden.
        echo "Konfiguration liess sich nicht ablegen - das Geraet startet im Config-Mode" >&2
    fi
}

prepare_kernel
prepare_rootfs
restore_config

v "Neustart"
umount -a
reboot -f
sleep 5
echo b 2>/dev/null > /proc/sysrq-trigger

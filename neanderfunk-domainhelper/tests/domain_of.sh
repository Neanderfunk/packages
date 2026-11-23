#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
#
# Prueft dh_domain_of (lib.sh) gegen alte und neue Codes. Wird nicht
# installiert. Aufruf auf dem Rechner (dash) oder auf einem Knoten
# (busybox ash):
#     sh tests/domain_of.sh files/lib/gluon/neanderfunk-domainhelper/lib.sh <domains-verzeichnis>
# <domains-verzeichnis> enthaelt je Domain eine Datei <NN>_<name>.json
# (auf dem Knoten /lib/gluon/domains).
. "$1"
eval "$(sed -n '/^dh_dom_by_nn()/,/^}/p' "$1" | sed "s#/lib/gluon/domains#$2#")"
fail=0
t() { r="$(dh_domain_of "$1" "$2")"; [ "$r" = "$3" ] && echo "ok   [$1|$2] -> '$r'" || { echo "FAIL [$1|$2] -> '$r' (erwartet '$3')"; fail=1; }; }
t 21_dias ffnef 21_dias
t "" nef-21_dias_EOL 21_dias
t "" dus-13_dusfl_EOL 13_dusfl
t nef-21_dias "" 21_dias
t "" 21_dias 21_dias
t "" 10_wlf 10_wlf
t "" 18_dusuk 18_nefuk
t "" nef-18_uk 18_nefuk
t "" dus-13_dus 13_dusfl
t "" 13_dus 13_dusfl
t "" bgl-43_bglgl 43_bggl
t "" bgl-47_bglrr 47_roes
t "" nef-48_rdv 48_rdvw
t "" lvrsw-38_lvrsw 38_siwiw
t "" nef-01_erk 07_erk
t "" nef-mon_05 05_mon
t ffnefd21 "" 21_dias
t FFNEFd03 "" 03_rat
t ffnefd99 "" ""
t "" ffnef-vel 01_vel
t ffnef_lvr ffnef 11_lvr
t "" ffnef-dusuk 12_dusuk
t "" ffdus 13_dusfl
t "" ffbar 14_bar
t "" wip 17_wip
t "" ffgl-bgl 43_bggl
t "" ffbgl 43_bggl
t "" bgl 43_bggl
t "" ffrrh 47_roes
t "" ffgl-ode 46_odth
t "" ffnef ""
t "" sisi ""
t "" ffhb ""
t "" ffgl-kut ""
t "" ffgl-lgn ""
t "" ffw ""
t "" ffki ""
t ffmsd01 "" ffmsd01
t "" foo-bar_x bar_x
t "" 99_xyz 99_xyz
t "" "" ""
exit $fail

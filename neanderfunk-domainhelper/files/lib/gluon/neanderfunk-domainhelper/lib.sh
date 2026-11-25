#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
#
# Gemeinsame Funktionen von neanderfunk-domainhelper, zum Sourcen:
#     . /lib/gluon/neanderfunk-domainhelper/lib.sh
#
# Bewusst Shell, kein Lua: Teile davon sollen spaeter im Minutentakt laufen
# (automesh, docs/entwurf-automesh.md), und auf 64-MB-Geraeten kostet jeder
# Lua-Start spuerbar Speicher. Gelesen wird JSON mit jsonfilter, geschrieben
# mit jshn.

DH_TAG=neanderfunk-domainhelper
# Feldtrenner fuer Zwischendateien: Steuerzeichen, kommt in iw-Ausgaben
# nicht vor (iw maskiert nicht druckbare Zeichen in SSIDs als \xNN), und
# anders als Tab kein IFS-Leerraum, leere Felder bleiben also erhalten
DH_US="$(printf '\037')"
# So lange wird nach dem Start einer LAN-Pruefung auf Antworten gewartet
DH_LAN_WAIT=60

dh_log() {
	logger -t "$DH_TAG" "$*"
}

dh_uptime() {
	local up rest
	read up rest < /proc/uptime
	echo "${up%%.*}"
}

# node_id: primaere MAC ohne Doppelpunkte, klein (wie gluon.util.node_id)
dh_own_id() {
	tr -d ':\n' < /lib/gluon/core/sysconfig/primary_mac | tr 'A-F' 'a-f'
}

# dh_domain_of <domain_code> <site_code>: Domain eines Nachbarn aus seiner
# respondd-Antwort. Multi-Domain-Firmware meldet domain_code. Single-Domain-
# Images melden nur site_code "<praefix>-<domain>", die Sackgasse 2021.1
# dazu mit Suffix _EOL (nef-21_dias_EOL, dus-13_dusfl_EOL, bgl-43_bggl_EOL),
# die Supernodes melden domain_code im selben Format (nef-21_dias). Praefix
# und Suffix fallen weg, es bleibt die Domain dieser Firmware; deren Codes
# haben nie einen Bindestrich.
#
# Aeltere Codes (0.13, Herkunft aus der Git-Historie von FirmwareConfigs,
# site-ffnef und ansible-ffnef, 23.11.2026):
# - <NN>_<name> mit oder ohne Praefix: die Nummer entscheidet, so dass auch
#   umbenannte Domains passen (18_dusuk und nef-18_uk = 18_nefuk, 13_dus,
#   bgl-43_bglgl bis 47_bglrr, 48_rdv, lvrsw-37_lvrsw ... vom 05.03.2024).
#   Kennt die Firmware die Nummer nicht, bleibt der Code wie er ist.
# - nef-01_erk (Tippfehler bis 2020) = 07_erk, nef-mon_05 = 05_mon.
# - ffnefd<NN>, bis 2023 FFNEFd<NN>: Supernodes (py_respondd, Ansible
#   "<kurzname>d<domaene>").
# - Namen vor den Domainnummern (bis 2020, Bergisch Gladbach bis 2018):
#   ffnef-<name>, ffnef_<name> (Multidomain 2019/2020), ff<name>,
#   ffgl-<name> und <name> allein, ueber die Tabelle unten.
# - Mehrdeutig, also unbekannt: ffnef ohne domain_code, ffdus (bis 2020
#   eine Domain 10.155.0.0/16, daraus 06.2020 12_dusuk und 13_dusfl),
#   Siegerland vor 2020
#   (sisi, sihb, ffhb, sifb), Kuerten, Overath, Koeln-rrh, Langenfeld der
#   GL-Gruppe (ffgl-kut, -ovr, -cgr, -lgn). Fremde Communities (ffw, ffki,
#   ffgek, ffwit, ffmz, ffmsd<NN>) loesen ohnehin nichts aus, weil sie keine
#   Domain dieser Firmware nennen.
dh_domain_of() {
	local d="$1" s n=
	[ -n "$d" ] || d="$2"
	d="${d%_EOL}"
	d="${d%_eol}"
	case "$d" in
		nef-01_erk) d=07_erk ;;
		nef-mon_05) d=05_mon ;;
	esac
	s="${d#*-}"
	case "$s" in
		[0-9][0-9]_?*)
			n="$(dh_dom_by_nn "${s%%_*}")"
			echo "${n:-$s}"
			return 0 ;;
	esac
	case "$d" in
		[Ff][Ff][Nn][Ee][Ff]d[0-9][0-9])
			dh_dom_by_nn "${d#?????d}"
			return 0 ;;
		ffnef[-_]?*) s="${d#ffnef?}" ;;
		ffgl-?*) s="${d#ffgl-}" ;;
		ff?*) s="${d#ff}" ;;
		*) s="$d" ;;
	esac
	case "$s" in
		vel) n=01 ;; met) n=02 ;; rat) n=03 ;; hld) n=04 ;; mon) n=05 ;;
		han) n=06 ;; erk) n=07 ;; hlg) n=08 ;; lgf) n=09 ;; wlf) n=10 ;;
		lvr) n=11 ;; dusuk) n=12 ;; dusfl) n=13 ;; bar) n=14 ;;
		mrh) n=15 ;; gmb) n=16 ;; wip) n=17 ;; bgl) n=43 ;; lln) n=44 ;;
		bcd) n=45 ;; ode) n=46 ;; rrh) n=47 ;;
		nef|dus|sisi|sihb|hb|sifb|kut|ovr|cgr|lgn) return 0 ;;
	esac
	if [ -n "$n" ] ; then
		dh_dom_by_nn "$n"
		return 0
	fi
	case "$d" in
		?*-?*) echo "${d#*-}" ;;
		*) [ -n "$1" ] && echo "$d" ;;
	esac
	return 0
}

# MAC-Adresse? (klein geschrieben erwartet)
dh_is_mac() {
	case "$1" in
		[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]) return 0 ;;
	esac
	return 1
}

# dh_lan_mesh <own_id> <ausgabedatei>
#
# LAN-Mesh: alle batman-Interfaces ausser mesh-vpn und den WLAN-Meshes
# (meshN). Je Interface die direkten Nachbarn per respondd fragen (wie die
# Statusseite). Die Domain steht in system.domain_code; Single-Domain-
# Images haben das Feld nicht, dann aus dem site_code (dh_domain_of, auch fuer
# die Sackgasse mit _EOL).
#
# Die Antworten kommen nicht sofort: Auf der Statusseite stehen Nachbarn oft
# bis zu 30 s nur als MAC da. Deshalb wird wiederholt gefragt, bis jeder
# batman-Nachbar am LAN geantwortet hat (erkannt an seinen MACs in
# network.mesh), hoechstens DH_LAN_WAIT Sekunden lang.
#
# Ausgabe je Nachbar eine Zeile, Felder durch DH_US getrennt:
#     <iface> <node_id> <domain> <mac>
# node_id und domain leer, wenn der Nachbar nicht geantwortet hat; mac leer,
# wenn eine Antwort keiner batman-MAC zuzuordnen war.
dh_lan_mesh() {
	local own="$1" out="$2" d ifname line mac deadline key
	d="/tmp/$DH_TAG.lan.$$"
	rm -rf "$d"
	mkdir -p "$d" || return 1

	batctl n -H 2>/dev/null | awk '
		$1 != "mesh-vpn" && $1 !~ /^mesh[0-9]+$/ {
			m = tolower($2)
			if (m ~ /^[0-9a-f][0-9a-f](:[0-9a-f][0-9a-f])(:[0-9a-f][0-9a-f])(:[0-9a-f][0-9a-f])(:[0-9a-f][0-9a-f])(:[0-9a-f][0-9a-f])$/)
				print $1, m
		}' | sort -u > "$d/pending"
	: > "$d/found"
	: > "$d/matched"

	deadline=$(( $(dh_uptime) + DH_LAN_WAIT ))
	while [ -s "$d/pending" ] && [ "$(dh_uptime)" -lt "$deadline" ] ; do
		for ifname in $(cut -d' ' -f1 "$d/pending" | sort -u) ; do
			gluon-neighbour-info -i "$ifname" -d ff02::2:1001 -p 1001 \
				-t 5 -r nodeinfo > "$d/ni" 2>/dev/null
			while read -r line ; do
				NI_ID= ; NI_DC= ; NI_SC=
				eval "$(jsonfilter -s "$line" -e 'NI_ID=@.node_id' \
					-e 'NI_DC=@.system.domain_code' \
					-e 'NI_SC=@.system.site_code' 2>/dev/null)"
				NI_ID="$(echo "$NI_ID" | tr 'A-F' 'a-f')"
				[ -n "$NI_ID" ] && [ "$NI_ID" != "$own" ] || continue
				key="$ifname $NI_ID"
				if ! grep -qxF "$key" "$d/found.keys" 2>/dev/null ; then
					echo "$key" >> "$d/found.keys"
					NI_DC="$(dh_domain_of "$NI_DC" "$NI_SC")"
					printf '%s%s%s%s%s\n' "$ifname" "$DH_US" "$NI_ID" \
						"$DH_US" "$NI_DC" >> "$d/found"
				fi
				for mac in $(jsonfilter -s "$line" \
						-e '@.network.mesh[*].interfaces[*][*]' 2>/dev/null \
						| tr 'A-F' 'a-f') ; do
					if grep -qxF "$ifname $mac" "$d/pending" ; then
						grep -vxF "$ifname $mac" "$d/pending" > "$d/p2"
						mv "$d/p2" "$d/pending"
						echo "$ifname $NI_ID $mac" >> "$d/matched"
					fi
				done
			done < "$d/ni"
		done
	done

	# Beantwortete Nachbarn in der Reihenfolge der Antworten, mit der zuletzt
	# zugeordneten MAC; dann wer bis zum Schluss nicht geantwortet hat, nur
	# mit MAC
	{
		while IFS="$DH_US" read -r ifname id dom ; do
			mac="$(awk -v i="$ifname" -v n="$id" \
				'$1 == i && $2 == n { m = $3 } END { print m }' "$d/matched")"
			printf '%s%s%s%s%s%s%s\n' "$ifname" "$DH_US" "$id" "$DH_US" \
				"$dom" "$DH_US" "$mac"
		done < "$d/found"
		while read -r ifname mac ; do
			printf '%s%s%s%s%s\n' "$ifname" "$DH_US$DH_US" "" "$DH_US" "$mac"
		done < "$d/pending"
	} > "$out"
	rm -rf "$d"
}

# dh_lan_target <eigene_domain> <datei aus dh_lan_mesh>
#
# Gibt die Domain aus, in die umgeschaltet werden soll, sonst nichts:
# genau eine fremde Domain am Kabel, die im Image steht, und keine weitere
# fremde Domain (auch keine, die das Image nicht kennt). Nachbarn ohne
# Domainangabe zaehlen nicht.
dh_lan_target() {
	local own="$1" file="$2" doms
	doms="$(awk -F "$DH_US" -v o="$own" '$3 != "" && $3 != o { print $3 }' \
		"$file" | sort -u)"
	[ -n "$doms" ] || return 0
	[ "$(echo "$doms" | wc -l)" -eq 1 ] || return 0
	case "$doms" in
		*[!A-Za-z0-9_-]*) return 0 ;;
	esac
	[ -f "/lib/gluon/domains/$doms.json" ] || return 0
	echo "$doms"
}

# dh_scan <verzeichnis>
#
# WLAN-Scan je Band ueber ein eigenes Interface. Legt in <verzeichnis> ab:
#   ifaces    eigene WLAN-Interfaces "name mac freq typ"
#   own       eigene MACs
#   targets   gescannte Interfaces "name|typ"
#   scan.res  je Scan "iface ok anzahl"
#   scan.all  rohe Ausgabe aller Scans (iw dev <if> scan passive)
#
# Passiv, nicht aktiv: ath11k verlaesst bei einem aktiven Scan seinen Kanal
# nicht, solange auf dem Radio ein AP laeuft, ein passiver Scan geht ueber alle
# Kanaele (MR80X v2, IPQ5018, auf mesh0 wie client0; 25.11.2026). Mesh-Punkte
# und APs senden Beacons, passiv fehlt also nichts, was hier gesucht wird.
# Ohne lowpri: das lehnt ath11k ab (-95). MT7986 meldet zeitweise -105
# (No buffer space), dann einmal nach 3 s wiederholen. Nur wenn passiv gar
# nichts kommt, zuletzt aktiv.
#
# DH_SCAN_ROUNDS Scans je Interface, zusammengefasst: Ein einzelner passiver
# Scan verpasst viel. Gemessen 25.11.2026 (je 5 Scans, 2.4 GHz, Anteil der
# Mesh-Punkte je Scan im Mittel/schlechtesten): WR1043ND v2 (ath9k) 64/44 %,
# M60 (mt7981) 83/67 %, MR80X v2 (ath11k) 98/88 %, Xiaomi 4A (mt76) 100 %;
# drei Scans hintereinander 96/89 %, 100 %, 100 %, 100 %. scan.all enthaelt
# alle Runden, also BSSIDs mehrfach (dh_scan_list und locate fassen zusammen).
# dh_scan_one <if> [scan-optionen]: nach $W/scan.one, 0 wenn ein BSS dabei ist
dh_scan_one() {
	local i="$1"
	shift
	iw dev "$i" scan "$@" > "$W/scan.one" 2>/dev/null
	head -n 1 "$W/scan.one" | grep -q '^BSS'
}

DH_SCAN_ROUNDS=3

dh_scan() {
	local W="$1" ifname typ ok count opts round
	# Eigene WLAN-Interfaces: Name, MAC, Typ, Frequenz (Zeilen "name mac freq typ")
	iw dev 2>/dev/null | awk '
		function out() { if (n != "") print n, (m == "" ? "-" : m), (f == "" ? 0 : f), t }
		/^[ \t]*Interface[ \t]/ { out(); n = $2; m = ""; t = ""; f = ""; next }
		n == "" { next }
		/^[ \t]*addr[ \t]/ { m = tolower($2) }
		/^[ \t]*type[ \t]/ { t = $0; sub(/^[ \t]*type[ \t]+/, "", t); sub(/[ \t]+$/, "", t) }
		f == "" && /\([0-9]+ MHz\)/ { s = $0; sub(/^.*\(/, "", s); sub(/ MHz\).*$/, "", s); f = s + 0 }
		END { out() }' > "$W/ifaces"
	awk '$2 != "-" { print $2 }' "$W/ifaces" > "$W/own"

	# Je Band ein Interface zum Scannen: Mesh-Punkt zuerst, dann Station,
	# zuletzt AP (der braucht ap-force). Ausgabe "name typ", nach Name sortiert.
	awk '
		{
			t = $0; sub(/^[^ ]+ [^ ]+ [^ ]+ /, "", t)
			r = (t == "mesh point") ? 1 : (t == "managed") ? 2 : (t == "AP") ? 3 : 0
			if (!r) next
			b = ($3 >= 4000) ? "5" : "2.4"
			if (!(b in best) || r < rank[b]) { best[b] = $1; rank[b] = r; typ[b] = t }
		}
		END { for (b in best) print best[b] "|" typ[b] }' "$W/ifaces" | sort > "$W/targets"

	: > "$W/scan.all"
	: > "$W/scan.res"
	while IFS='|' read -r ifname typ ; do
		# erste Runde: die Art finden, die geht; weitere Runden mit derselben
		opts=-
		if dh_scan_one "$ifname" passive ; then opts=passive
		elif sleep 3 && dh_scan_one "$ifname" passive ; then opts=passive
		elif [ "$typ" = AP ] && dh_scan_one "$ifname" ap-force passive ; then opts='ap-force passive'
		elif dh_scan_one "$ifname" ; then opts=
		elif [ "$typ" = AP ] && dh_scan_one "$ifname" ap-force ; then opts=ap-force
		fi
		cp "$W/scan.one" "$W/scan.acc"
		if [ "$opts" != - ] ; then
			round=1
			while [ "$round" -lt "$DH_SCAN_ROUNDS" ] ; do
				round=$((round + 1))
				sleep 1
				# shellcheck disable=SC2086
				dh_scan_one "$ifname" $opts && cat "$W/scan.one" >> "$W/scan.acc"
			done
		fi
		mv "$W/scan.acc" "$W/scan.one"
		ok=0
		head -n 1 "$W/scan.one" | grep -q '^BSS' && ok=1
		count="$(sed -n 's/^BSS \([0-9a-f:]\{17\}\).*/\1/p' "$W/scan.one" | sort -u | wc -l)"
		count=$((count + 0))
		echo "$ifname $ok $count" >> "$W/scan.res"
		cat "$W/scan.one" >> "$W/scan.all"
	done < "$W/targets"
}

# dh_scan_list <verzeichnis>: aus scan.all je BSS eine Zeile, DH_US-getrennt:
#     bssid freq signal ssid mesh_id
# ohne eigene Interfaces, ohne Eintraege ohne Pegel; je BSSID eine Zeile mit
# dem staerksten Pegel (bis 0.15 blieben doppelte stehen). Ausgabe nach
# <verzeichnis>/scan.list
dh_scan_list() {
	awk -v US="$DH_US" -v ownl="$(tr '\n' ' ' < "$1/own")" '
		BEGIN { n = split(ownl, o, " "); for (i = 1; i <= n; i++) own[o[i]] = 1 }
		function rnd(x,   y, i) { y = x + 0.5; i = int(y); if (i > y) i--; return i }
		# eine Zeile je BSSID (mehrere Scan-Runden, zwei Interfaces), der
		# staerkste Pegel gewinnt, Reihenfolge des ersten Auftretens
		function flush() {
			if (b == "" || s == "" || (b in own)) return
			if (!(b in line)) ord[++n2] = b
			else if (sig[b] >= s) return
			sig[b] = s; line[b] = b US f US s US ssid US mesh
		}
		/^BSS[ \t]/ {
			flush()
			b = tolower($0); sub(/^bss[ \t]+/, "", b); b = substr(b, 1, 17)
			if (b !~ /^[0-9a-f][0-9a-f](:[0-9a-f][0-9a-f])(:[0-9a-f][0-9a-f])(:[0-9a-f][0-9a-f])(:[0-9a-f][0-9a-f])(:[0-9a-f][0-9a-f])$/) b = ""
			f = ""; s = ""; ssid = ""; mesh = ""
			next
		}
		b == "" { next }
		/^\tfreq:/ { v = $0; sub(/^\tfreq:[ \t]*/, "", v); if (v ~ /^[0-9.]+/) f = rnd(v + 0) }
		/^\tsignal:/ { v = $0; sub(/^\tsignal:[ \t]*/, "", v); if (v ~ /^-?[0-9.]+[ \t]*dBm/) s = rnd(v + 0) }
		/^\tSSID:/ { v = $0; sub(/^\tSSID: ?/, "", v); ssid = v }
		/^\tMESH ID:/ { v = $0; sub(/^\tMESH ID: ?/, "", v); mesh = v }
		END { flush(); for (i = 1; i <= n2; i++) print line[ord[i]] }' "$1/scan.all" > "$1/scan.list"
}

# --- Domains und Gateways ------------------------------------------------------

# Domain mit Ortung (neanderfunk_domainhelper.locator.urls, also 25_hvb)?
dh_is_hvb() {
	[ -n "$(jsonfilter -i "/lib/gluon/domains/$1.json" -e '@.neanderfunk_domainhelper.locator.urls[0]' 2>/dev/null)" ]
}

# Domainnummer: Ziffern vor dem Unterstrich (18_nefuk -> 18), sonst nichts
dh_dom_nn() {
	case "$1" in
		[0-9][0-9]_*) echo "${1%%_*}" ;;
	esac
}

# Domain dieser Firmware zur Nummer, nur wenn eindeutig
dh_dom_by_nn() {
	local f n=0 d=
	for f in /lib/gluon/domains/"$1"_*.json ; do
		[ -f "$f" ] || continue
		n=$((n + 1))
		d="${f##*/}"
		d="${d%.json}"
	done
	[ "$n" = 1 ] && echo "$d"
}

# Eigenes VPN: ein batman-Nachbar auf mesh-vpn
dh_has_vpn() {
	[ "$(batctl n -H 2>/dev/null | awk '$1 == "mesh-vpn"' | wc -l)" -gt 0 ]
}

# dh_gw_list <ausgabedatei>: je Gateway aus batctl gwl eine Zeile
#     <gateway-mac> <schnittstelle> <domainnummer|->
# Die Domainnummer steht im Originator der Supernodes:
# 02:ca:ff:ee:<NN>:<SS>, NN = Domainnummer, dezimal als Hexbyte geschrieben.
dh_gw_list() {
	batctl gwl -H 2>/dev/null | awk '
		{
			s = $0; sub(/^[ \t]*\*?[ \t]*/, "", s)
			split(s, f, /[ \t]+/); m = tolower(f[1])
			if (m !~ /^[0-9a-f][0-9a-f](:[0-9a-f][0-9a-f])(:[0-9a-f][0-9a-f])(:[0-9a-f][0-9a-f])(:[0-9a-f][0-9a-f])(:[0-9a-f][0-9a-f])$/) next
			i = "-"
			if (match(s, /\[[ \t]*[^] \t]+[ \t]*\]/)) { i = substr(s, RSTART + 1, RLENGTH - 2); gsub(/[ \t]/, "", i) }
			nn = "-"
			if (substr(m, 1, 12) == "02:ca:ff:ee:" && substr(m, 13, 2) ~ /^[0-9][0-9]$/) nn = substr(m, 13, 2)
			print m, i, nn
		}' > "$1"
}

# Kabel-Schnittstellen des Mesh (gluon_mesh, nicht WLAN, nicht VPN), je Zeile eine
dh_wired_mesh_devs() {
	ubus call network.interface dump 2>/dev/null |
		jsonfilter -e "@.interface[@.proto='gluon_mesh' && @.up=true].device" 2>/dev/null |
		grep -v -E '^(mesh[0-9]+|mesh-vpn)$' | sort -u
}

# dh_respondd <device> <nodeinfo|statistics> <ausgabedatei>: Antworten der
# Nachbarn an diesem Kabel, je Zeile ein JSON. Geht auch, wenn batman dort
# getrennt ist: Die Trennung verwirft nur batman-Frames (0x4305) oder nimmt
# nur die batman-Schnittstelle vom Geraet, IPv6 bleibt.
dh_respondd() {
	gluon-neighbour-info -i "$1" -d ff02::2:1001 -p 1001 -t 3 -r "$2" > "$3" 2>/dev/null
}

# dh_gw_domain <originator>: Gegenprobe "Wer ist dieses Gateway?"
# (docs/entwurf-automesh.md, Abschnitt 4, #3). Aus batctl tg die Clients
# dieses Originators (die bat-Schnittstellen der Supernodes,
# f2:be:ef:00:<NN>:<SS>), je eine link-local-Adresse daraus (EUI-64) per
# respondd fragen. Gueltig nur, wenn der Originator in den Mesh-Interfaces
# der Antwort steht. Ausgabe: die Domain, sonst nichts (unbekannt).
dh_gw_domain() {
	local orig m b1 ll line n=0 q="/tmp/$DH_TAG.gwq.$$"
	orig="$(echo "$1" | tr 'A-F' 'a-f')"
	dh_is_mac "$orig" || return 1
	for m in $(batctl tg -H 2>/dev/null | tr 'A-F' 'a-f' | awk -v g="$orig" '
			{ s = $0; sub(/^[ \t]*\*?[ \t]*/, "", s); split(s, f, /[ \t]+/); c = f[1] }
			index($0, g) && c != g && c !~ /^(33:33|01:00:5e):/ { print c }' | sort -u) ; do
		dh_is_mac "$m" || continue
		n=$((n + 1))
		[ "$n" -le 3 ] || break
		b1="${m%%:*}"
		set -- $(echo "${m#*:}" | tr ':' ' ')
		ll="fe80::$(printf '%x' $((0x$b1 ^ 2)))$1:$2ff:fe$3:$4$5"
		gluon-neighbour-info -i br-client -d "$ll" -p 1001 -t 3 -r nodeinfo > "$q" 2>/dev/null
		line="$(head -n 1 "$q")"
		rm -f "$q"
		[ -n "$line" ] || continue
		echo "$line" | tr 'A-F' 'a-f' | grep -qF "\"$orig\"" || continue
		NI_DC= ; NI_SC=
		eval "$(jsonfilter -s "$line" -e 'NI_DC=@.system.domain_code' -e 'NI_SC=@.system.site_code' 2>/dev/null)"
		dh_domain_of "$NI_DC" "$NI_SC"
		return 0
	done
	return 1
}

# dh_last_switch <von> <nach> <wie>: Domainwechsel vermerken, im Flash
# (sysconfig, uebersteht Neustart und sysupgrade). respondd meldet ihn als
# statistics.neanderfunk.domainhelper.last_switch, nodestatus zeigt ihn.
dh_last_switch() {
	printf '%s %s %s %s\n' "$1" "$2" "$3" "$(date +%s)" > /lib/gluon/core/sysconfig/neanderfunk_domainhelper_last_switch
}

# Alle Laufzeit-Deltas verwerfen (Offline-SSID, ap-timer, Blackout), vor
# einem Domainwechsel: 001-reset-uci (gluon-reconfigure) und
# gluon-switch-domain committen pauschal. Der Neustart verwirft sie ohnehin.
dh_revert_all() {
	local p
	for p in $(uci changes 2>/dev/null | sed -n 's/^-\{0,1\}\([^.]*\)\..*/\1/p' | sort -u) ; do
		uci revert "$p"
	done
}

# Beim naechsten Domainwechsel nach <domain> die WLAN-Kanaele behalten,
# soweit preserve_channels gesetzt ist (neanderfunk-preserve-wifichannel
# setzt sonst einmal die Kanaele der neuen Domain). Fuer Wechsel ueber das
# LAN-Mesh (adorfer 22.11.).
dh_keep_channels_on_switch() {
	local sc
	sc="$(jsonfilter -i /lib/gluon/site.json -e '@.site_code' 2>/dev/null)"
	[ -n "$sc" ] || return 1
	printf '%s\n' "$sc/$1" > /lib/gluon/core/sysconfig/neanderfunk_preserve_wifichannel_keep
}

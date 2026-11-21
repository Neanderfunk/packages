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
# Statusseite). Die Domain steht in system.domain_code; aeltere
# Single-Domain-Images haben das Feld nicht, dann der Teil des site_code
# hinter dem Bindestrich (nef-21_dias, bgl-43_bggl).
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
					if [ -z "$NI_DC" ] ; then
						case "$NI_SC" in
							?*-?*) NI_DC="${NI_SC#*-}" ;;
						esac
					fi
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

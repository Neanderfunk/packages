#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
#
# Unterbefehl "follow" von neanderfunk-domainhelper, wird von
# /usr/sbin/neanderfunk-domainhelper gesourct. Alle 91 s aus bridge-loop.sh.
#
# Knoten ohne eigenes VPN folgen der Domain, aus der ihr Netz kommt
# (docs/entwurf-automesh.md #9, docs/matrix-domainwechsel.md). Ohne VXLAN
# verschmelzen die batman-Wolken am Kabel; ein Knoten ohne VPN nutzt dann
# Gateways und Praefix der anderen Domain und bleibt selbst in seiner
# (Mischbetrieb). Zwei Regeln, beide nur ohne eigenes VPN, beide erst nach
# FO_WAIT (60 min, adorfer 22.11.) am Stueck:
#
#   R1 Kabel: Ein Nachbar am Kabel steht in einer fremden Domain D und hat
#      dort ein eigenes VPN (in seinen respondd-Statistiken ist das Gateway
#      sein eigener Nexthop), und ein Gateway der eigenen Domain kommt
#      hoechstens ueber WLAN. Dann nach D, auch wenn ueber WLAN ein eigenes
#      Gateway da ist: LAN-Mesh schlaegt WLAN-Mesh (adorfer 22.11.). Der
#      Nachbar mit VPN trennt das Kabel per bridge sofort; abgefragt wird
#      trotzdem, respondd laeuft ueber IPv6 und die Trennung verwirft nur
#      batman. Nach unserem Wechsel hebt er die Trennung wieder auf.
#   R2 nur fremde Gateways: In batctl gwl stehen nur Gateways einer fremden
#      Domain D (Originator 02:ca:ff:ee:<NN>:..). Fuer Knoten, die nur per
#      WLAN hinter einem R1-Knoten haengen.
#
# Wechsel: alle Laufzeit-Deltas verwerfen, Marke fuer
# neanderfunk-preserve-wifichannel (WLAN-Kanaele bleiben, soweit
# preserve_channels gesetzt ist), gluon-switch-domain <D> mit Neustart.
#
# Nichts tut follow
#   - in einer Domain mit Ortung (25_hvb): dort schaltet locate (lan_switch);
#   - mit eigenem VPN;
#   - wenn ein Gateway der eigenen Domain ueber ein Kabel kommt (LAN gegen
#     LAN);
#   - in eine Domain mit Ortung, in eine Domain, die nicht in dieser
#     Firmware steht, oder wenn mehrere fremde Domains in Frage kommen;
#   - "Fall 3": Nachbar am Kabel in fremder Domain ohne eigenes VPN, und
#     wir sehen ein eigenes Gateway. Beide Seiten sind versorgt, das wird
#     nur gemeldet (adorfer 22.11.).
#
# Der Zeitpunkt, seit dem die Lage gilt, bleibt stehen, wenn zwischendurch
# gar kein Gateway zu sehen ist (etwa weil der R1-Knoten vor uns gewechselt
# hat und neu startet). Ist er aelter als FO_WAIT, wechselt island Fall b
# ohne seine lange Wartezeit in genau diese Domain. Zurueckgesetzt wird er
# nur durch ein eigenes Gateway, eigenes VPN oder eine andere Zieldomain.
#
# Abschalten: uci neanderfunk-domainhelper.follow.enabled=0.
# -n: Wartezeit uebergehen, nur zeigen, was passieren wuerde.

FO_DIR=/tmp/neanderfunk-domainhelper.follow
FO_BANNER=/tmp/neanderfunk-domainhelper.banner.follow
FO_WAIT=3600

dry=0
case "$1" in
	-n) dry=1 ;;
	'') ;;
	*) echo 'usage: domainhelper follow [-n]' >&2 ; exit 2 ;;
esac

[ "$(uci -q get gluon-setup-mode.@setup_mode[0].configured)" = 1 ] || exit 0
case "$(uci -q get neanderfunk-domainhelper.follow.enabled)" in
	0|false|no|off|disabled) [ "$dry" = 1 ] || exit 0 ;;
esac

mkdir -p "$FO_DIR" || exit 1

fo_say() {
	if [ "$dry" = 1 ] ; then echo "$*" ; else dh_log "$*" ; fi
}

# fo_clear <grund>: Lage aufgeloest
fo_clear() {
	if [ "$dry" = 1 ] ; then
		echo "nichts zu tun: $1"
		return 0
	fi
	if [ -r "$FO_DIR/state" ] ; then
		dh_log "follow: aufgehoben ($1)"
		rm -f "$FO_DIR/state"
	fi
	rm -f "$FO_BANNER"
}

# fo_note <schluessel> <text>: einmal melden, solange die Lage gleich bleibt
fo_note() {
	if [ "$dry" = 1 ] ; then
		echo "$2"
		return 0
	fi
	[ "$(cat "$FO_DIR/note" 2>/dev/null)" = "$1" ] && return 0
	echo "$1" > "$FO_DIR/note"
	dh_log "follow: $2"
}

now="$(dh_uptime)"
own_id="$(dh_own_id)"
own_domain="$(uci -q get gluon.core.domain)"
own_nn="$(dh_dom_nn "$own_domain")"

if dh_is_hvb "$own_domain" ; then
	[ "$dry" = 1 ] && echo "Domain mit Ortung ($own_domain): locate schaltet um"
	exit 0
fi
if dh_has_vpn ; then
	fo_clear 'eigenes VPN'
	exit 0
fi

# Gateways nach Domain
dh_gw_list "$FO_DIR/gw"
own_gw=0 own_gw_lan=0
if [ -n "$own_nn" ] ; then
	own_gw="$(awk -v n="$own_nn" '$3 == n' "$FO_DIR/gw" | wc -l)"
	own_gw_lan="$(awk -v n="$own_nn" '$3 == n && $2 !~ /^mesh[0-9]+$/' "$FO_DIR/gw" | wc -l)"
fi
if [ "$dry" = 1 ] ; then
	echo "eigene Domain $own_domain (Nummer ${own_nn:--}), kein eigenes VPN"
	echo 'Gateways (mac schnittstelle domainnummer):'
	sed 's/^/  /' "$FO_DIR/gw"
fi

# Ziel pruefen: in dieser Firmware, nicht die eigene, keine Ortung
fo_ok_target() {
	case "$1" in
		''|*[!A-Za-z0-9_-]*) return 1 ;;
	esac
	[ "$1" != "$own_domain" ] && [ -f "/lib/gluon/domains/$1.json" ] && ! dh_is_hvb "$1"
}

# --- R1: Nachbarn am Kabel, auch hinter einer Trennung -----------------------------
#
# fo_cable <datei>: je fremdem Nachbarn am Kabel "<domain> <vpn 0|1> <node_id> <device>"
fo_cable() {
	local dev line
	: > "$1"
	for dev in $(dh_wired_mesh_devs) ; do
		dh_respondd "$dev" nodeinfo "$FO_DIR/ni"
		dh_respondd "$dev" statistics "$FO_DIR/st"
		while read -r line ; do
			NI_ID= ; NI_DC= ; NI_SC=
			eval "$(jsonfilter -s "$line" -e 'NI_ID=@.node_id' \
				-e 'NI_DC=@.system.domain_code' -e 'NI_SC=@.system.site_code' 2>/dev/null)"
			NI_ID="$(echo "$NI_ID" | tr 'A-F' 'a-f')"
			[ -n "$NI_ID" ] && [ "$NI_ID" != "$own_id" ] || continue
			NI_DC="$(dh_domain_of "$NI_DC" "$NI_SC")"
			[ -n "$NI_DC" ] && [ "$NI_DC" != "$own_domain" ] || continue
			vpn=0
			while read -r sl ; do
				ST_ID= ; ST_GW= ; ST_NH=
				eval "$(jsonfilter -s "$sl" -e 'ST_ID=@.node_id' -e 'ST_GW=@.gateway' \
					-e 'ST_NH=@.gateway_nexthop' 2>/dev/null)"
				[ "$(echo "$ST_ID" | tr 'A-F' 'a-f')" = "$NI_ID" ] || continue
				[ -n "$ST_GW" ] && [ "$(echo "$ST_GW" | tr 'A-F' 'a-f')" = "$(echo "$ST_NH" | tr 'A-F' 'a-f')" ] && vpn=1
			done < "$FO_DIR/st"
			echo "$NI_DC $vpn $NI_ID $dev" >> "$1"
		done < "$FO_DIR/ni"
	done
	# busybox sort kennt kein -o
	sort -u "$1" > "$1.s" && mv "$1.s" "$1"
}

cand= rule= why=
fo_cable "$FO_DIR/cable"
if [ "$dry" = 1 ] ; then
	echo 'fremde Nachbarn am Kabel (domain vpn node_id device):'
	sed 's/^/  /' "$FO_DIR/cable"
fi
if [ "$own_gw_lan" -gt 0 ] ; then
	why="eigenes Gateway ueber ein Kabel"
else
	r1="$(awk '$2 == 1 { print $1 }' "$FO_DIR/cable" | sort -u)"
	if [ -n "$r1" ] ; then
		if [ "$(echo "$r1" | wc -l)" -gt 1 ] ; then
			why="mehrere fremde Domains mit VPN am Kabel: $(echo $r1)"
		elif fo_ok_target "$r1" ; then
			cand="$r1" rule=R1
		else
			why="Nachbar mit VPN in $r1, kein Ziel (Ortung oder nicht in dieser Firmware)"
		fi
	fi
fi

# --- R2: nur Gateways einer fremden Domain ------------------------------------------

if [ -z "$cand" ] && [ -z "$why" ] && [ -s "$FO_DIR/gw" ] && [ "$own_gw" -eq 0 ] ; then
	nns="$(awk '{ print $3 }' "$FO_DIR/gw" | sort -u)"
	if [ "$(echo "$nns" | wc -l)" -gt 1 ] || [ "$nns" = - ] ; then
		why="Gateways mehrerer oder unbekannter Domains: $(echo $nns)"
	else
		d="$(dh_dom_by_nn "$nns")"
		if fo_ok_target "$d" ; then
			cand="$d" rule=R2
		else
			why="nur Gateways der Domainnummer $nns, kein Ziel"
		fi
	fi
fi

# --- Entscheiden --------------------------------------------------------------------

if [ -z "$cand" ] ; then
	# Fall 3: beide Seiten versorgt, nur melden
	f3="$(awk '$2 == 0 { print $1 }' "$FO_DIR/cable" | sort -u | tr '\n' ' ')"
	if [ "$own_gw" -gt 0 ] && [ -n "$f3" ] ; then
		fo_note "f3 $f3" "Domain-Bruecke am Kabel zu ${f3% } ohne VPN auf beiden Seiten, beide versorgt: kein Eingriff"
	fi
	if [ "$own_gw" -gt 0 ] ; then
		fo_clear "${why:-Gateway der eigenen Domain}"
	elif [ -n "$why" ] ; then
		[ "$dry" = 1 ] && echo "nichts zu tun: $why"
	else
		[ "$dry" = 1 ] && echo 'nichts zu tun: kein Gateway (dafuer ist island zustaendig)'
	fi
	exit 0
fi

s_dom= s_since=0 s_rule=
[ -r "$FO_DIR/state" ] && read -r s_dom s_since s_rule s_wait < "$FO_DIR/state"
if [ "$s_dom" != "$cand" ] ; then
	s_since="$now"
	if [ "$dry" = 0 ] ; then
		echo "$cand $now $rule $FO_WAIT" > "$FO_DIR/state"
		dh_log "follow: $rule, Netz kommt aus $cand, eigene Domain $own_domain; Wechsel nach $((FO_WAIT / 60)) min"
		echo "yellow|Netz kommt aus Domain $cand ($rule), Wechsel nach $((FO_WAIT / 60)) min" > "$FO_BANNER"
	fi
elif [ "$s_rule" != "$rule" ] && [ "$dry" = 0 ] ; then
	echo "$cand $s_since $rule $FO_WAIT" > "$FO_DIR/state"
fi
age=$((now - s_since))

if [ "$dry" = 1 ] ; then
	echo "wuerde nach $cand wechseln ($rule, seit $age s, ab $FO_WAIT s): Laufzeit-Deltas verwerfen, Kanaele behalten, gluon-switch-domain $cand"
	exit 0
fi
[ "$age" -ge "$FO_WAIT" ] || exit 0

# Direkt vorher noch einmal frisch: Bei R1 muss der Nachbar mit VPN noch da
# sein, sonst verschoebe sich der Knoten selbst auf eine Insel.
if [ "$rule" = R1 ] ; then
	fo_cable "$FO_DIR/cable2"
	if ! awk -v d="$cand" '$1 == d && $2 == 1 { f = 1 } END { exit !f }' "$FO_DIR/cable2" ; then
		dh_log "follow: Nachbar mit VPN in $cand bei der Nachfrage nicht mehr da, kein Wechsel"
		exit 0
	fi
fi
# Bei R2 entscheidet sonst allein das MAC-Schema. Gegenprobe (#3): Der
# Supernode hinter dem gewaehlten Gateway nennt per respondd seine Domain.
# Keine oder eine andere Antwort: kein Wechsel, unbekannt loest nie aus.
if [ "$rule" = R2 ] ; then
	sel="$(batctl gwl -H 2>/dev/null | awk '/^[ \t]*\*/ { sub(/^[ \t]*\*[ \t]*/, ""); print tolower($1) ; exit }')"
	gd="$(dh_gw_domain "$sel")"
	if [ "$gd" != "$cand" ] ; then
		fo_note "gp $sel $gd" "Gegenprobe: Gateway $sel nennt ${gd:-keine Domain}, nicht $cand: kein Wechsel"
		exit 0
	fi
fi

dh_log "follow: $rule seit $((age / 60)) min, wechsle Domain $own_domain -> $cand, Kanaele bleiben"
dh_revert_all
dh_last_switch "$own_domain" "$cand" "follow-$rule"
dh_keep_channels_on_switch "$cand" || dh_log "follow: Marke fuer die Kanaele nicht geschrieben"
sync
gluon-switch-domain "$cand" > "$FO_DIR/switch.out" 2>&1 || \
	dh_log "follow: gluon-switch-domain fehlgeschlagen: $(tail -n 1 "$FO_DIR/switch.out")"
exit 0

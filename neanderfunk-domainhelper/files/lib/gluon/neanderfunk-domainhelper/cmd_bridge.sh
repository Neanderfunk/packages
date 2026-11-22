#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
#
# Unterbefehl "bridge" von neanderfunk-domainhelper, wird von
# /usr/sbin/neanderfunk-domainhelper gesourct. Alle 91 s aus bridge-loop.sh
# (procd-Dienst, Teil von /etc/init.d/neanderfunk-domainhelper).
#
# Domain-Bruecken erkennen und trennen (docs/entwurf-automesh.md, Fall A).
# Wir fahren mesh.vxlan = false: Steckt am LAN-Mesh ein Knoten einer anderen
# Domain, verschmelzen beide batman-Wolken sofort.
#
# Ablauf:
#   1. LAN-Mesh-Nachbarn (batman-Interfaces ausser mesh-vpn und meshN) per
#      respondd nach ihrer Domain fragen (lib.sh, dh_lan_mesh). Neue
#      Nachbarn sofort, bekannte alle BR_CACHE_AGE Sekunden.
#   2. Ein Nachbar ist fremd nur auf positiven Beleg: Er nennt eine Domain,
#      die in dieser Firmware steht und nicht die eigene ist (_EOL der
#      Sackgasse zaehlt nicht). Unbekannte Codes loesen nichts aus.
#   3. Bruecke gesehen: melden (Syslog, Banner, Statusdatei), bis zum
#      naechsten Lauf warten (BR_FRIST, ein Durchgang der Schleife).
#   4. Dann frisch nachfragen und trennen, wenn ALLES zutrifft:
#      - Trennen nicht abgeschaltet (uci neanderfunk-domainhelper.bridge.cut);
#      - eigenes VPN (batman-Nachbar auf mesh-vpn): Wir behalten unseren
#        Uplink;
#      - die Gegenseite hat einen eigenen Uplink: Der fremde Nachbar erreicht
#        sein Gateway direkt (gateway_nexthop = gateway, nur ueber einen
#        eigenen Tunnel moeglich), oder in batctl gwl steht ein Gateway
#        seiner Domain (Originator 02:ca:ff:ee:<NN>:..). Sonst schnitte das
#        Trennen die Gegenseite vom Netz ab.
#      - Ohne Bridge (swconfig wie Archer C7 oder TL-WR1043ND: alle
#        LAN-Ports sind ein Geraet, der Switch leitet in Hardware weiter,
#        keine Port-Isolation) zusaetzlich: BR_FRIST_SW (2 min) laenger
#        warten, damit eine Gegenseite mit DSA zuerst ihren Port trennen
#        kann, und nur trennen, wenn am LAN kein Nachbar der eigenen Domain
#        haengt. Sonst nur melden (mit Switch-Port aus arl_table, wo der
#        Switch ihn kennt): Trennen kappte nur unsere eigenen Links, die
#        fremden Knoten blieben ueber unseren Switch mit den eigenen
#        verbunden (adorfer 22.11.).
#      Getrennt wird nur zur Laufzeit, kein uci commit. Wieder verbunden
#      wird nur, wenn der getrennte Nachbar inzwischen selbst in unserer
#      Domain steht (er ist per follow herueber gewechselt, adorfer 22.11.),
#      sonst bleibt es getrennt bis zum naechsten Neustart: kein erneutes
#      Zusammenwachsen zweier Domains. Faellt danach ein VPN weg und die
#      Wolke steht ohne Gateway da, startet ein Waechter (linkcheck
#      no_gateway) den Knoten neu, dann beginnt die Pruefung von vorn:
#      - Ist der Hardif eine Bridge (br-mesh_other, br-wan bei Mesh-on-WAN,
#        mit DSA je Port ein Geraet): ebtables verwirft batman-Frames
#        (0x4305) an genau dem Port, hinter dem der fremde Nachbar steht
#        (aus der Weiterleitungstabelle der Bridge), fuer uns und fuer die
#        Weiterleitung zu den anderen Ports. Nachbarn der eigenen Domain an
#        anderen Ports bleiben dran. Ist der Port nicht zu finden, wie
#        frueher die ganze Bridge fuer uns. Die Nachbarn fallen nach etwa
#        200 s aus batctl n.
#      - Sonst (ein einzelnes Geraet wie eth1.1): "ifdown" nur auf der
#        batman-Schnittstelle (mesh_other_mesh, proto gluon_mesh). Das
#        Geraet und seine link-local-Adresse bleiben, wir koennen den
#        Nachbarn weiter per respondd fragen (der eigene respondd hoert dort
#        dann nicht mehr). Wieder verbunden wird mit "ifup" auf dem
#        gluon_wired-Interface (mesh_other), das die Schnittstelle neu
#        anlegt.
#      Solange getrennt, prueft jeder Lauf, ob die Trennung noch greift
#      (ein Neuladen der Firewall loescht die Regeln), und setzt sie neu;
#      alle BR_LIFT_EVERY Sekunden fragt er den getrennten Nachbarn nach
#      seiner Domain.
#
# Nur zum Testen: uci set neanderfunk-domainhelper.bridge.test_domain=<d>
# (ohne commit) laesst bridge so tun, als stuende der Knoten in <d>. So
# laesst sich das Trennen gegen Nachbarn der eigenen Domain pruefen, ohne
# eine fremde Domain anzuschliessen.
#
# In einer Domain mit Ortung (neanderfunk_domainhelper.locator.urls, also
# 25_hvb) trennt bridge nicht, sondern startet einmal locate: Das meldet und
# schaltet selbst in die Domain des Nachbarn um.
#
# Ohne eigenes VPN trennt bridge nie; ob ein solcher Knoten selbst die Domain
# wechselt, ist ein eigener Schritt (Entwurf, Abschnitt 0).

BR_DIR=/tmp/neanderfunk-domainhelper.bridge
BR_BANNER=/tmp/neanderfunk-domainhelper.banner
# Ein Durchgang der Schleife (91 s) minus Spiel: erkannt in einem Lauf,
# getrennt im naechsten
BR_FRIST=80
# ohne Bridge (swconfig) 2 min laenger: eine Gegenseite mit DSA trennt zuerst
BR_FRIST_SW=200
BR_CACHE_AGE=900
BR_REEVAL=600
BR_LIFT_EVERY=270

dry=0
case "$1" in
	-n) dry=1 ;;
	'') ;;
	*) echo 'usage: neanderfunk-domainhelper bridge [-n]' >&2 ; exit 2 ;;
esac

[ "$(uci -q get gluon-setup-mode.@setup_mode[0].configured)" = 1 ] || exit 0

mkdir -p "$BR_DIR" || exit 1
if [ "$dry" = 0 ] ; then
	if [ -n "$(find "$BR_DIR/lock" -maxdepth 0 -mmin +10 2>/dev/null)" ] ; then
		rmdir "$BR_DIR/lock" 2>/dev/null
	fi
	mkdir "$BR_DIR/lock" 2>/dev/null || exit 0
	trap 'rmdir "$BR_DIR/lock" 2>/dev/null' EXIT
fi

now="$(dh_uptime)"
own_id="$(dh_own_id)"
own_domain="$(uci -q get gluon.core.domain)"
test_domain="$(uci -q get neanderfunk-domainhelper.bridge.test_domain)"
case "$test_domain" in
	''|*[!A-Za-z0-9_-]*) test_domain= ;;
	*) own_domain="$test_domain" ;;
esac

# Zustand: <zustand> <iface> <seit> <domain> <nachbar> <geprueft> <grund>
#   idle | bridge (gesehen, nicht getrennt) | cut (<iface> = eb:<bridge>
#   bei ebtables, if:<interface> bei ifdown)
state=idle s_if= s_since=0 s_dom= s_node= s_eval=0 s_note=
[ -r "$BR_DIR/state" ] && read -r state s_if s_since s_dom s_node s_eval s_note < "$BR_DIR/state"

br_say() {
	if [ "$dry" = 1 ] ; then echo "$*" ; else dh_log "$*" ; fi
}

br_save() {
	[ "$dry" = 1 ] && return 0
	echo "$*" > "$BR_DIR/state.new" && mv "$BR_DIR/state.new" "$BR_DIR/state"
}

# br_banner "<yellow|red>|<text>" oder leer: Zeile fuer nodestatus
br_banner() {
	[ "$dry" = 1 ] && return 0
	if [ -n "$1" ] ; then
		echo "$1" > "$BR_BANNER"
	else
		rm -f "$BR_BANNER"
	fi
}

br_idle() {
	if [ "$state" != idle ] ; then
		br_say "Domain-Bruecke weg${1:+ ($1)}"
	fi
	br_save idle
	br_banner ''
}

br_cut_enabled() {
	case "$(uci -q get neanderfunk-domainhelper.bridge.cut)" in
		0|false|no|off|disabled) return 1 ;;
	esac
	return 0
}

# Erster fremder Nachbar aus einer dh_lan_mesh-Datei: "<iface> <node_id> <domain> <mac|->"
br_foreign() {
	local i id d m
	awk -F "$DH_US" '$2 != "" && $3 != "" { d = $3; sub(/_EOL$/, "", d); print $1, $2, d, ($4 == "" ? "-" : $4) }' "$1" |
	while read -r i id d m ; do
		[ "$d" = "$own_domain" ] && continue
		case "$d" in
			*[!A-Za-z0-9_-]*) continue ;;
		esac
		[ -f "/lib/gluon/domains/$d.json" ] || continue
		# Nachbar in einer Domain mit Ortung (25_hvb): Der schaltet per
		# lan_switch selbst zu uns um; Trennen hielte ihn danach bis zum
		# Neustart ab.
		dh_is_hvb "$d" && continue
		echo "$i $id $d $m"
		break
	done
}

# Alle fremden Nachbarn an <iface> aus einer dh_lan_mesh-Datei, je Zeile eine node_id
br_foreign_ids() {
	local i id d
	awk -F "$DH_US" -v w="$2" '$1 == w && $2 != "" && $3 != "" { d = $3; sub(/_EOL$/, "", d); print $1, $2, d }' "$1" |
	while read -r i id d ; do
		[ "$d" = "$own_domain" ] && continue
		case "$d" in
			*[!A-Za-z0-9_-]*) continue ;;
		esac
		[ -f "/lib/gluon/domains/$d.json" ] && echo "$id"
	done
}

# Hat die Gegenseite hinter <iface> einen eigenen Uplink? (<iface> <datei> <domain>)
# Nach dem Trennen bleiben die Knoten dort ueber die Ports untereinander
# verbunden; es reicht also, wenn einer von ihnen einen eigenen Uplink hat.
br_far_uplink() {
	local line ids nn
	# Ein Gateway ihrer Domain (02:ca:ff:ee:<NN>:..)
	nn="$(dh_dom_nn "$3")"
	if [ -n "$nn" ] ; then
		dh_gw_list "$BR_DIR/gw"
		awk -v n="$nn" '$3 == n { f = 1 } END { exit !f }' "$BR_DIR/gw" && return 0
	fi
	# Ein fremder Nachbar erreicht sein Gateway direkt, also ueber eigenen Tunnel
	ids="$(br_foreign_ids "$2" "$1")"
	[ -n "$ids" ] || return 1
	gluon-neighbour-info -i "$1" -d ff02::2:1001 -p 1001 -t 5 \
		-r statistics > "$BR_DIR/stats" 2>/dev/null
	while read -r line ; do
		ST_ID= ; ST_GW= ; ST_NH=
		eval "$(jsonfilter -s "$line" -e 'ST_ID=@.node_id' -e 'ST_GW=@.gateway' \
			-e 'ST_NH=@.gateway_nexthop' 2>/dev/null)"
		ST_ID="$(echo "$ST_ID" | tr 'A-F' 'a-f')"
		echo "$ids" | grep -qxF "$ST_ID" || continue
		[ -n "$ST_GW" ] || continue
		[ "$(echo "$ST_GW" | tr 'A-F' 'a-f')" = "$(echo "$ST_NH" | tr 'A-F' 'a-f')" ] && return 0
	done < "$BR_DIR/stats"
	return 1
}

# Trennen und Freigeben: <ziel> ist eb:<bridge> oder if:<interface>
br_rules() {
	# $1 = -I oder -D, $2 = Bridge
	ebtables-tiny "$1" INPUT -p 0x4305 --logical-in "$2" -j DROP 2>/dev/null
	ebtables-tiny "$1" OUTPUT -p 0x4305 --logical-out "$2" -j DROP 2>/dev/null
}

br_rules_present() {
	ebtables-tiny -L INPUT 2>/dev/null | grep -q -- "-p 0x4305 --logical-in $1 -j DROP" &&
	ebtables-tiny -L OUTPUT 2>/dev/null | grep -q -- "-p 0x4305 --logical-out $1 -j DROP"
}

# Nur ein Port einer Bridge: $1 = -I oder -D, $2 = Port
br_port_rules() {
	ebtables-tiny "$1" INPUT -p 0x4305 -i "$2" -j DROP 2>/dev/null
	ebtables-tiny "$1" OUTPUT -p 0x4305 -o "$2" -j DROP 2>/dev/null
	ebtables-tiny "$1" FORWARD -p 0x4305 -i "$2" -j DROP 2>/dev/null
	ebtables-tiny "$1" FORWARD -p 0x4305 -o "$2" -j DROP 2>/dev/null
}

br_port_rules_present() {
	ebtables-tiny -L INPUT 2>/dev/null | grep -q -- "-p 0x4305 -i $1 -j DROP" &&
	ebtables-tiny -L OUTPUT 2>/dev/null | grep -q -- "-p 0x4305 -o $1 -j DROP" &&
	[ "$(ebtables-tiny -L FORWARD 2>/dev/null | grep -c -E -- "-p 0x4305 -[io] $1 -j DROP")" -ge 2 ]
}

# br_fdb_port <bridge> <mac>: Port der Bridge, hinter dem <mac> steht. Aus
# "brctl showmacs" (busybox, Spalten: port no, mac, is local, ageing), sonst
# aus der Weiterleitungstabelle /sys/class/net/<bridge>/brforward (je
# Eintrag 16 Byte: mac[6], port_no, is_local, ageing[4], port_hi, pad,
# unused[2]) per hexdump; od fehlt in unseren Images.
br_fdb_port() {
	local no p
	dh_is_mac "$2" || return 1
	no="$(brctl showmacs "$1" 2>/dev/null | awk -v m="$2" 'tolower($2) == m && $3 == "no" { print $1 + 0 ; exit }')"
	if [ -z "$no" ] && command -v hexdump >/dev/null 2>&1 ; then
		no="$(hexdump -v -e '16/1 "%02x " "\n"' "/sys/class/net/$1/brforward" 2>/dev/null | awk -v m="$2" '
			function hx(s,   i, v) { v = 0; for (i = 1; i <= length(s); i++) v = v * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1; return v }
			NF >= 16 && ($1 ":" $2 ":" $3 ":" $4 ":" $5 ":" $6) == m && $8 == "00" { print hx($13) * 256 + hx($7) ; exit }')"
	fi
	[ -n "$no" ] || return 1
	for p in "/sys/class/net/$1/brif/"* ; do
		[ -r "$p/port_no" ] || continue
		[ "$(( $(cat "$p/port_no") ))" = "$no" ] && { echo "${p##*/}" ; return 0 ; }
	done
	return 1
}

# br_arl_port <mac>: Switch-Port aus arl_table (swconfig, nur manche Switches)
br_arl_port() {
	local sw
	command -v swconfig >/dev/null 2>&1 || return 1
	sw="$(swconfig list 2>/dev/null | awk '/^Found:/ { print $2 ; exit }')"
	[ -n "$sw" ] || return 1
	swconfig dev "$sw" get arl_table 2>/dev/null | awk -v m="$1" '
		tolower($0) ~ m { sub(/:.*/, ""); print ; exit }' | grep .
}

br_iface_up() {
	[ "$(ubus call "network.interface.$1" status 2>/dev/null | jsonfilter -e '@.up' 2>/dev/null)" = true ]
}

# Ziele: eb:<bridge> (ganze Bridge fuer uns), ebp:<bridge>:<port> (ein
# Port), mif:<batman-interface>:<gluon_wired-interface>:<geraet>
br_tparts() {
	local IFS=:
	set -- $1
	T_KIND="$1" T_A="$2" T_B="$3" T_C="$4"
}

br_do_cut() {
	br_tparts "$1"
	case "$T_KIND" in
		eb) br_rules_present "$T_A" || br_rules -I "$T_A" ;;
		ebp) br_port_rules_present "$T_B" || br_port_rules -I "$T_B" ;;
		mif) ifdown "$T_A" ;;
		if) ifdown "$T_A" ;;
	esac
}

br_do_lift() {
	br_tparts "$1"
	case "$T_KIND" in
		eb) br_rules -D "$T_A" ;;
		ebp) br_port_rules -D "$T_B" ;;
		mif) ifup "$T_B" ;;
		if) ifup "$T_A" ;;
	esac
}

# Greift die Trennung noch?
br_still_cut() {
	br_tparts "$1"
	case "$T_KIND" in
		eb) br_rules_present "$T_A" ;;
		ebp) br_port_rules_present "$T_B" ;;
		mif|if) ! br_iface_up "$T_A" ;;
	esac
}

# Geraet, ueber das der getrennte Nachbar per respondd zu fragen ist
br_query_dev() {
	br_tparts "$1"
	case "$T_KIND" in
		eb|ebp) echo "$T_A" ;;
		mif) echo "$T_C" ;;
	esac
}

# Domain eines Nachbarn per respondd an <geraet>: br_peer_domain <geraet> <node_id>
br_peer_domain() {
	local line
	dh_respondd "$1" nodeinfo "$BR_DIR/peer"
	while read -r line ; do
		NI_ID= ; NI_DC= ; NI_SC=
		eval "$(jsonfilter -s "$line" -e 'NI_ID=@.node_id' \
			-e 'NI_DC=@.system.domain_code' -e 'NI_SC=@.system.site_code' 2>/dev/null)"
		[ "$(echo "$NI_ID" | tr 'A-F' 'a-f')" = "$2" ] || continue
		if [ -z "$NI_DC" ] ; then
			case "$NI_SC" in
				?*-?*) NI_DC="${NI_SC#*-}" ;;
			esac
		fi
		echo "${NI_DC%_EOL}"
		return 0
	done < "$BR_DIR/peer"
	return 1
}

# Ziel zum batman-Hardif <device> und Nachbarn <mac>: ebp:<device>:<port>
# bei einer Bridge mit bekanntem Port, eb:<device> bei einer Bridge sonst,
# mif:<batman-interface>:<gluon_wired-Interface>:<device> ohne Bridge,
# sonst nichts
br_target() {
	local m p port
	if [ -d "/sys/class/net/$1/bridge" ] ; then
		if port="$(br_fdb_port "$1" "$2")" ; then
			echo "ebp:$1:$port"
		else
			echo "eb:$1"
		fi
		return 0
	fi
	m="$(ubus call network.interface dump 2>/dev/null | jsonfilter \
		-e "@.interface[@.l3_device='$1' && @.proto='gluon_mesh'].interface" 2>/dev/null | head -n 1)"
	case "$m" in
		*_mesh) p="${m%_mesh}" ;;
		*) return 0 ;;
	esac
	[ "$(ubus call "network.interface.$p" status 2>/dev/null | jsonfilter -e '@.proto' 2>/dev/null)" = gluon_wired ] || return 0
	echo "mif:$m:$p:$1"
}

# --- getrennt: bis zum Neustart halten ----------------------------------------

if [ "$state" = cut ] ; then
	# Ist der getrennte Nachbar inzwischen in unserer Domain (follow)?
	if [ "$dry" = 1 ] || [ $((now - s_eval)) -ge "$BR_LIFT_EVERY" ] ; then
		qd="$(br_query_dev "$s_if")"
		pd=
		[ -n "$qd" ] && pd="$(br_peer_domain "$qd" "$s_node")"
		if [ "$dry" = 1 ] ; then
			echo "getrennt: $s_if seit $((now - s_since)) s, Nachbar $s_node jetzt in ${pd:-?}"
			exit 0
		fi
		if [ -n "$pd" ] && [ "$pd" = "$own_domain" ] ; then
			br_do_lift "$s_if"
			br_say "Domain-Bruecke: Nachbar $s_node ist jetzt in $own_domain, Trennung $s_if aufgehoben"
			br_save idle
			br_banner ''
			exit 0
		fi
		br_save cut "$s_if" "$s_since" "$s_dom" "$s_node" "$now" "$s_note"
	fi
	if ! br_still_cut "$s_if" ; then
		br_say "Domain-Bruecke: Trennung $s_if war aufgehoben, setze sie neu"
		br_do_cut "$s_if"
	fi
	exit 0
fi

# --- LAN-Mesh-Nachbarn ----------------------------------------------------------

batctl n -H 2>/dev/null | awk '
	$1 != "mesh-vpn" && $1 !~ /^mesh[0-9]+$/ && $2 ~ /^[0-9a-fA-F][0-9a-fA-F]:/ { print $1, tolower($2) }' |
	sort -u > "$BR_DIR/macs"
if [ ! -s "$BR_DIR/macs" ] ; then
	[ "$dry" = 1 ] && echo 'keine LAN-Mesh-Nachbarn'
	br_idle 'keine LAN-Mesh-Nachbarn'
	exit 0
fi

# Domains der Nachbarn: neu fragen, wenn ein Nachbar unbekannt oder die
# letzte Abfrage zu alt ist
cache="$BR_DIR/cache"
need=0
cts=-1
[ -r "$BR_DIR/cache.ts" ] && read -r cts < "$BR_DIR/cache.ts"
if [ "$dry" = 1 ] || [ ! -r "$cache" ] || [ "$cts" -lt 0 ] || [ $((now - cts)) -ge "$BR_CACHE_AGE" ] ; then
	need=1
else
	awk -F "$DH_US" '$4 != "" { print $1, $4 }' "$cache" | sort -u > "$BR_DIR/known"
	[ -z "$(grep -vxFf "$BR_DIR/known" "$BR_DIR/macs")" ] || need=1
fi
if [ "$need" = 1 ] ; then
	[ "$dry" = 1 ] && cache="$BR_DIR/cache.dry"
	dh_lan_mesh "$own_id" "$cache.new" && mv "$cache.new" "$cache"
	[ "$dry" = 1 ] || echo "$(dh_uptime)" > "$BR_DIR/cache.ts"
fi
if [ "$dry" = 1 ] ; then
	echo 'LAN-Mesh-Nachbarn (iface node_id domain mac):'
	tr "$DH_US" ' ' < "$cache" | sed 's/^/  /'
fi

f="$(br_foreign "$cache")"
if [ -z "$f" ] ; then
	[ "$dry" = 1 ] && echo "keine Domain-Bruecke (eigene Domain $own_domain)"
	br_idle
	exit 0
fi
set -- $f
f_if="$1" f_id="$2" f_dom="$3" f_mac="$4"

# --- Bruecke gesehen ------------------------------------------------------------

if [ "$state" != bridge ] || [ "$s_if" != "$f_if" ] || [ "$s_node" != "$f_id" ] ; then
	br_say "Domain-Bruecke an $f_if: Nachbar $f_id ist in $f_dom, eigene Domain $own_domain${test_domain:+ (Test)}"
	br_save bridge "$f_if" "$now" "$f_dom" "$f_id" 0 neu
	br_banner "yellow|Domain-Bruecke an $f_if zu $f_dom (Nachbar $f_id), wird geprueft"
	[ "$dry" = 1 ] || exit 0
	s_since="$now" s_note=neu s_eval=0
fi

# Frist abwarten; ein schon bewerteter Fall wird nur alle BR_REEVAL s neu bewertet
if [ "$dry" = 0 ] ; then
	[ $((now - s_since)) -ge "$BR_FRIST" ] || exit 0
	[ "$s_note" = neu ] || [ $((now - s_eval)) -ge "$BR_REEVAL" ] || exit 0
fi

# --- Entscheiden ----------------------------------------------------------------

note=
text=
if [ -n "$(nf_site_get '@.neanderfunk_domainhelper.locator.urls[0]')" ] ; then
	note=locate
	text="Domain mit Ortung, locate schaltet um"
elif ! br_cut_enabled ; then
	note=abgeschaltet
	text="Trennen abgeschaltet (uci neanderfunk-domainhelper.bridge.cut)"
elif [ "$(batctl n -H 2>/dev/null | awk '$1 == "mesh-vpn"' | wc -l)" -eq 0 ] ; then
	note=ohne_vpn
	text="kein eigenes VPN, Trennen wuerde uns abschneiden"
else
	# Frisch nachfragen, bevor getrennt wird
	if [ "$dry" = 0 ] ; then
		dh_lan_mesh "$own_id" "$BR_DIR/cache.new" && mv "$BR_DIR/cache.new" "$BR_DIR/cache"
		echo "$(dh_uptime)" > "$BR_DIR/cache.ts"
		f="$(br_foreign "$BR_DIR/cache")"
		if [ -z "$f" ] ; then
			br_idle 'bei der Nachfrage nicht mehr fremd'
			exit 0
		fi
		set -- $f
		f_if="$1" f_id="$2" f_dom="$3" f_mac="$4"
	fi
	target="$(br_target "$f_if" "$f_mac")"
	if ! br_far_uplink "$f_if" "$cache" "$f_dom" ; then
		note=gegenseite_ohne_uplink
		text="Gegenseite ohne eigenen Uplink, Trennen wuerde sie abschneiden"
	elif [ -z "$target" ] ; then
		note=keine_schnittstelle
		text="weder Bridge noch gluon_wired-Interface zu $f_if"
	else
		case "$target" in
			mif:*)
				# Ohne Bridge (swconfig): keine Port-Isolation
				if [ "$dry" = 0 ] && [ $((now - s_since)) -lt "$BR_FRIST_SW" ] ; then
					exit 0
				fi
				if awk -F "$DH_US" -v w="$f_if" -v o="$own_domain" '$1 == w && $3 == o { f = 1 } END { exit !f }' "$cache" ; then
					note=eigene_am_lan
					port="$(br_arl_port "$f_mac")"
					text="ohne Port-Isolation, am selben LAN auch Nachbarn der eigenen Domain${port:+ (fremder Nachbar an Switch-$port)}"
				fi
				;;
		esac
	fi
fi

if [ "$note" = locate ] ; then
	if [ "$s_note" != locate ] ; then
		br_say "Domain-Bruecke an $f_if zu $f_dom: $text"
		if [ "$dry" = 0 ] ; then
			printf '#!/bin/sh\nexec /usr/sbin/neanderfunk-domainhelper locate\n' > "$BR_DIR/locate.run"
			chmod +x "$BR_DIR/locate.run"
			start-stop-daemon -S -b -x "$BR_DIR/locate.run"
		fi
	fi
	br_save bridge "$f_if" "$s_since" "$f_dom" "$f_id" "$now" "$note"
	exit 0
fi

if [ -n "$note" ] ; then
	[ "$s_note" = "$note" ] || br_say "Domain-Bruecke an $f_if zu $f_dom bleibt: $text"
	br_save bridge "$f_if" "$s_since" "$f_dom" "$f_id" "$now" "$note"
	br_banner "yellow|Domain-Bruecke an $f_if zu $f_dom (Nachbar $f_id) bleibt: $text"
	exit 0
fi

# --- Trennen --------------------------------------------------------------------

if [ "$dry" = 1 ] ; then
	echo "wuerde trennen: $target ($f_if), Nachbar $f_id in $f_dom, bis zum Neustart"
	exit 0
fi

br_do_cut "$target"
br_save cut "$target" "$now" "$f_dom" "$f_id" "$now" getrennt
br_say "Domain-Bruecke getrennt: $target ($f_if), Nachbar $f_id in $f_dom, eigene Domain $own_domain${test_domain:+ (Test)}, bis zum Neustart"
br_banner "yellow|Domain-Bruecke zu $f_dom an $f_if getrennt (Nachbar $f_id), bis zum Neustart"
exit 0

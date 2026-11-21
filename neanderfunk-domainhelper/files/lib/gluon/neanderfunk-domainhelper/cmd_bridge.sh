#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
#
# Unterbefehl "bridge" von neanderfunk-domainhelper, wird von
# /usr/sbin/neanderfunk-domainhelper gesourct. Jede Minute aus micron.d.
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
#   3. Bruecke gesehen: melden (Syslog, Banner, Statusdatei), dann BR_FRIST
#      Sekunden warten.
#   4. Nach der Frist frisch nachfragen und trennen, wenn ALLES zutrifft:
#      - Trennen nicht abgeschaltet (uci neanderfunk-domainhelper.bridge.cut);
#      - eigenes VPN (batman-Nachbar auf mesh-vpn): Wir behalten unseren
#        Uplink;
#      - die Gegenseite hat einen eigenen Uplink: Der fremde Nachbar erreicht
#        sein Gateway direkt (gateway_nexthop = gateway, nur ueber einen
#        eigenen Tunnel moeglich), oder in batctl gwl steht ein Gateway, das
#        wir ueber genau diese Schnittstelle erreichen. Sonst schnitte das
#        Trennen die Gegenseite vom Netz ab.
#      Getrennt wird nur zur Laufzeit, kein uci commit, ein Neustart hebt es
#      auf:
#      - Ist der Hardif eine Bridge (br-mesh_other, br-wan bei Mesh-on-WAN):
#        zwei ebtables-Regeln verwerfen batman-Frames (0x4305) von und zu
#        diesem Knoten an der Bridge. Die Weiterleitung zwischen den Ports
#        bleibt, andere Knoten an unseren LAN-Ports meshen weiter
#        miteinander; nur wir sind draussen. Die Nachbarn fallen nach etwa
#        200 s aus batctl n.
#      - Sonst (ein einzelnes Geraet wie eth1.1): "ifdown" auf dem
#        gluon_wired-Interface (mesh_other, ...).
#      Solange getrennt, prueft jeder Lauf, ob die Trennung noch greift
#      (ein Neuladen der Firewall loescht die Regeln), und setzt sie neu.
#   5. Nach 10, 20, 40, 80, dann 120 min wieder freigeben und neu pruefen.
#      24 h ohne Trennen setzen die Stufe zurueck.
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
BR_FRIST=120
BR_CACHE_AGE=900
BR_REEVAL=600

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

br_backoff_min() {
	case "$1" in
		0) echo 10 ;; 1) echo 20 ;; 2) echo 40 ;; 3) echo 80 ;; *) echo 120 ;;
	esac
}

# Erster fremder Nachbar aus einer dh_lan_mesh-Datei: "<iface> <node_id> <domain>"
br_foreign() {
	local i id d
	awk -F "$DH_US" '$2 != "" && $3 != "" { d = $3; sub(/_EOL$/, "", d); print $1, $2, d }' "$1" |
	while read -r i id d ; do
		[ "$d" = "$own_domain" ] && continue
		case "$d" in
			*[!A-Za-z0-9_-]*) continue ;;
		esac
		[ -f "/lib/gluon/domains/$d.json" ] || continue
		echo "$i $id $d"
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

# Hat die Gegenseite hinter <iface> einen eigenen Uplink? (<iface> <datei>)
# Nach dem Trennen bleiben die Knoten dort ueber die Ports untereinander
# verbunden; es reicht also, wenn einer von ihnen einen eigenen Uplink hat.
br_far_uplink() {
	local line ids
	# Ein Gateway, das wir ueber genau diese Schnittstelle erreichen
	batctl gwl -H 2>/dev/null | awk -v i="$1" '
		{ s = $0; if (match(s, /\[[ \t]*[^] \t]+\]/)) { x = substr(s, RSTART + 1, RLENGTH - 2); gsub(/[ \t]/, "", x); if (x == i) f = 1 } }
		END { exit !f }' && return 0
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

br_iface_up() {
	[ "$(ubus call "network.interface.$1" status 2>/dev/null | jsonfilter -e '@.up' 2>/dev/null)" = true ]
}

br_do_cut() {
	case "$1" in
		eb:*) br_rules_present "${1#eb:}" || br_rules -I "${1#eb:}" ;;
		if:*) ifdown "${1#if:}" ;;
	esac
}

br_do_release() {
	case "$1" in
		eb:*) while br_rules_present "${1#eb:}" ; do br_rules -D "${1#eb:}" ; done ;;
		if:*) ifup "${1#if:}" ;;
	esac
}

# Greift die Trennung noch?
br_still_cut() {
	case "$1" in
		eb:*) br_rules_present "${1#eb:}" ;;
		if:*) ! br_iface_up "${1#if:}" ;;
	esac
}

# Ziel zum batman-Hardif <device>: eb:<device> bei einer Bridge, sonst
# if:<gluon_wired-Interface>, sonst nichts
br_target() {
	local m p
	if [ -d "/sys/class/net/$1/bridge" ] ; then
		echo "eb:$1"
		return 0
	fi
	m="$(ubus call network.interface dump 2>/dev/null | jsonfilter \
		-e "@.interface[@.l3_device='$1' && @.proto='gluon_mesh'].interface" 2>/dev/null | head -n 1)"
	case "$m" in
		*_mesh) p="${m%_mesh}" ;;
		*) return 0 ;;
	esac
	[ "$(ubus call "network.interface.$p" status 2>/dev/null | jsonfilter -e '@.proto' 2>/dev/null)" = gluon_wired ] || return 0
	echo "if:$p"
}

# --- getrennt: halten, nach Ablauf der Stufe freigeben ----------------------

if [ "$state" = cut ] ; then
	lvl=0 last=0
	[ -r "$BR_DIR/backoff" ] && read -r lvl last < "$BR_DIR/backoff"
	wait=$(( $(br_backoff_min "$lvl") * 60 ))
	if [ $((now - s_since)) -ge "$wait" ] ; then
		br_say "Domain-Bruecke: $s_if wieder frei, pruefe erneut"
		[ "$dry" = 1 ] || br_do_release "$s_if"
		br_save idle
		br_banner ''
	elif [ "$dry" = 1 ] ; then
		echo "getrennt: $s_if seit $((now - s_since)) s, frei nach $wait s"
	elif ! br_still_cut "$s_if" ; then
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
f_if="$1" f_id="$2" f_dom="$3"

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
		f_if="$1" f_id="$2" f_dom="$3"
	fi
	target="$(br_target "$f_if")"
	if ! br_far_uplink "$f_if" "$cache" ; then
		note=gegenseite_ohne_uplink
		text="Gegenseite ohne eigenen Uplink, Trennen wuerde sie abschneiden"
	elif [ -z "$target" ] ; then
		note=keine_schnittstelle
		text="weder Bridge noch gluon_wired-Interface zu $f_if"
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

lvl=-1 last=0
[ -r "$BR_DIR/backoff" ] && read -r lvl last < "$BR_DIR/backoff"
if [ "$lvl" -lt 0 ] || [ $((now - last)) -ge 86400 ] ; then
	lvl=0
else
	lvl=$((lvl + 1))
	[ "$lvl" -gt 4 ] && lvl=4
fi
min="$(br_backoff_min "$lvl")"

if [ "$dry" = 1 ] ; then
	echo "wuerde trennen: $target ($f_if), Nachbar $f_id in $f_dom, Neupruefung nach $min min"
	exit 0
fi

br_do_cut "$target"
echo "$lvl $now" > "$BR_DIR/backoff"
br_save cut "$target" "$now" "$f_dom" "$f_id" "$now" getrennt
br_say "Domain-Bruecke getrennt: $target ($f_if), Nachbar $f_id in $f_dom, eigene Domain $own_domain${test_domain:+ (Test)}, Neupruefung in $min min"
br_banner "yellow|Domain-Bruecke zu $f_dom an $f_if getrennt, Neupruefung in $min min (oder Neustart)"
exit 0

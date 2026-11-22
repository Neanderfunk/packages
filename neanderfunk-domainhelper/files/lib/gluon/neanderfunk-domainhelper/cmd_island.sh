#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
#
# Unterbefehl "island" von neanderfunk-domainhelper, wird von
# /usr/sbin/neanderfunk-domainhelper gesourct. Alle 91 s aus bridge-loop.sh.
#
# Insel ohne Gateway wieder ans Netz bringen (docs/entwurf-automesh.md,
# Abschnitt 0, Fall a und b). Steht laenger kein Gateway in batctl gwl,
# sucht der Knoten per Scan ein WLAN-Mesh einer Domain dieser Firmware:
#
#   a) Mesh der eigenen Domain auf einem anderen Kanal (auch wenn das eigene
#      Radio auf "auto" steht): nach ISL_WAIT_A (60 min) den Kanal dieses
#      Radios darauf stellen.
#   b) Mesh einer anderen Domain: nach ISL_WAIT_B (600 min) Domain und
#      Kanal wechseln (gluon-switch-domain --no-reboot, dann der Kanal,
#      dann Neustart).
#
# Dazu je Knoten ein fester Versatz von 0 bis 15 min aus der MAC: Fallen
# mehrere Knoten einer Wolke gleichzeitig aus, wechselt einer zuerst, die
# anderen sehen danach ueber das LAN-Mesh wieder ein Gateway. Ausserhalb von
# 25_hvb soll nichts hastig wechseln (adorfer 22.11.).
#
# In einer Domain mit Ortung (25_hvb, "Halteverbot") so bald wie moeglich:
# Fall a und b nach ISL_WAIT_HVB (5 min, Zeit fuer VPN und Gateway-Wahl nach
# dem Boot), ohne Versatz, naechster Wechsel nach ISL_REARM_HVB (15 min).
#
# Der Kanal wird dauerhaft gespeichert (Befehl "channel" aus
# neanderfunk-banner, ohne das uci-Delta mitzuschreiben, danach "wifi up
# <radio>"). Ist er der Standardkanal der (neuen) Domain, mit --no-keep:
# preserve_channels_<band>=0, der Knoten folgt dann weiter der Domain; sonst
# preserve_channels_<band>=1, egal was vorher stand, damit ein Update ihn
# nicht zuruecksetzt (adorfer 22.11.).
#
# Nicht gewechselt wird:
#   - zu einem Mesh-Punkt, dessen Knoten selbst offline ist: Ein AP auf
#     derselben Frequenz mit verwandter BSSID sendet die Offline-SSID des
#     ssid-changers (ssid_changer.prefix). Verwandt heisst: bis auf wenige
#     Bits gleich, entweder im letzten Byte (untere 3 Bit) oder im ersten
#     (Bits 0x0e). So bleiben bei einem Ausfall des Internets alle Knoten,
#     wo sie sind;
#   - auf einem Band ohne Mesh-Rolle (gluon.band_<band>.role): Dort ist das
#     Mesh bewusst aus, island schaltet es nicht ein;
#   - auf 5 GHz im Outdoor-Modus (dort waehlt Gluon den Kanal);
#   - in eine Domain mit Ortung (neanderfunk_domainhelper.locator.urls,
#     also 25_hvb);
#   - zu schwachen Mesh-Punkten (unter ISL_MIN_SIGNAL dBm).
# Nach einem Wechsel frueheste der naechste nach ISL_REARM (6 h), damit ein
# Mesh, das nicht ans Netz fuehrt, nicht stuendlich den Kanal kippt.
#
# Ein aktives LAN-Mesh oder weitere Knoten in der Wolke verhindern den
# Wechsel nicht (adorfer 21.11.); massgeblich ist nur: kein Gateway.
#
# Abschalten: uci neanderfunk-domainhelper.island.enabled=0.
# -n: Wartezeiten uebergehen, scannen und zeigen, was passieren wuerde.

ISL_DIR=/tmp/neanderfunk-domainhelper.island
ISL_BANNER=/tmp/neanderfunk-domainhelper.banner.island
ISL_WAIT_A=3600
ISL_WAIT_B=36000
ISL_REARM=21600
ISL_WAIT_HVB=300
ISL_REARM_HVB=900
ISL_SCAN_EVERY=300
ISL_MIN_SIGNAL=-80

dry=0
case "$1" in
	-n) dry=1 ;;
	'') ;;
	*) echo 'usage: neanderfunk-domainhelper island [-n]' >&2 ; exit 2 ;;
esac

[ "$(uci -q get gluon-setup-mode.@setup_mode[0].configured)" = 1 ] || exit 0
case "$(uci -q get neanderfunk-domainhelper.island.enabled)" in
	0|false|no|off|disabled) [ "$dry" = 1 ] || exit 0 ;;
esac

mkdir -p "$ISL_DIR" || exit 1

isl_say() {
	if [ "$dry" = 1 ] ; then echo "$*" ; else dh_log "$*" ; fi
}

now="$(dh_uptime)"

# --- Gateway da? ------------------------------------------------------------------

if [ -n "$(batctl gwl -H 2>/dev/null)" ] ; then
	if [ "$dry" = 1 ] ; then
		echo 'Gateway in Sicht: im Betrieb nichts zu tun, Auswertung trotzdem'
	elif [ -r "$ISL_DIR/since" ] ; then
		read -r since < "$ISL_DIR/since"
		rm -f "$ISL_DIR/since"
		[ $((now - since)) -ge "$ISL_WAIT_A" ] && \
			dh_log "Insel: Gateway wieder da nach $(( (now - since) / 60 )) min"
		exit 0
	else
		exit 0
	fi
fi

own_domain="$(uci -q get gluon.core.domain)"
offset=
if [ -n "$(jsonfilter -i "/lib/gluon/domains/$own_domain.json" -e '@.neanderfunk_domainhelper.locator.urls[0]' 2>/dev/null)" ] ; then
	# eigene Domain mit Ortung (25_hvb): so bald wie moeglich weg
	ISL_WAIT_A="$ISL_WAIT_HVB" ISL_WAIT_B="$ISL_WAIT_HVB" ISL_REARM="$ISL_REARM_HVB" offset=0
fi

since="$now"
if [ -r "$ISL_DIR/since" ] ; then
	read -r since < "$ISL_DIR/since"
else
	echo "$now" > "$ISL_DIR/since"
fi
if [ -z "$offset" ] ; then
	IFS=: read a a a a a m < /lib/gluon/core/sysconfig/primary_mac
	offset=$(( (0x$m % 16) * 60 ))
fi
age=$((now - since))
allow_b=0
[ "$age" -ge $((ISL_WAIT_B + offset)) ] && allow_b=1

if [ "$dry" = 0 ] ; then
	[ "$age" -ge $((ISL_WAIT_A + offset)) ] || exit 0
	last=0
	[ -r "$ISL_DIR/lastaction" ] && read -r last < "$ISL_DIR/lastaction"
	[ "$last" -gt 0 ] && [ $((now - last)) -lt "$ISL_REARM" ] && exit 0
	lscan=0
	[ -r "$ISL_DIR/lastscan" ] && read -r lscan < "$ISL_DIR/lastscan"
	[ "$lscan" -gt 0 ] && [ $((now - lscan)) -lt "$ISL_SCAN_EVERY" ] && exit 0
	echo "$now" > "$ISL_DIR/lastscan"
else
	allow_b=1
	echo "ohne Gateway seit $age s (Versatz $offset s); Fall a ab $((ISL_WAIT_A + offset)) s, Fall b ab $((ISL_WAIT_B + offset)) s"
fi

# Baender mit Mesh-Rolle, ohne Outdoor-5-GHz: "<band> <radio> <kanal>"
: > "$ISL_DIR/bands"
for r in $(uci -q show wireless | sed -n 's/^wireless\.\(radio[0-9]*\)=wifi-device$/\1/p') ; do
	band="$(uci -q get "wireless.$r.band")"
	case "$band" in 2g|5g) ;; *) continue ;; esac
	uci -q get "gluon.band_$band.role" | grep -qw mesh || continue
	if [ "$band" = 5g ] ; then
		case "$(uci -q get gluon.wireless.outdoor)" in 1|true) continue ;; esac
	fi
	grep -q "^$band " "$ISL_DIR/bands" && continue
	echo "$band $r $(uci -q get "wireless.$r.channel")" >> "$ISL_DIR/bands"
done
if [ ! -s "$ISL_DIR/bands" ] ; then
	[ "$dry" = 1 ] && echo 'kein Band mit Mesh-Rolle'
	exit 0
fi

# Domains: "<domain> <mesh-id 2g> <mesh-id 5g> <kanal 2g> <kanal 5g> <ziel>"
# ziel 0: Domain mit Ortung (25_hvb), nie Ziel von Fall b
: > "$ISL_DIR/domains"
for f in /lib/gluon/domains/*.json ; do
	d="${f##*/}" ; d="${d%.json}"
	ziel=1
	[ -n "$(jsonfilter -i "$f" -e '@.neanderfunk_domainhelper.locator.urls[0]' 2>/dev/null)" ] && ziel=0
	i2="$(jsonfilter -i "$f" -e '@.wifi24.mesh.id' 2>/dev/null)"
	i5="$(jsonfilter -i "$f" -e '@.wifi5.mesh.id' 2>/dev/null)"
	c2="$(jsonfilter -i "$f" -e '@.wifi24.channel' 2>/dev/null)"
	c5="$(jsonfilter -i "$f" -e '@.wifi5.channel' 2>/dev/null)"
	[ -n "$c2" ] || c2="$(jsonfilter -i /lib/gluon/site.json -e '@.wifi24.channel' 2>/dev/null)"
	[ -n "$c5" ] || c5="$(jsonfilter -i /lib/gluon/site.json -e '@.wifi5.channel' 2>/dev/null)"
	echo "$d ${i2:--} ${i5:--} ${c2:--} ${c5:--} $ziel" >> "$ISL_DIR/domains"
done

prefix="$(nf_site_get '@.ssid_changer.prefix')"
[ -n "$prefix" ] || prefix=FF_Offline_

# Nur zum Testen, nur mit -n: DH_ISLAND_SCANLIST=<datei> nimmt eine fertige
# Liste im Format von dh_scan_list statt zu scannen
if [ "$dry" = 1 ] && [ -n "$DH_ISLAND_SCANLIST" ] ; then
	cp "$DH_ISLAND_SCANLIST" "$ISL_DIR/scan.list"
else
	dh_scan "$ISL_DIR"
	dh_scan_list "$ISL_DIR"
fi

# Kandidat waehlen. Ausgabe: "<a|b> <domain> <band> <kanal> <signal> <bssid>"
cand="$(awk -v US="$DH_US" -v own="$own_domain" -v pre="$prefix" \
	-v minsig="$ISL_MIN_SIGNAL" -v allowb="$allow_b" \
	-v dfile="$ISL_DIR/domains" -v bfile="$ISL_DIR/bands" -v dry="$dry" '
	function hx(s,   i, v) { v = 0; for (i = 1; i <= length(s); i++) v = v * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1; return v }
	function related(x, y,   p, q, i, same) {
		split(x, p, ":"); split(y, q, ":")
		same = 1; for (i = 2; i <= 6; i++) if (p[i] != q[i]) same = 0
		if (same && and(xor(hx(p[1]), hx(q[1])), 241) == 0) return 1
		same = 1; for (i = 1; i <= 5; i++) if (p[i] != q[i]) same = 0
		if (same && and(xor(hx(p[6]), hx(q[6])), 248) == 0) return 1
		return 0
	}
	function chan(f) {
		if (f == 2484) return 14
		if (f < 4000) return int((f - 2407) / 5)
		return int((f - 5000) / 5)
	}
	BEGIN {
		while ((getline l < dfile) > 0) {
			split(l, x, " ")
			if (x[2] != "-") dom["2g|" x[2]] = x[1]
			if (x[3] != "-") dom["5g|" x[3]] = x[1]
			ziel[x[1]] = x[6]
		}
		while ((getline l < bfile) > 0) { split(l, x, " "); okband[x[1]] = 1; cur[x[1]] = x[3] }
		FS = US
	}
	{ n++; bs[n] = $1; fr[n] = $2 + 0; sg[n] = $3 + 0; ss[n] = $4; mi[n] = $5 }
	END {
		best = ""; bk = ""; bsig = -999
		for (i = 1; i <= n; i++) {
			if (mi[i] == "") continue
			band = (fr[i] < 4000) ? "2g" : "5g"
			d = dom[band "|" mi[i]]
			c = chan(fr[i])
			why = ""
			if (d == "") why = "keine Domain dieser Firmware"
			else if (!(band in okband)) why = "Band ohne Mesh-Rolle"
			else if (sg[i] < minsig) why = "zu schwach"
			k = (d == own) ? "a" : "b"
			if (why == "" && k == "b" && ziel[d] == "0") why = "Zieldomain mit Ortung"
			if (why == "" && k == "b" && !allowb) why = "Fall b noch nicht dran"
			if (why == "" && k == "a" && cur[band] == c "") why = "gleicher Kanal wie unser Radio"
			if (why == "")
				for (j = 1; j <= n; j++)
					if (j != i && fr[j] == fr[i] && index(ss[j], pre) == 1 && related(bs[i], bs[j])) why = "Knoten offline (" ss[j] ")"
			if (dry) printf "  Mesh %s (%s, %s) Kanal %d %d dBm %s: %s\n", mi[i], (d == "" ? "-" : d), band, c, sg[i], bs[i], (why == "" ? "Kandidat " k : why) > "/dev/stderr"
			if (why != "") continue
			# a vor b, dann staerkstes Signal
			if (best == "" || (k == "a" && bk == "b") || (k == bk && sg[i] > bsig)) {
				best = k " " d " " band " " c " " sg[i] " " bs[i]; bk = k; bsig = sg[i]
			}
		}
		print best
	}' "$ISL_DIR/scan.list")"

if [ -z "$cand" ] ; then
	[ "$dry" = 1 ] && echo 'kein passendes Mesh gefunden'
	exit 0
fi
set -- $cand
kind="$1" tdom="$2" band="$3" ch="$4" sig="$5" bssid="$6"

# Standardkanal der Zieldomain fuer dieses Band
def="$(awk -v d="$tdom" -v b="$band" '$1 == d { print (b == "2g") ? $4 : $5 }' "$ISL_DIR/domains")"
keep=
[ "$ch" = "$def" ] && keep=--no-keep
if [ "$band" = 2g ] ; then args="$ch -" ; else args="- $ch" ; fi
cur="$(awk -v b="$band" '$1 == b { print $3 }' "$ISL_DIR/bands")"

if [ "$kind" = a ] ; then
	what="Insel: Mesh der eigenen Domain $own_domain auf $band Kanal $ch ($sig dBm, $bssid), stelle Kanal von $cur auf $ch${keep:+ (Standardkanal, ohne Festschreiben)}"
else
	what="Insel: Mesh der Domain $tdom auf $band Kanal $ch ($sig dBm, $bssid), wechsle Domain $own_domain -> $tdom und Kanal${keep:+ (Standardkanal, ohne Festschreiben)}"
fi

if [ "$dry" = 1 ] ; then
	echo "wuerde: $what"
	[ "$kind" = b ] && echo "  uci revert (alle Laufzeit-Deltas); gluon-switch-domain --no-reboot $tdom"
	echo "  channel $args $keep -f"
	[ "$kind" = b ] && echo "  reboot"
	exit 0
fi

echo "$now" > "$ISL_DIR/lastaction"
dh_log "$what"
if [ "$kind" = a ] ; then
	# shellcheck disable=SC2086
	if channel $args $keep -f > "$ISL_DIR/channel.out" 2>&1 ; then
		echo "yellow|Insel: $band-Kanal von $cur auf $ch gestellt, Mesh der eigenen Domain ($bssid)" > "$ISL_BANNER"
	else
		dh_log "Insel: channel fehlgeschlagen: $(tail -n 1 "$ISL_DIR/channel.out")"
	fi
	exit 0
fi

# Fall b: Domain, dann Kanal, dann Neustart. neanderfunk-preserve-wifichannel
# traegt im gluon-reconfigure des Domainwechsels einmal die Kanaele der neuen
# Domain ein; der Kanal kommt deshalb danach.
# Vorher alle Laufzeit-Deltas verwerfen (Offline-SSID, ap-timer, Blackout):
# 001-reset-uci im gluon-reconfigure macht ein pauschales "uci commit" und
# schriebe sie sonst in den Flash. Der Neustart verwirft sie ohnehin.
for p in $(uci changes 2>/dev/null | sed -n 's/^-\{0,1\}\([^.]*\)\..*/\1/p' | sort -u) ; do
	uci revert "$p"
done
if ! gluon-switch-domain --no-reboot "$tdom" > "$ISL_DIR/switch.out" 2>&1 ; then
	dh_log "Insel: gluon-switch-domain fehlgeschlagen: $(tail -n 1 "$ISL_DIR/switch.out")"
	exit 0
fi
# shellcheck disable=SC2086
channel $args $keep -f > "$ISL_DIR/channel.out" 2>&1 || \
	dh_log "Insel: channel fehlgeschlagen: $(tail -n 1 "$ISL_DIR/channel.out")"
dh_log "Insel: Domain jetzt $tdom, Neustart"
sync
reboot
exit 0

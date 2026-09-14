#!/bin/sh
# Reboot a node whose ethernet TX hangs after a transmit timeout and does not
# come back (mtk_soc_eth on MT7981/MT7986, openwrt/openwrt#17505).
#
# What the kernel does (5.15 with the backports 729-19..21):
#   * dev_watchdog() finds a TX queue stopped for longer than watchdog_timeo
#     (5 s for mtk_soc_eth), counts /sys/class/net/<dev>/queues/tx-N/tx_timeout
#     up and calls the driver. It keeps doing that every 5 s for as long as the
#     queue stays stuck; the "NETDEV WATCHDOG ... transmit queue N timed out"
#     WARN only appears once per boot.
#   * mtk_tx_timeout() only schedules a reset when mtk_hw_reset_check() finds
#     error bits in the frame engine's interrupt status. Otherwise it returns
#     silently and the queue may simply stay stuck.
#   * A reset that fails logs "warm reset failed"; after that both GMACs are
#     dead until a reboot, reportedly on some boards not even that.
#
# So the trigger is: the tx_timeout counters of a netdev keep rising - the
# kernel re-fires every 5 s while a queue stays stuck - and its tx_packets does
# not move, for hotfix.eth_tx_stall.strikes runs in a row (default 3, one run a
# minute). "warm reset failed" in the dmesg makes a run count double and also
# counts without new timeouts (a dead GMAC need not have carrier any more); it
# speeds a reboot up, it never triggers one on its own.
#
# The episode ends without action when
#   * TX moves again and no new timeouts came: the warm reset worked;
#   * no new timeouts came although TX stands: the reset worked and the port is
#     just quiet, or the carrier went away (the kernel watchdog only fires with
#     carrier, so a pulled cable never starts an episode either).
# Timeouts while TX keeps moving (one queue stuck while others send) are logged
# once per episode and never acted on.
#
# Before a reboot comes a port reset: "ethtool -r <dev>" restarts autoneg, as
# if the cable had been pulled and put back (adorfer, 14.09.2026). On the Cudy
# TR3000 with its RTL8221B only that ever helped; a reboot with the cable in
# often did not. So when the strikes are reached:
#   1. ethtool -r (if ethtool is there and hotfix.eth_tx_stall.soft_reset is not
#      0) - also in dry run, it is harmless and tells us something. Logged to the
#      syslog only, not to the reboot log on flash. If TX comes back: "recovered
#      after ethtool -r", done. If ethtool fails (fixed link, driver without
#      nway_reset), straight on to 2.
#   2. the strikes are reached again within the hour: reboot, or in dry run
#      "would reboot". One ethtool -r per port counts for 60 minutes, so a port
#      that goes quiet after the reset cannot keep the check from escalating.
# Without ethtool it is 2. straight away, as before; no "ip link down/up" as a
# substitute, it would cut across netifd and br-wan.
#
# Second, narrow trigger, only for ports with an RTL8221B PHY that are in br-wan
# (Cudy TR3000, WR3000H, M3000): carrier up but rx_packets does not move for
# hotfix.eth_tx_stall.rx_strikes runs (default 5, i.e. 5 minutes). That is the
# "booted with the cable already in, SerDes mode wrong" case, which need not
# produce a single tx timeout. An uplink receives something every few seconds
# (ARP, RA, VPN keepalives), five minutes of nothing with link up is not idle.
# Reaction: only ethtool -r, never a reboot, at most once per hour per port -
# the same budget as step 1 above, so the two triggers never reset a port twice.
#
# Only logs by default (dry run): the reaction is unproven in the field. To
# let it reboot:
#     uci set hotfix.eth_tx_stall.dry_run='0' ; uci commit hotfix
# or community-wide in the site.conf: hotfix = { eth_tx_stall_dry_run = 0 }.
#
# Only the netdevs the driver itself registers (the GMACs, eth0/eth1), not the
# DSA ports behind them: /sys/bus/*/drivers/<driver>/*/net/*. mtk_soc_eth is
# the name on filogic, MT7621, MT7622 and (OpenWrt's own ramips driver) mt76x8
# and mt7620 - about a quarter of the fleet. More drivers:
#     uci add_list hotfix.eth_tx_stall.driver='<name>' ; uci commit hotfix
#
# Testing without a reboot (see the README):
#     HOTFIX_DRYRUN=1 / =0                      dry run on / off for one run
#     HOTFIX_SYSFS=/tmp/fake                    sysfs root to read from
#     HOTFIX_DMESG=/tmp/fake.dmesg              file instead of dmesg
#     HOTFIX_STATE=/tmp/x                       state prefix instead of /tmp/hotfix.eth_tx_stall
#     HOTFIX_ETHTOOL='echo ethtool'             command instead of ethtool

CHECK='eth_tx_stall'
SYSFS="${HOTFIX_SYSFS:-/sys}"
STATE="${HOTFIX_STATE:-/tmp/hotfix.$CHECK}"

# --- ohne Unterprozess entscheiden, ob es hier ueberhaupt etwas zu tun gibt --
#
# Der Eintrag laeuft jede Minute auf JEDEM Knoten, und die allermeisten haben
# kein mtk_soc_eth. Schon das "uci show" aus common.sh waere dort jede Minute
# ein Prozessstart fuer nichts, auf 64-MB-Geraeten aus dem Flash. Deshalb die
# Treiberliste direkt aus /etc/config/hotfix lesen (read ist ein Builtin) und
# common.sh erst laden, wenn ein passendes Netdev da ist. Folge: ein per uci
# ergaenzter Treiber gilt erst nach "uci commit hotfix".
drivers='mtk_soc_eth'
sec=''
if [ -r /etc/config/hotfix ] ; then
	while read -r kw a b _ ; do
		case "$kw" in
			config) sec="$b" ;;
			list)
				case "$sec:$a" in
					"'$CHECK':driver"|"$CHECK:driver")
						b="${b#\'}" ; drivers="$drivers ${b%\'}" ;;
				esac
				;;
		esac
	done < /etc/config/hotfix
fi

devs=''
for drv in $drivers ; do
	for n in "$SYSFS"/bus/*/drivers/"$drv"/*/net/* ; do
		[ -e "$n" ] || continue
		devs="$devs ${n##*/}"
	done
done
[ -n "$devs" ] || exit 0

# Kein Timeout seit dem Boot und keine laufende Episode: fertig, ebenfalls ohne
# Unterprozess. Das ist der Normalfall auf allen ~260 Knoten mit diesem
# Treiber, darunter 64-MB-Geraete (R6120, WR1000) - common.sh und uci erst,
# wenn der Kernel wirklich einen Timeout gezaehlt hat.
# Ports mit RTL8221B-PHY im br-wan, fuer den RX-Ausloeser. Die Treiber sind auf
# jedem filogic-Image registriert; es zaehlt nur, ob der phydev eines Ports auf
# einen davon zeigt. [ -ef ] vergleicht das ohne Prozessstart.
rtl_devs=''
for drvdir in "$SYSFS"/bus/mdio_bus/drivers/*8221B* ; do
	[ -d "$drvdir" ] || continue
	for dev in $devs ; do
		[ "$SYSFS/class/net/$dev/phydev/driver" -ef "$drvdir" ] || continue
		[ -e "$SYSFS/class/net/br-wan/brif/$dev" ] || continue
		case " $rtl_devs " in *" $dev "*) ;; *) rtl_devs="$rtl_devs $dev" ;; esac
	done
done

busy=''
[ -n "$rtl_devs" ] && busy=1
for dev in $devs ; do
	[ -e "$STATE.$dev" ] && busy=1
	for q in "$SYSFS/class/net/$dev"/queues/tx-*/tx_timeout ; do
		[ -r "$q" ] || continue
		v=0
		read -r v < "$q"
		[ "$v" = 0 ] || busy=1
	done
done
[ -n "$busy" ] || exit 0

HOTFIX_TAG='neanderfunk-hotfix'
. /lib/gluon/neanderfunk-hotfix/common.sh

check_disabled "$CHECK" && exit 0
checks_ok || exit 0

if command -v flock >/dev/null 2>&1 ; then
	exec 200<"$0"
	flock -n 200 || exit 0
fi

need=3
nf_uci_get "$NF_UCI_hotfix" "hotfix.$CHECK.strikes"
case "$NF_VAL" in
	''|0|*[!0-9]*) ;;
	*) need="$NF_VAL" ;;
esac

# nur loggen, solange niemand ausdruecklich dry_run=0 gesetzt hat
dry=1
nf_uci_get "$NF_UCI_hotfix" "hotfix.$CHECK.dry_run" && [ "$NF_VAL" = 0 ] && dry=''
case "${HOTFIX_DRYRUN:-}" in
	1) dry=1 ;;
	0) dry='' ;;
esac

log() {
	logger -s -t "$HOTFIX_TAG" -p 5 "[$CHECK] $*"
}

# Port-Reset per ethtool -r: an, solange soft_reset nicht 0 ist und ethtool da
ETHTOOL="${HOTFIX_ETHTOOL:-ethtool}"
soft=1
nf_uci_get "$NF_UCI_hotfix" "hotfix.$CHECK.soft_reset" && [ "$NF_VAL" = 0 ] && soft=''
command -v "${ETHTOOL%% *}" >/dev/null 2>&1 || soft=''

rx_need=5
nf_uci_get "$NF_UCI_hotfix" "hotfix.$CHECK.rx_strikes"
case "$NF_VAL" in
	''|0|*[!0-9]*) ;;
	*) rx_need="$NF_VAL" ;;
esac

nf_uptime
SOFT_HOLD=3600

# true, wenn der Port-Reset hinter diesem Marker weniger als SOFT_HOLD her ist
soft_recent() {
	local t=''
	[ -r "$1" ] && read -r t < "$1"
	case "$t" in ''|*[!0-9]*) return 1 ;; esac
	[ $((NF_UP - t)) -lt "$SOFT_HOLD" ]
}

# port_reset <dev> <warum>: ethtool -r, Ergebnis ins Syslog; Rueckgabe wie ethtool
port_reset() {
	local out rc
	out="$($ETHTOOL -r "$1" 2>&1)"
	rc=$?
	if [ "$rc" = 0 ] ; then
		log "$1: $2 - port reset (ethtool -r), watching whether it comes back"
	else
		log "$1: $2 - ethtool -r failed (rc $rc${out:+: $(echo "$out" | head -n 1)})"
	fi
	return "$rc"
}

# dmesg nur lesen, wenn ein Netdev scharf ist und steht - also praktisch nie.
# DMESG_HITS: die letzten zwei passenden Zeilen ohne Zeitstempel, je hoechstens
# 120 Zeichen, zu einer Zeile zusammengezogen
DMESG_READ='' DMESG_FAILED='' DMESG_HITS=''
read_dmesg() {
	[ -n "$DMESG_READ" ] && return
	DMESG_READ=1
	local out line
	if [ -n "$HOTFIX_DMESG" ] ; then
		out="$(grep -e 'NETDEV WATCHDOG' -e 'warm reset' "$HOTFIX_DMESG" 2>/dev/null | tail -n 2)"
	else
		out="$(dmesg 2>/dev/null | grep -e 'NETDEV WATCHDOG' -e 'warm reset' | tail -n 2)"
	fi
	case "$out" in *'warm reset failed'*) DMESG_FAILED=1 ;; esac
	local IFS='
'
	for line in $out ; do
		line="${line#\[*\] }"
		DMESG_HITS="${DMESG_HITS:+$DMESG_HITS | }$(echo "$line" | cut -c1-120)"
	done
}

for dev in $devs ; do
	d="$SYSFS/class/net/$dev"
	st="$STATE.$dev"

	sum=0 inflight=0
	for q in "$d"/queues/tx-* ; do
		[ -r "$q/tx_timeout" ] || continue
		read -r v < "$q/tx_timeout" && sum=$((sum + v))
		if [ -r "$q/byte_queue_limits/inflight" ] ; then
			read -r v < "$q/byte_queue_limits/inflight" && inflight=$((inflight + v))
		fi
	done
	pkts=''
	read -r pkts < "$d/statistics/tx_packets" 2>/dev/null
	[ -n "$pkts" ] || continue
	# carrier is unreadable (EINVAL) while the interface is down
	carrier=0
	read -r carrier < "$d/carrier" 2>/dev/null

	psum='' ppkts=''
	[ -r "$st" ] && read -r psum ppkts < "$st"
	echo "$sum $pkts" > "$st"
	# Kein Zustand: bisher waren alle Zaehler 0 (sonst gaebe es ihn), also gilt
	# 0 als Vorwert. Ob TX steht, laesst sich erst ab dem naechsten Lauf sagen.
	[ -n "$psum" ] || psum=0
	# counters went backwards (driver reload): start over
	if [ "$sum" -lt "$psum" ] || { [ -n "$ppkts" ] && [ "$pkts" -lt "$ppkts" ] ; } ; then
		rm -f "$st.armed"
		unstrike "$st.s"
		continue
	fi

	rose='' moved=''
	[ "$sum" -gt "$psum" ] && rose=1
	[ -n "$ppkts" ] && [ "$pkts" -gt "$ppkts" ] && moved=1

	# armed = this episode's timeouts have been logged; holds the count before
	if [ -n "$rose" ] && [ ! -e "$st.armed" ] ; then
		echo "$psum" > "$st.armed"
		if [ -n "$moved" ] ; then
			log "$dev: tx timeout (count $psum -> $sum), tx still moves, watching"
		else
			log "$dev: tx timeout (count $psum -> $sum), tx_packets at $pkts, watching"
		fi
	fi
	[ -e "$st.armed" ] || continue
	[ -n "$ppkts" ] || continue
	read -r first < "$st.armed"

	if [ -n "$moved" ] ; then
		# TX moves. Without new timeouts that is the warm reset having worked;
		# with new ones it is a single queue stuck while others still send, not
		# what this check is about - stay armed, but start counting over.
		if [ -z "$rose" ] ; then
			if [ -e "$st.soft" ] ; then
				log "$dev: tx moves again after tx timeout (count $first -> $sum), recovered after ethtool -r"
				rm -f "$st.soft"
			else
				log "$dev: tx moves again after tx timeout (count $first -> $sum), recovered, no action"
			fi
			rm -f "$st.armed"
		fi
		unstrike "$st.s"
		continue
	fi

	read_dmesg
	if [ -z "$rose" ] && [ -z "$DMESG_FAILED" ] ; then
		# TX stands, but the kernel counted no new timeout: the reset worked and
		# the port is just quiet, or the carrier went away. Neither is the hang.
		log "$dev: no further tx timeouts (count $first -> $sum, carrier $carrier), tx idle or cable out, episode closed, no action"
		rm -f "$st.armed"
		unstrike "$st.s"
		continue
	fi
	n="$(strike "$st.s")"
	[ -n "$DMESG_FAILED" ] && n="$(strike "$st.s")"
	if [ "$n" -lt "$need" ] ; then
		log "$dev: tx_packets stuck at $pkts, tx_timeout $first -> $sum (strike $n of $need${DMESG_FAILED:+, warm reset failed})"
		continue
	fi

	# Stufe 1: Port-Reset, einmal je Stunde und Port. Klappt ethtool nicht,
	# gleich weiter zur Stufe 2.
	if [ -n "$soft" ] && ! soft_recent "$st.soft" ; then
		if port_reset "$dev" "tx hung since tx timeout, tx_packets stuck at $pkts, tx_timeout $first -> $sum" ; then
			echo "$NF_UP" > "$st.soft"
			unstrike "$st.s"
			continue
		fi
	fi

	soft_note=''
	soft_recent "$st.soft" && soft_note=', ethtool -r did not help'
	reason="[$CHECK] $dev: tx hung since tx timeout, tx_packets stuck at $pkts (strike $n of $need), tx_timeout $first -> $sum, bql inflight $inflight, carrier $carrier$soft_note${DMESG_HITS:+; dmesg: $DMESG_HITS}"
	rm -f "$st.armed"
	unstrike "$st.s"
	if [ -n "$dry" ] ; then
		log "dry run, would reboot: ${reason#\[$CHECK\] }"
		continue
	fi
	now_reboot "$reason"
done

# RTL8221B-Uplink: Link da, aber RX steht -> nur Port-Reset, nie Reboot
for dev in $rtl_devs ; do
	d="$SYSFS/class/net/$dev"
	sr="$STATE.$dev.rx"
	rx=''
	read -r rx < "$d/statistics/rx_packets" 2>/dev/null
	[ -n "$rx" ] || continue
	carrier=0
	read -r carrier < "$d/carrier" 2>/dev/null
	prx=''
	[ -r "$sr" ] && read -r prx < "$sr"
	echo "$rx" > "$sr"

	if [ "$carrier" != 1 ] || [ -z "$prx" ] || [ "$rx" != "$prx" ] ; then
		unstrike "$sr.s"
		if [ "$carrier" = 1 ] && [ -n "$prx" ] && [ "$rx" != "$prx" ] && [ -e "$STATE.$dev.soft" ] ; then
			log "$dev: uplink rx moves again after ethtool -r (rx_packets $prx -> $rx), recovered"
			rm -f "$STATE.$dev.soft"
		fi
		continue
	fi

	n="$(strike "$sr.s")"
	[ "$n" = 1 ] && log "$dev: uplink (RTL8221B) has carrier but rx_packets stands at $rx, watching"
	[ "$n" -lt "$rx_need" ] && continue
	unstrike "$sr.s"
	if [ -z "$soft" ] ; then
		log "$dev: uplink rx_packets stuck at $rx with carrier for $n min, no ethtool or soft_reset=0, no action"
		continue
	fi
	soft_recent "$STATE.$dev.soft" && continue
	port_reset "$dev" "uplink (RTL8221B) has carrier but rx_packets stuck at $rx for $n min" &&
		echo "$NF_UP" > "$STATE.$dev.soft"
done
exit 0

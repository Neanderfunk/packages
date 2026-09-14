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
busy=''
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
			log "$dev: tx moves again after tx timeout (count $first -> $sum), recovered, no action"
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

	reason="[$CHECK] $dev: tx hung since tx timeout, tx_packets stuck at $pkts (strike $n of $need), tx_timeout $first -> $sum, bql inflight $inflight, carrier $carrier${DMESG_HITS:+; dmesg: $DMESG_HITS}"
	rm -f "$st.armed"
	unstrike "$st.s"
	if [ -n "$dry" ] ; then
		log "dry run, would reboot: ${reason#\[$CHECK\] }"
		continue
	fi
	now_reboot "$reason"
done
exit 0

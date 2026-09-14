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
# So the trigger is: the tx_timeout counters of a netdev rose, and after that
# its tx_packets does not move for hotfix.eth_tx_stall.strikes runs (default
# 3, one run a minute). If TX moves again - the warm reset worked - the check
# logs that and forgets the episode.
#
# Without carrier the kernel watchdog does not fire at all, so a pulled cable
# never arms the check. Should carrier go away while it is armed, the episode
# is dropped unless "warm reset failed" is in the dmesg; a cable pulled in the
# middle of an episode must not reboot the node. That line also makes each
# stagnant run count double - it speeds the reboot up, it never triggers one
# on its own.
#
# Timeouts while TX keeps moving (reset worked within the minute, or one queue
# stuck while others send) are logged once per episode and never acted on.
#
# Only the netdevs the driver itself registers (the GMACs, eth0/eth1), not the
# DSA ports behind them: /sys/bus/*/drivers/<driver>/*/net/*. More drivers:
#     uci add_list hotfix.eth_tx_stall.driver='<name>' ; uci commit hotfix
#
# Testing without a reboot (see the README):
#     uci set hotfix.eth_tx_stall.dry_run='1'   logs "would reboot" instead
#     HOTFIX_DRYRUN=1                           the same, for one run
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

dry="${HOTFIX_DRYRUN:-}"
if [ -z "$dry" ] && nf_uci_get "$NF_UCI_hotfix" "hotfix.$CHECK.dry_run" ; then
	[ "$NF_VAL" = 1 ] && dry=1
fi

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
	# first run after a boot, or the counters went backwards (driver reload):
	# nothing to compare against yet
	if [ -z "$ppkts" ] || [ "$sum" -lt "$psum" ] || [ "$pkts" -lt "$ppkts" ] ; then
		rm -f "$st.armed"
		unstrike "$st.s"
		continue
	fi

	# armed = this episode's timeouts have been logged; holds the count before
	if [ "$sum" -gt "$psum" ] && [ ! -e "$st.armed" ] ; then
		echo "$psum" > "$st.armed"
		if [ "$pkts" -gt "$ppkts" ] ; then
			log "$dev: tx timeout (count $psum -> $sum), tx still moves, watching"
		else
			log "$dev: tx timeout (count $psum -> $sum), tx_packets stands at $pkts, watching"
		fi
	fi

	if [ "$pkts" -gt "$ppkts" ] ; then
		# TX moves. Without new timeouts that is the warm reset having worked;
		# with new ones it is a single queue stuck while others still send, not
		# what this check is about - stay armed, but start counting over.
		if [ -e "$st.armed" ] && [ "$sum" -eq "$psum" ] ; then
			read -r first < "$st.armed"
			log "$dev: tx moves again after tx timeout (count $first -> $sum), recovered, no action"
			rm -f "$st.armed"
		fi
		unstrike "$st.s"
		continue
	fi
	[ -e "$st.armed" ] || continue

	read_dmesg
	if [ "$carrier" != 1 ] && [ -z "$DMESG_FAILED" ] ; then
		# most likely a cable pulled mid-episode. Drop the episode: with the
		# cable back and TX still stuck the kernel watchdog fires again and
		# arms it anew, and a cable that stays out does not log every minute.
		log "$dev: carrier lost while tx hung, episode dropped, no action"
		rm -f "$st.armed"
		unstrike "$st.s"
		continue
	fi
	n="$(strike "$st.s")"
	[ -n "$DMESG_FAILED" ] && n="$(strike "$st.s")"
	if [ "$n" -lt "$need" ] ; then
		log "$dev: tx_packets stuck at $pkts, tx_timeout $sum (strike $n of $need${DMESG_FAILED:+, warm reset failed})"
		continue
	fi

	read -r first < "$st.armed"
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

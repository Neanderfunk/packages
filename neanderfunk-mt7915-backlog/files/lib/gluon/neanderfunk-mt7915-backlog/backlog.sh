#!/bin/sh
# Work around a known mt7915e firmware bug (freifunk-gluon/gluon#3154): once the
# driver's txq backlog fills up, the radio stops answering reliably over wifi -
# pings go unanswered, traffic stalls. Restart wifi before it gets that far.
#
# Ported from ffac-mt7915-backlog, see README.md. Differences to the original:
#
#   * Only mt7915 phys are looked at. The package gate is by build target
#     (ramips_mt7621, mediatek_filogic, mediatek_mt7622) plus kmod-mt7915e, but
#     an mt7621 board need not carry an mt7915 radio at all: a Xiaomi Mi Router
#     4A Gigabit is ramips/mt7621 with mt7603e and mt76x2e, and this script was
#     polling both of them every two minutes and would have restarted its wifi
#     on an mt7915-specific symptom.
#   * The backlog value is checked before it is compared. Every device tested
#     prints exactly one "Backlog:" line per phy, but an absent or multi-line
#     value made "[ "$backlog" -gt 50 ]" a shell error instead of a skip.
#   * A cool-down between restarts. The original restarted wifi on every run
#     that saw a high backlog, so a backlog that does not clear meant a wifi
#     restart every two minutes for as long as it lasted - each one throwing
#     the clients off.
#   * The logger tag follows the package name, so it can be grepped for like
#     the rest of this feed.
#
# No autoupdater guard here on purpose: the autoupdater stops micrond before it
# downloads, so this job cannot run during a download or flash anyway.

TAG='neanderfunk-mt7915-backlog'
MARKER='/tmp/mt7915backlog.last-restart'

[ "$(uci -q get mt7915backlog.settings.disabled)" = "1" ] && exit 0

# Two uptime thresholds, same rule as neanderfunk-hotfix and -linkcheck:
#   below check_uptime_min (default 5) do not even look - the radios are still
#     coming up and a transient backlog says nothing;
#   below reboot_uptime_min (default 60) report the backlog but do not restart
#     wifi, so a node that has just booted is not thrown around again.
uptime_s="$(sed 's/\..*//g' /proc/uptime)"
check_min="$(uci -q get mt7915backlog.settings.check_uptime_min)"
case "$check_min" in ''|*[!0-9]*) check_min=5 ;; esac
[ "$uptime_s" -gt "$((check_min * 60))" ] || exit 0
action_min="$(uci -q get mt7915backlog.settings.reboot_uptime_min)"
case "$action_min" in ''|*[!0-9]*) action_min=60 ;; esac

threshold="$(uci -q get mt7915backlog.settings.threshold)"
case "$threshold" in ''|*[!0-9]*) threshold=50 ;; esac
cooldown="$(uci -q get mt7915backlog.settings.cooldown_min)"
case "$cooldown" in ''|*[!0-9]*) cooldown=30 ;; esac

# /sys/class/ieee80211 rather than the original's /sys/kernel/debug/ieee80211:
# the class directory is always there, debugfs need not be mounted.
for phy in /sys/class/ieee80211/phy* ; do
	[ -e "$phy" ] || continue
	phy_name="$(basename "$phy")"

	drv="$(readlink -f "$phy/device/driver" 2>/dev/null)"
	case "${drv##*/}" in
		mt7915*) ;;
		*) continue ;;
	esac

	backlog="$(iw phy "$phy_name" get txq 2>/dev/null | awk '/Backlog/ {print $2; exit}')"
	case "$backlog" in
		''|*[!0-9]*)
			logger -s -t "$TAG" -p 5 "$phy_name: no usable backlog value from iw, skipped"
			continue
			;;
	esac

	if [ "$backlog" -le "$threshold" ] ; then
		[ "$backlog" -gt 0 ] && logger -s -t "$TAG" -p 5 "$phy_name: backlog $backlog (below $threshold)"
		continue
	fi

	if [ -f "$MARKER" ] ; then
		age=$(( ( $(date +%s) - $(date -r "$MARKER" +%s) ) / 60 ))
		if [ "$age" -lt "$cooldown" ] ; then
			logger -s -t "$TAG" -p 5 "$phy_name: backlog $backlog over $threshold, but wifi was restarted ${age}min ago, waiting out the ${cooldown}min cool-down"
			continue
		fi
	fi

	if [ "$uptime_s" -le "$((action_min * 60))" ] ; then
		logger -s -t "$TAG" -p 5 "$phy_name: backlog $backlog over $threshold - no action taken, uptime below mt7915backlog.settings.reboot_uptime_min (${action_min}min)"
		continue
	fi

	logger -s -t "$TAG" -p 5 "$phy_name: backlog $backlog over $threshold - restarting wifi"
	touch "$MARKER"
	# Twice, as in the original. Kept deliberately: the failure mode it works
	# around cannot be reproduced here, so the call is left as the upstream
	# authors found it to work.
	wifi
	wifi
	# One restart per run - it takes down every radio anyway, so looking at the
	# remaining phys afterwards would only measure the restart.
	break
done

exit 0

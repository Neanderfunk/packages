#!/bin/sh
# Detect a crashed mt76 wifi firmware and reboot.
#
# /sys/kernel/debug/ieee80211/phy*/mt76/rf_regval is a register window into the
# running wifi firmware. While that firmware lives, reading it yields a value.
# When it has crashed the file is still there, but the read fails - the driver
# cannot reach the chip any more. "Present but unreadable" is therefore about
# as direct a crash detector as we have; there is no self-recovery and no
# remedy short of a reboot (the firmware is loaded when the module probes, so
# `wifi down; wifi up` does not reload it).
#
# Ported from ffac-mt7915-hotfix in community-packages, which we can drop once
# this ships. Differences to the original:
#
#   * The original expanded phy* twice, independently: once in `ls` and once in
#     `cat`. On a device where one phy has the file and another does not, the
#     `ls` succeeds while the `cat` fails, and the node reboots for a file that
#     was never there. Here each phy is looked at on its own, and only a phy
#     whose file exists is read.
#   * Uptime thresholds like every other check here. The original had none at
#     all - it could reboot two minutes into a boot, while the firmware was
#     still coming up.
#   * Two strikes before acting, so a single failed read does not reboot.
#   * The autoupdater guard uses the markers our own autoupdater hooks write.
#     The original used /tmp/autoupdate.lock, which nobody creates.
#   * Switchable per node like the rest: uci set hotfix.wifi_firmware.disabled=1
#
# Deliberately NOT in acts_immediately(): a node that has been up for days -
# the normal case - is rebooted about six minutes after the firmware dies,
# which is fast enough. Only within the first hour after a boot is the reboot
# held back, and that is exactly the window where a genuinely broken chip would
# otherwise put the node into a reboot loop every few minutes. Held back, the
# worst case becomes one reboot per hour instead, and the finding is in the log
# the whole time. A node that should react at once anyway:
#     uci set hotfix.wifi_firmware.immediate='1' ; uci commit hotfix
#
# Not mt7915-specific despite the original's name - the debugfs path is
# mt76-generic. On chips that do not export rf_regval (mt7603e, mt76x2e on a
# Xiaomi 4A Gigabit) nothing matches and the check does nothing, which is also
# why the original's `ls` guard was the only thing keeping that device from
# rebooting itself every two minutes.

HOTFIX_TAG='neanderfunk-hotfix'
. /lib/gluon/neanderfunk-hotfix/common.sh

CHECK='wifi_firmware'
MARKER="/tmp/hotfix.$CHECK"

check_disabled "$CHECK" && exit 0

# Below hotfix.settings.check_uptime_min nothing runs: right after a boot the
# firmware may not have finished loading, and this is the check that must not
# misread that as a crash.
checks_ok || exit 0

# Single instance, same idiom as healthcheck.sh. A read that hangs rather than
# failing would otherwise let runs pile up and count one fault several times.
if command -v flock >/dev/null 2>&1 ; then
	exec 200<"$0"
	if ! flock -n 200 ; then
		exit 0
	fi
fi

dead=''
for regval in /sys/kernel/debug/ieee80211/phy*/mt76/rf_regval ; do
	# no match leaves the pattern unexpanded, and debugfs need not be mounted
	[ -e "$regval" ] || continue
	phy="${regval#/sys/kernel/debug/ieee80211/}"
	phy="${phy%%/*}"
	if ! cat "$regval" > /dev/null 2>&1 ; then
		dead="${dead:+$dead }$phy"
	fi
done

if [ -z "$dead" ] ; then
	unstrike "$MARKER"
	exit 0
fi

n="$(strike "$MARKER")"
if [ "$n" -lt 2 ] ; then
	logger -s -t "$HOTFIX_TAG" -p 5 "[$CHECK] $dead: firmware register read failed (strike $n of 2)"
	exit 0
fi

unstrike "$MARKER"
now_reboot "[$CHECK] $dead: wifi firmware crashed, register read failed twice"

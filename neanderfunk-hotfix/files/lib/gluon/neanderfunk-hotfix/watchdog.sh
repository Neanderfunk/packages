#!/bin/sh
# Deadman watchdog for micrond itself.
#
# Every other check in this package runs from micrond - so if micrond dies
# (crash, OOM kill, or stopped and never restarted), nothing on the node would
# ever notice or reboot it again. This closes that hole:
#
# micrond starts this script every hotfix.settings.watchdog_interval_min
# minutes. Each new instance relieves its predecessor by killing it. An
# instance that is *not* relieved within 3x that interval concludes that no
# micrond is starting jobs any more, and reboots the node.
#
# Everything after the sleep is deliberately fork-free: the case this exists
# for includes running out of memory, where starting another process (logger,
# /sbin/reboot, date, uci) may simply fail. echo, read and kill are ash
# builtins, so the decision and the reboot need no fork at all - the reboot
# goes through /proc/sysrq-trigger ('s' = emergency sync, 'b' = reboot now).
#
# The autoupdater legitimately stops micrond while it downloads and flashes
# (see /usr/lib/autoupdater/download.d/10gluon-autoupdater). That must never be
# mistaken for a dead micrond, so the hooks in download.d/upgrade.d/abort.d of
# this package leave markers behind and this watchdog reads them:
#   /tmp/autoupdater-running   uptime (s) at which the download started
#   /tmp/autoupdater-flashing  set right before sysupgrade writes the flash
# While flashing, this never reboots - interrupting a flash write bricks the
# node. While downloading, it reboots only once the run has exceeded
# hotfix.settings.autoupdater_stale_min minutes, because then the updater is
# not making progress any more.

. /lib/gluon/neanderfunk-hotfix/common.sh

check_disabled watchdog && exit 0

PIDFILE=/tmp/hotfix-watchdog.pid
RUNMARK=/tmp/autoupdater-running
FLASHMARK=/tmp/autoupdater-flashing

# config is read once, up front, where forking is still fine
interval="$(uci -q get hotfix.settings.watchdog_interval_min)"
case "$interval" in ''|*[!0-9]*) interval=5 ;; esac
stale="$(uci -q get hotfix.settings.autoupdater_stale_min)"
case "$stale" in ''|*[!0-9]*) stale=300 ;; esac

deadline=$((interval * 3 * 60))
stale_s=$((stale * 60))

# relieve the predecessor
if [ -f "$PIDFILE" ] ; then
	read oldpid < "$PIDFILE"
	case "$oldpid" in
		''|*[!0-9]*) ;;
		*) [ "$oldpid" = "$$" ] || kill "$oldpid" 2>/dev/null ;;
	esac
fi
echo $$ > "$PIDFILE"

# fork-free from here on
reboot_now() {
	# best effort, still fork-free: /dev/kmsg shows up in logread
	echo "neanderfunk-hotfix: [watchdog] $1, rebooting via sysrq" > /dev/kmsg 2>/dev/null
	echo s > /proc/sysrq-trigger 2>/dev/null
	echo b > /proc/sysrq-trigger 2>/dev/null
	# only reached if sysrq is unavailable; then at least try the normal way
	reboot -f
}

while : ; do
	if ! sleep "$deadline" ; then
		# could not even fork sleep - that is the out-of-memory case this
		# watchdog is meant to survive, and waiting longer will not help
		reboot_now "unable to fork (out of memory?)"
	fi

	# still here: nobody relieved us, so micrond is not starting jobs any more

	# never interrupt a flash write
	[ -f "$FLASHMARK" ] && continue

	if [ -f "$RUNMARK" ] ; then
		read started < "$RUNMARK"
		read now rest < /proc/uptime
		now=${now%.*}
		case "$started" in ''|*[!0-9]*) started=$now ;; esac
		case "$now" in ''|*[!0-9]*) now=$started ;; esac
		# updater still within its allowance: keep watching, do not reboot
		[ $((now - started)) -lt "$stale_s" ] && continue
		reboot_now "autoupdater stuck for more than ${stale} min"
		# reboot_now only returns if neither sysrq nor /sbin/reboot worked
		# (e.g. no memory left to fork). Retry at the next deadline instead
		# of falling through to the branch below and logging a wrong reason.
		continue
	fi

	reboot_now "no micrond for more than $((deadline / 60)) min"
done

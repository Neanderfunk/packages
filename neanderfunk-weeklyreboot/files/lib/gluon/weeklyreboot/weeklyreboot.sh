#!/bin/sh
# Weekly reboot, spread over the small hours so the whole fleet does not come
# back at the same moment. Started by micrond, see /usr/lib/micron.d/weeklyreboot.

# tr -dc, not "sed 's/[^[:digit:]]//g'": sed works line by line and re-appends a
# newline after every line, and head -c counts bytes - so those newlines ate
# into the four characters. Measured on a node, the old pipeline drew values
# like "72\n0", "\n58", "6\n6", "08", "25". The delay was therefore heavily
# skewed towards very short values and a good share of the fleet rebooted within
# a minute of 03:15, which is the thundering herd this randomisation exists to
# prevent. tr has no line semantics and gave four digits in 50 of 50 draws,
# uniform over 0..9999 seconds (about 2h46).
#
# Not an entropy problem, so haveged does not enter into it: /dev/urandom is a
# CSPRNG and its bytes were always fine, the text processing mangled them.
DELAYTIME=$(tr -dc '0-9' < /dev/urandom | head -c4)
case "$DELAYTIME" in
	''|*[!0-9]*) DELAYTIME=3600 ;;
esac

logger -s -t "neanderfunk-weeklyreboot" -p 5 "scheduled reboot in $DELAYTIME seconds"
sleep "$DELAYTIME"
logger -s -t "neanderfunk-weeklyreboot" -p 5 "scheduled reboot in 5 seconds"
sleep 5

# Is an autoupdater run in flight?
#
# This guard used to test for /tmp/autoupdate.lock - a file nobody in the whole
# ecosystem creates, so it could never fire. Testing for the existence of the
# real lock would be just as wrong: /var/lock/autoupdater.lock stays behind
# after every run (it is sitting there on a node right now, 0 bytes), so the
# test would be permanently true and no weekly reboot would ever happen again.
# Only taking the lock answers the question.
#
# It matters more here than in the other checks: the sleep above runs for up to
# 2.7 hours, and a job micrond has already forked keeps running even after the
# autoupdater stops micrond before downloading. Rebooting into a running flash
# bricks the node.
# Two guards, because they cover different phases and neither needs another
# package installed:
#
#   flock   covers the download and verify phase for certain. The autoupdater
#           execs /sbin/sysupgrade rather than forking it (its binary carries
#           the string "failed to call sysupgrade", which is what one prints
#           after a failed exec), so whether the lock survives into the flash
#           depends on FD_CLOEXEC - not something to rely on.
#   pgrep   covers the flash itself regardless. sysupgrade is a shell script,
#           and busybox names such a process {sysupgrade}, so pgrep finds it -
#           checked on a node with a test script.
#
# Both fail safe: when in doubt this skips the reboot. A missed weekly reboot
# costs nothing, a reboot into a running flash bricks the node.
autoupdater_running() {
	if command -v flock >/dev/null 2>&1 ; then
		# exit 0 means the lock was free, so no autoupdater holds it
		flock -n /var/lock/autoupdater.lock true 2>/dev/null || return 0
	fi
	pgrep autoupdater >/dev/null 2>&1 && return 0
	pgrep sysupgrade  >/dev/null 2>&1 && return 0
	return 1
}

if autoupdater_running ; then
	logger -s -t "neanderfunk-weeklyreboot" -p 5 "autoupdater is running, skipping this week's reboot"
	exit 2
fi

reboot

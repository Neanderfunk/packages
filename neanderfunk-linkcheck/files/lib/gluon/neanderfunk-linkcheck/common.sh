#!/bin/sh
# Shared helpers for the neanderfunk-linkcheck checks. Sourced, not executed.
#
# Every single check can be switched off on a node:
#     uci set linkcheck.<check>.disabled='1' ; uci commit linkcheck
# The <check> name is part of the reason logged before a wifi restart or a
# reboot, so it can be read off `logread -f` while watching a node.
# `uci show linkcheck` lists the available names.
#
# How long after a boot no check may reboot (minutes, default 60):
#     uci set linkcheck.settings.reboot_uptime_min='90' ; uci commit linkcheck
# Presettable community-wide from the site.conf, see
# /lib/gluon/upgrade/500-neanderfunk-linkcheck and the README.
#
# These helpers are deliberately duplicated from neanderfunk-hotfix rather than
# shared: the two packages are independent and neither may need the other
# installed.

# true when the named check is switched off on this node
check_disabled() {
	if [ "$(uci -q get linkcheck."$1".disabled)" = "1" ] ; then
		return 0
	fi
	return 1
}

# true once the node is old enough for a check to ACT on what it found -
# reboot, wifi restart, any network reinit. Below this limit a check still
# runs and still logs; see no_action_yet(). Unset or non-numeric falls back to
# the 60 minutes this used to be hardcoded to.
uptime_ok() {
	local m
	m="$(uci -q get linkcheck.settings.reboot_uptime_min)"
	case "$m" in
		''|*[!0-9]*) m=60 ;;
	esac
	[ "$(sed 's/\..*//g' /proc/uptime)" -gt "$((m * 60))" ]
}

# Minimum uptime in seconds before a check may even run (minutes, default 5):
#     uci set linkcheck.settings.check_uptime_min='10' ; uci commit linkcheck
# Right after a boot the network is often not up yet; an anycast ping failing
# then is not a fault worth reporting. Below this limit nothing runs at all.
check_uptime_limit() {
	local m
	m="$(uci -q get linkcheck.settings.check_uptime_min)"
	case "$m" in
		''|*[!0-9]*) m=5 ;;
	esac
	echo $((m * 60))
}

# true once the node is old enough for the checks to run at all
checks_ok() {
	[ "$(sed 's/\..*//g' /proc/uptime)" -gt "$(check_uptime_limit)" ]
}

# reboot_uptime_limit in minutes, for log messages
reboot_uptime_min() {
	local m
	m="$(uci -q get linkcheck.settings.reboot_uptime_min)"
	case "$m" in
		''|*[!0-9]*) m=60 ;;
	esac
	echo "$m"
}

# Log that a check found something but is not acting on it yet. Between
# check_uptime_min and reboot_uptime_min the checks run and report, they just
# do not reboot or restart wifi.
no_action_yet() {
	# $1: the finding, already carrying its [check] tag
	logger -s -t "neanderfunk-linkcheck" -p 5 "$1 - no action taken, uptime below linkcheck.settings.reboot_uptime_min ($(reboot_uptime_min)min)"
}

# Count consecutive failures: strike <prefix> records one more and prints how
# many there are now. One marker file per strike rather than a single counter
# file on purpose - a counter file is truncated on every write, so being killed
# in that window resets the count to zero.
strike() {
	local n=1
	while [ -e "$1.$n" ] ; do n=$((n + 1)) ; done
	touch "$1.$n"
	echo "$n"
}

unstrike() {
	rm -f "$1".* 2>/dev/null
}

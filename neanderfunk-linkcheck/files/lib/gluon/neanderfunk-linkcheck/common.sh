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

# minimum uptime in seconds before a check may reboot; unset or non-numeric
# falls back to the 60 minutes this used to be hardcoded to
uptime_ok() {
	local m
	m="$(uci -q get linkcheck.settings.reboot_uptime_min)"
	case "$m" in
		''|*[!0-9]*) m=60 ;;
	esac
	[ "$(sed 's/\..*//g' /proc/uptime)" -gt "$((m * 60))" ]
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

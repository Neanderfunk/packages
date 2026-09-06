#!/bin/sh
# Shared helpers for the neanderfunk-hotfix checks. Sourced, not executed.
#
# Every single check can be switched off on a node:
#     uci set hotfix.<check>.disabled='1' ; uci commit hotfix
# The <check> name is part of the reason logged before a reboot or a wifi
# restart, so whoever watches a node with `logread -f` can read straight off
# the syslog which key to set if a check produces false positives for them.
# `uci show hotfix` lists all available check names.
#
# How long after a boot no check may reboot the node (minutes, default 60):
#     uci set hotfix.settings.reboot_uptime_min='90' ; uci commit hotfix
# It can be preset for the whole community from the site.conf, see
# /lib/gluon/upgrade/500-neanderfunk-hotfix and the package README.

# true when the named check is switched off on this node
check_disabled() {
	if [ "$(uci -q get hotfix."$1".disabled)" = "1" ] ; then
		return 0
	fi
	return 1
}

# minimum uptime in seconds before any check may reboot; anything unset or
# not a plain number falls back to the 60 minutes this used to be hardcoded to
reboot_uptime_limit() {
	local m
	m="$(uci -q get hotfix.settings.reboot_uptime_min)"
	case "$m" in
		''|*[!0-9]*) m=60 ;;
	esac
	echo $((m * 60))
}

# true once the node is old enough to be rebooted by a check
uptime_ok() {
	[ "$(sed 's/\..*//g' /proc/uptime)" -gt "$(reboot_uptime_limit)" ]
}

# Count consecutive failures. strike <prefix> records one more and prints how
# many there are now, so a check reads as
#     [ "$(strike /tmp/hotfix.gw-gone)" -ge 4 ] && reboot
# instead of a hand-written if/elif ladder over .1/.2/.3 marker files.
#
# One marker file per strike rather than a single counter file, on purpose: a
# counter file is truncated on every write, so being killed in that window
# resets the count to zero - exactly the failure that used to leave nodes stuck
# on the offline SSID in neanderfunk-ssid-changer. Losing one marker here only
# costs one round.
strike() {
	local n=1
	while [ -e "$1.$n" ] ; do n=$((n + 1)) ; done
	touch "$1.$n"
	echo "$n"
}

# forget all strikes recorded under this prefix
unstrike() {
	rm -f "$1".* 2>/dev/null
}

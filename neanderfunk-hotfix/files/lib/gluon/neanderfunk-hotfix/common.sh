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

# true once the node is old enough for a check to ACT on what it found -
# reboot, wifi restart, any network reinit. A check below this limit still
# runs and still logs; see no_action_yet().
uptime_ok() {
	[ "$(sed 's/\..*//g' /proc/uptime)" -gt "$(reboot_uptime_limit)" ]
}

# Minimum uptime in seconds before a check may even run (minutes, default 5):
#     uci set hotfix.settings.check_uptime_min='10' ; uci commit hotfix
# Right after a boot the network is often not up yet, and a check firing then
# would only report a problem that is not one. Below this limit nothing runs
# and nothing is logged.
check_uptime_limit() {
	local m
	m="$(uci -q get hotfix.settings.check_uptime_min)"
	case "$m" in
		''|*[!0-9]*) m=5 ;;
	esac
	echo $((m * 60))
}

# true once the node is old enough for the checks to run at all
checks_ok() {
	[ "$(sed 's/\..*//g' /proc/uptime)" -gt "$(check_uptime_limit)" ]
}

# Log that a check found something but is not acting on it yet. Between
# check_uptime_min and reboot_uptime_min the checks run and report, they just
# do not reboot, restart wifi or otherwise touch the network - so whoever
# watches `logread -f` right after a boot sees the finding without the node
# acting on a network that is still settling.
no_action_yet() {
	# $1: the finding, already carrying its [check] tag
	logger -s -t "neanderfunk-hotfix" -p 5 "$1 - no action taken, uptime below hotfix.settings.reboot_uptime_min ($(($(reboot_uptime_limit) / 60))min)"
}

# Some faults must not wait out reboot_uptime_min. A check listed here acts as
# soon as it fires, whatever the uptime:
#
#   kernel_bug  "Kernel bug detected" is a BUG()/oops. gluon#680 reports that
#               afterwards "any invocation of ip, ifconfig, brctl, batctl etc
#               will result in a stuck system" - there is no self-recovery and
#               no remedy short of a reboot. Worse for us: our own other checks
#               shell out to exactly those tools, so a node in this state may
#               not even manage to report anything. Holding it for an hour buys
#               nothing and costs an hour of a dead node.
#
# Everything else deliberately keeps the hold-off:
#   ath_malloc, ksoftirqd_malloc  can be a transient OOM *during boot* on small
#               devices (openwrt forum on "ath: skbuff alloc of size ... failed":
#               "could be OOM during peak mem consumption while booting, but it
#               may look ok later on"). Acting at once would reboot-loop a
#               32 MiB node at every boot. Both also recur - the freifunk forum
#               reports page allocation failures every 5 to 10 seconds - so a
#               delayed reaction still fires, and the node limps rather than
#               dying outright.
#   load        right after a boot the load is legitimately high, and the 5
#               minute average is not meaningful before the node has been up
#               5 minutes at all.
#
# Per node this can be changed in either direction:
#     uci set hotfix.load.immediate='1'      ; uci commit hotfix
#     uci set hotfix.kernel_bug.immediate='0' ; uci commit hotfix
acts_immediately() {
	local v
	v="$(uci -q get hotfix."$1".immediate)"
	case "$v" in
		1) return 0 ;;
		0) return 1 ;;
	esac
	case "$1" in
		kernel_bug) return 0 ;;
	esac
	return 1
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

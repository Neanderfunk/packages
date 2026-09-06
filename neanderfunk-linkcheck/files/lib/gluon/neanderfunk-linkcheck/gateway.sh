#!/bin/sh
# Is this node still reaching the rest of the network?
#
# Two independent checks, both only armed once the node has seen the thing
# working at least once since boot - a node that never had a gateway must not
# reboot over it. Both escalate over four checks (*/8, so roughly half an hour)
# before rebooting, and neither reboots within the first
# linkcheck.settings.reboot_uptime_min minutes of uptime.
#
# This lived in neanderfunk-hotfix as rebootIfNoGw.sh. It is a "does the
# network still work" question, not a "is this node healthy" one, so it belongs
# here with the other link checks. It brings its own helpers rather than reusing
# anything from hotfix: the two packages stay independent of each other.

. /lib/gluon/neanderfunk-linkcheck/common.sh

upgrade_started='/tmp/autoupdate.lock'
[ -f $upgrade_started ] && exit

reboot_if_old() {
	# $1: check name for the log, $2: reason
	logger -s -t "neanderfunk-linkcheck" -p 5 "[$1] $2, rebooting"
	uptime_ok || return 0
	sync
	reboot -f
}

# --- batman gateway ---------------------------------------------------------
# `batctl gwl -H` lists the gateways without the header lines, so empty output
# means none is in range. This used to grep batctl's output for "No gateways in
# range", a message current batctl does not contain at all, so the check never
# fired.
if ! check_disabled no_gateway && [ -z "$(batctl gwl -H 2>/dev/null)" ] ; then
	if [ -f /tmp/linkcheck.gw-seen ] && [ "$(strike /tmp/linkcheck.gw-gone)" -ge 4 ] ; then
		reboot_if_old no_gateway "no batman gateway for 4 checks"
	fi
else
	touch /tmp/linkcheck.gw-seen
	unstrike /tmp/linkcheck.gw-gone
fi

# --- IPv6 anycast -----------------------------------------------------------
returnval=0
ipv6_subnet="$(ip -6 -o addr show dev br-client | head -1 | awk -v N=4 '{print $N}' | sed -e 's/\/64//' | cut -d":" -f1-4)"
if [ ! -z "$ipv6_subnet" ]; then
	ping6 "${ipv6_subnet}::ac1" -c 10 >/dev/null 2>&1
	returnval="$?"
fi

if ! check_disabled ipv6_anycast && { [ "$returnval" -ne 0 ] || [ -z "$ipv6_subnet" ]; } ; then
	if [ -f /tmp/linkcheck.ip6anycast-seen ] ; then
		logger -s -t "neanderfunk-linkcheck" -p 5 "[ipv6_anycast] IPv6 anycast address not reachable"
		if [ "$(strike /tmp/linkcheck.ip6anycast-gone)" -ge 4 ] ; then
			reboot_if_old ipv6_anycast "IPv6 anycast unreachable for 4 checks"
		fi
	fi
else
	touch /tmp/linkcheck.ip6anycast-seen
	unstrike /tmp/linkcheck.ip6anycast-gone
fi

exit 0

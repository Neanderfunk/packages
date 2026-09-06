#!/bin/sh
# check_disabled(), uptime_ok() - see common.sh for the uci keys
# (hotfix.<check>.disabled, hotfix.settings.reboot_uptime_min). uptime_ok keeps
# a node that cannot reach a gateway at all from ending up in a tight reboot
# loop; the escalation below keeps counting either way, so the reboot happens
# as soon as the node is old enough.
. /lib/gluon/neanderfunk-hotfix/common.sh

upgrade_started='/tmp/autoupdate.lock'

[ -f $upgrade_started ] && exit

# `batctl gwl -H` lists the gateways without the header lines, so empty output
# means no gateway is in range. This used to grep batctl's output for
# "No gateways in range" - a message current batctl does not contain at all
# (checked with strings on batctl 2023.1), so the match never succeeded, the
# else branch always ran, and this script never rebooted for a missing gateway.
if ! check_disabled no_gateway && [ -z "$(batctl gwl -H 2>/dev/null)" ] ; then
  # only escalate on a node that has seen a gateway at least once since boot
  if [ -f /tmp/hotfix.gw-seen ] && [ "$(strike /tmp/hotfix.gw-gone)" -ge 4 ] ; then
    [ -f $upgrade_started ] && exit
    logger -s -t "neanderfunk-hotfix" -p 5 "[no_gateway] no batman gateway for 4 checks, rebooting"
    uptime_ok && securereboot
  fi
else
  touch /tmp/hotfix.gw-seen
  unstrike /tmp/hotfix.gw-gone
fi

returnval=0
ipv6_subnet="$(ip -6 -o addr show dev br-client| head -1 |awk -v N=4 '{print $N}'|sed -e 's/\/64//'|cut -d":" -f1-4)"
if [ ! -z "$ipv6_subnet" ]; then
  ipv6_anycast="${ipv6_subnet}::ac1"
  ping6 "$ipv6_anycast" -c 10 >/dev/null 2>&1
  returnval="$?"
fi
if ! check_disabled ipv6_anycast && { [ "$returnval" -ne 0 ] || [ -z "$ipv6_subnet" ]; }; then
  if [ -f /tmp/hotfix.ip6anycast-seen ] ; then
    logger "[ipv6_anycast] IPv6 Anycast-IP NOT reachable."
    if [ "$(strike /tmp/hotfix.ip6anycast-gone)" -ge 4 ] ; then
      [ -f $upgrade_started ] && exit
      uptime_ok && securereboot
      exit 0
    fi
  fi
else
  logger "IPv6 Anycast-IP reachable."
  touch /tmp/hotfix.ip6anycast-seen
  unstrike /tmp/hotfix.ip6anycast-gone
fi

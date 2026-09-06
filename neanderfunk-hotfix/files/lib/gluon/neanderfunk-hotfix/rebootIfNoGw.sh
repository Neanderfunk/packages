#!/bin/sh
upgrade_started='/tmp/autoupdate.lock'

[ -f $upgrade_started ] && exit

# No reboot within the first hour of uptime - same policy as healthcheck.sh, so
# a node that cannot reach a gateway at all does not end up in a tight reboot
# loop. The escalation below keeps counting either way, so the reboot happens as
# soon as the node is old enough.
uptime_ok() {
  [ "$(sed 's/\..*//g' /proc/uptime)" -gt "3600" ]
}

# `batctl gwl -H` lists the gateways without the header lines, so empty output
# means no gateway is in range. This used to grep batctl's output for
# "No gateways in range" - a message current batctl does not contain at all
# (checked with strings on batctl 2023.1), so the match never succeeded, the
# else branch always ran, and this script never rebooted for a missing gateway.
if [ -z "$(batctl gwl -H 2>/dev/null)" ] ; then
  if [ -f /tmp/gw ] ; then
    if [ -f /tmp/gwgone.3 ] ; then
      [ -f $upgrade_started ] && exit
      logger -s -t "neanderfunk-hotfix" -p 5 "no batman gateway for 4 checks, rebooting"
      uptime_ok && securereboot
    elif [ -f /tmp/gwgone.2 ] ; then
      touch /tmp/gwgone.3
    elif [ -f /tmp/gwgone.1 ] ; then
      touch /tmp/gwgone.2
    else
      touch /tmp/gwgone.1
    fi
  fi
else
  touch /tmp/gw
  rm -f /tmp/gwgone.* 2>/dev/null
fi

returnval=0
ipv6_subnet="$(ip -6 -o addr show dev br-client| head -1 |awk -v N=4 '{print $N}'|sed -e 's/\/64//'|cut -d":" -f1-4)"
if [ ! -z "$ipv6_subnet" ]; then
  ipv6_anycast="${ipv6_subnet}::ac1"
  ping6 "$ipv6_anycast" -c 10 >/dev/null 2>&1
  returnval="$?"
fi
if [ "$returnval" -ne 0 ] || [ -z "$ipv6_subnet" ]; then
  if [ -f /tmp/ip6anycast ] ; then
    logger "IPv6 Anycast-IP NOT reachable."
    if [ -f /tmp/ip6anycastgone.3 ] ; then
      [ -f $upgrade_started ] && exit
      uptime_ok && securereboot
      exit 0
    elif [ -f /tmp/ip6anycastgone.2 ] ; then
      touch /tmp/ip6anycastgone.3
    elif [ -f /tmp/ip6anycastgone.1 ] ; then
      touch /tmp/ip6anycastgone.2
    else
      touch /tmp/ip6anycastgone.1
    fi
  fi
else
  logger "IPv6 Anycast-IP reachable."
  touch /tmp/ip6anycast
  rm -f /tmp/ip6anycastgone.* 2>/dev/null
fi

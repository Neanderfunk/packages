#!/bin/sh
# Reboot if the ::ac1 anycast address in the client prefix has not answered
# for four runs in a row (every 8 min), once it had answered since boot.
# Removed 2026-10 (Sackgasse 2021.1): the gateway ladder on "No gateways in
# range" (batctl 2019.2 no longer prints that text, it never fired; the ::ac1
# ping covers the case) and the log line on every successful run.
flock -n /var/lock/autoupdater.lock true || exit 0

ipv6_subnet="$(ip -6 -o addr show dev br-client| head -1 |awk -v N=4 '{print $N}'|sed -e 's/\/64//'|cut -d":" -f1-4)"
returnval=1
if [ -n "$ipv6_subnet" ]; then
  ping6 "${ipv6_subnet}::ac1" -c 10 >/dev/null 2>&1
  returnval="$?"
fi
if [ "$returnval" -ne 0 ]; then
  if [ -f /tmp/ip6anycast ] ; then
    logger -t eulenfunk-rebootifnogw "IPv6 Anycast-IP NOT reachable."
    if [ -f /tmp/ip6anycastgone.3 ] ; then
      securereboot
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
  touch /tmp/ip6anycast
  rm -f /tmp/ip6anycastgone.* 2>/dev/null
fi

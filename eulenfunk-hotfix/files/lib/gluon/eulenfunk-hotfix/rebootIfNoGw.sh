#!/bin/sh
# Every 8 min. Reboot after four runs in a row without
# - any batman gateway, once one was seen since boot, or
# - an answer from <public client prefix>::ac1, once it answered since boot.
# Nothing the first hour after boot.
# Sackgasse 2021.1, repairs backported from neanderfunk-linkcheck gateway.sh
# (v2025.1.x):
# - the gateway check looked for the text "No gateways in range", which
#   batctl 2019.2 no longer prints, so it never fired; now an empty
#   "batctl gwl -H" means no gateway
# - the anycast ping took the first address on br-client, which can be the
#   ULA; now only public prefixes are tried, each until one answers
# - no log line on every successful run, failures with a tag

. /lib/gluon/eulenfunk-hotfix/common.sh

autoupdater_busy && exit 0
exec 200<"$0"
flock -n 200 || exit 0

reboot_if_old() {
  if [ "$(uptime_s)" -le 3600 ] ; then
    logger -t eulenfunk-rebootifnogw -p 5 "$1 - no action taken during the first hour"
    return 0
  fi
  logger -t eulenfunk-rebootifnogw -p 5 "$1, rebooting"
  securereboot
  exit 0
}

if [ -z "$(batctl gwl -H 2>/dev/null)" ] ; then
  if [ -f /tmp/hotfix.gw-seen ] ; then
    logger -t eulenfunk-rebootifnogw -p 5 "no batman gateway"
    [ "$(strike /tmp/hotfix.gw-gone)" -ge 4 ] && reboot_if_old "no batman gateway for 4 checks"
  fi
else
  : > /tmp/hotfix.gw-seen
  unstrike /tmp/hotfix.gw-gone
fi

prefixes="$(ip -6 -o addr show dev br-client scope global 2>/dev/null \
  | awk '{ split($4, a, "/"); p = tolower(a[1]); if (p ~ /^f[cd]/) next;
    split(a[1], g, ":"); x = g[1] ":" g[2] ":" g[3] ":" g[4];
    if (!seen[x]++) print x }')"
ok=''
for pfx in $prefixes ; do
  if ping6 "${pfx}::ac1" -c 10 -w 15 >/dev/null 2>&1 ; then
    ok=1
    break
  fi
done
if [ -z "$ok" ] ; then
  if [ -f /tmp/ip6anycast ] ; then
    logger -t eulenfunk-rebootifnogw -p 5 "IPv6 Anycast-IP NOT reachable."
    [ "$(strike /tmp/ip6anycastgone)" -ge 4 ] && reboot_if_old "IPv6 anycast unreachable for 4 checks"
  fi
else
  touch /tmp/ip6anycast
  unstrike /tmp/ip6anycastgone
fi

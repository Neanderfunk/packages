#!/bin/sh
# Every 15 min: if wifi clients had been there since boot and none has been
# associated for four runs in a row, restart wifi (not in the first hour).
# Sackgasse 2021.1, repairs backported from neanderfunk-hotfix (v2025.1.x):
# C_MACs typo (only the last interface counted), ethernet ports of br-client
# no longer queried, shared wifi lock, nothing during the first hour.

. /lib/gluon/eulenfunk-hotfix/common.sh

autoupdater_busy && exit 0

cliifs=$(/usr/sbin/brctl show | sed -n -e '/^br-client[[:space:]]/,/^\S/ { /^\(br-client[[:space:]]\|\t\)/s/^.*\t//p }' | grep -v "bat0\|eth\|local-port" | tr '\n' ' ')

APoff=1
for r in 0 1 2; do
  if uci -q get wireless.radio$r >/dev/null ; then
    [ "$(uci -q get wireless.radio$r.disabled)" = 1 ] && continue
    [ "$(uci -q get wireless.client_radio$r.disabled)" = 1 ] && continue
    APoff=0
  fi
done
[ "$APoff" -eq "1" ] && exit 0

C_MACS=""
for if in $cliifs; do
  C_MACS=${C_MACS}$(iw dev $if station dump | grep ^Station | cut -d ' ' -f 2)
done

if [ -z "$C_MACS" ] ; then
  if [ -f /tmp/WifiClients ] && [ "$(strike /tmp/NoWiCli)" -ge 4 ] ; then
    if [ "$(uptime_s)" -le 3600 ] ; then
      logger -t "hotfix-IfNoWificlient" -p 5 "wireless stations disappeared for long - no action during the first hour"
      exit 0
    fi
    if ! wifi_lock ; then
      logger -t "hotfix-IfNoWificlient" -p 5 "wireless stations disappeared for long, but another check is already restarting wifi"
      exit 0
    fi
    logger -s -t "hotfix-IfNoWificlient" -p 5 "wireless stations disappeared for long, restarting Wifi"
    rm -f /tmp/WifiClients 2>/dev/null
    unstrike /tmp/NoWiCli
    wifi down
    killall hostapd >/dev/null 2>&1
    rm -f /var/run/wifi-*.pid >/dev/null 2>&1
    wifi config
    wifi up
    wifi_unlock
  fi
else
  touch /tmp/WifiClients
  unstrike /tmp/NoWiCli
fi

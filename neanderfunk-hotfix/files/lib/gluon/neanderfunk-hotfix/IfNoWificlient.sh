#!/bin/sh
# check_disabled() - see common.sh (uci key hotfix.no_wifi_clients.disabled)
. /lib/gluon/neanderfunk-hotfix/common.sh

upgrade_started='/tmp/autoupdate.lock'

[ -f $upgrade_started ] && exit
check_disabled no_wifi_clients && exit 0

cliifs=$(/usr/sbin/brctl show | sed -n -e '/^br-client[[:space:]]/,/^\S/ { /^\(br-client[[:space:]]\|\t\)/s/^.*\t//p }' | grep -v "bat0\|eth\|local-port" | tr '\n' ' ')

APoff=1
for r in 0 1 2; do
  if uci get wireless.radio$r &>/dev/null ; then
    roff=$(uci get wireless.radio$r.disabled 2>/dev/null)
    if [ -z $roff ] || [ ! "$roff" -eq "1" ] ; then
      coff=$(uci get wireless.client_radio$r.disabled 2>/dev/null);
      if [ -z $coff ] || [ ! "$coff" -eq "1" ] ; then
        APoff=0
       fi
     fi
   fi
 done

[ "$APoff" -eq "1" ] && exit 0
C_MACS=""
for if in $cliifs; do
  # NB: ${C_MACS}, not ${C_MACs} - with the typo this overwrote instead of
  # appending, so only the last interface counted. A node with clients on
  # 2.4GHz but none on 5GHz then looked client-less and got its wifi
  # restarted (kicking the clients it did have) after 4 rounds.
  C_MACS=${C_MACS}$(iw dev $if station dump | grep ^Station | cut -d ' ' -f 2)
 done

if [ -z "$C_MACS" ] ; then
  # only escalate on a node that has seen clients at least once since boot
  if [ -f /tmp/WifiClients ] && [ "$(strike /tmp/NoWiCli)" -ge 4 ] ; then
    [ -f $upgrade_started ] && exit
    logger -s -t "hotfix-IfNoWificlient" -p 5 "[no_wifi_clients] wireless stations disappeared for long, restarting Wifi"
    rm -f /tmp/WifiClients 2>/dev/null
    unstrike /tmp/NoWiCli
    wifi down
    killall hostapd >/dev/null 2>&1
    rm -f /var/run/wifi-*.pid >/dev/null 2>&1
    wifi config
    wifi up
  fi
else
  touch /tmp/WifiClients
  unstrike /tmp/NoWiCli
fi


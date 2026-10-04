#!/bin/sh
# Called per hostapd process with its ps line as arguments
# ("<pid> <user> <vsz> <stat> /usr/sbin/hostapd -s -P ... -B /var/run/hostapd-phyN.conf").
# Restarts wifi if the AP interface of that phy is in master mode but has no
# channel, three runs in a row.
# Removed 2026-10 (Sackgasse 2021.1), both never had an effect:
# - pid file vs. ps pid: busybox ps pads the pid, the comparison failed for
#   pids below 10000; above, it restarted only when a second look matched
# - "up: false" in wifi status: never matched the ubus JSON
restart_wifi() {
  logger -s -t "eulenfunk-checkhostapd" "wifi hard restart"
  wifi down
  killall hostapd 2>/dev/null
  rm -f /tmp/hostapd.*.core 2>/dev/null
  rm -f /var/run/wifi-*.pid 2>/dev/null
  wifi config
  wifi up
  sleep 60
}

phy=$(echo "$@" | sed 's/.*-B\ //g' | cut -d" " -f1 | sed 's/.*hostapd-//g' | cut -d"." -f1)
case "$phy" in phy[0-9]*) ;; *) exit 0 ;; esac
client="client${phy#phy}"
sema="/tmp/channelunknown"
iwstat=$(iwinfo $client info)
if echo "$iwstat" | grep -qi "Mode: Master" ; then
  if echo "$iwstat" | grep -qi "Channel: unknown" ; then
    if [ -f $sema.fail.$client.2 ] ; then
      logger -s -t "eulenfunk-healthcheck" "channel $client unknown"
      restart_wifi
      rm -f $sema.fail.$client.* $sema.ok.$client.* 2>/dev/null
    elif [ -f $sema.fail.$client.1 ] ; then
      touch $sema.fail.$client.2
    else
      touch $sema.fail.$client.1
      rm -f $sema.ok.$client.* 2>/dev/null
    fi
  else
    rm -f $sema.fail.$client.* 2>/dev/null
    touch $sema.ok.$client
  fi
fi

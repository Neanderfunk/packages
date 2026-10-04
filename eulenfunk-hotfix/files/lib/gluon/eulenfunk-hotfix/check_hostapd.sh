#!/bin/sh
# Called per hostapd process with its ps line as arguments
# ("<pid> <user> <vsz> <stat> /usr/sbin/hostapd -s -P /var/run/wifi-phyN.pid ...").
# Two checks per phy, each acting after three runs in a row:
# - radio down and pending in "wifi status" -> wifi restart
# - AP interface in master mode without a channel -> wifi restart
# Sackgasse 2021.1, repairs backported from neanderfunk-hotfix (v2025.1.x):
# - the phy comes from the pid file name: without a terminal busybox ps cuts
#   lines at 80 columns and the -B argument the old code parsed was cut to
#   "-B /v", so nothing here ever ran in the field (found 2026-10-04, WR841N v9)
# - "up: false" never matched the wifi status JSON; read via jsonfilter
# - one wifi restart at a time across all checks (lock), and at most one per
#   30 min from here (hotfix.settings.hostapd_cooldown_min)
# Not backported: the BSS status check via "ubus call hostapd.<if>
# get_status" - hostapd in OpenWrt 19.07 has no get_status. The old pid file
# comparison is gone for good (it restarted when a second look matched).

. /lib/gluon/eulenfunk-hotfix/common.sh

RESTART_MARKER='/tmp/hotfix.hostapd.last-restart'
restart_wifi() {
  local cooldown last
  cooldown="$(uci -q get hotfix.settings.hostapd_cooldown_min)"
  case "$cooldown" in ''|*[!0-9]*) cooldown=30 ;; esac
  last="$(cat "$RESTART_MARKER" 2>/dev/null)"
  case "$last" in ''|*[!0-9]*) last='' ;; esac
  if [ -n "$last" ] && [ $(( ($(uptime_s) - last) / 60 )) -lt "$cooldown" ] ; then
    logger -t "eulenfunk-checkhostapd" -p 5 "wifi restart skipped, last one less than ${cooldown}min ago"
    return 1
  fi
  if ! wifi_lock ; then
    logger -t "eulenfunk-checkhostapd" -p 5 "wifi restart skipped, another check is already restarting wifi"
    return 1
  fi
  uptime_s > "$RESTART_MARKER"
  logger -s -t "eulenfunk-checkhostapd" "wifi hard restart"
  wifi down
  killall hostapd 2>/dev/null
  rm -f /tmp/hostapd.*.core 2>/dev/null
  rm -f /var/run/wifi-*.pid 2>/dev/null
  wifi config
  wifi up
  wifi_unlock
  sleep 60
  return 0
}

phy=$(echo "$@" | grep -o 'wifi-phy[0-9]*' | head -n1 | sed 's/^wifi-//')
case "$phy" in phy[0-9]*) ;; *) exit 0 ;; esac
radio="radio${phy#phy}"
client="client${phy#phy}"

rup='' ; pending=''
eval "$(jsonfilter -s "$(wifi status 2>/dev/null)" -e "rup=@[\"$radio\"].up" -e "pending=@[\"$radio\"].pending" 2>/dev/null)"
sema="/tmp/hotfix.wifipending"
if [ "$rup" = "0" ] && [ "$pending" = "1" ] ; then
  if [ "$(strike $sema.$radio)" -ge 3 ] ; then
    logger -s -t "eulenfunk-healthcheck" "hostapd down and pending on $radio"
    restart_wifi && unstrike $sema.$radio
  fi
else
  unstrike $sema.$radio
fi

sema="/tmp/channelunknown"
iwstat=$(iwinfo $client info)
if echo "$iwstat" | grep -qi "Mode: Master" ; then
  if echo "$iwstat" | grep -qi "Channel: unknown" ; then
    if [ -f $sema.fail.$client.2 ] ; then
      logger -s -t "eulenfunk-healthcheck" "channel $client unknown"
      restart_wifi && rm -f $sema.fail.$client.* $sema.ok.$client.* 2>/dev/null
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

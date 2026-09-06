#!/bin/sh
# check_hostapd for matching pids
# strike()/unstrike() count consecutive failures, see common.sh
. /lib/gluon/neanderfunk-hotfix/common.sh
restart_wifi() {
  logger -s -t "neanderfunk-checkhostapd" "wifi hard restart"
  wifi down
  killall hostapd 2>/dev/null
  rm -f /tmp/hostapd.*.core 2>/dev/null
  rm -f /var/run/wifi-*.pid 2>/dev/null
  wifi config
  wifi up
  sleep 60
}

pspid="$1"
phy=$(echo $@|sed 's/.*-B\ //g'|cut -d" " -f1|sed 's/.*hostapd-//g'|cut -d"." -f1)
if [ "${phy:0:3}" = "phy" ] ; then
  pidfile=$(echo $@|sed 's/.*-P\ //g'|cut -d" " -f1)
  pid=$(cat $pidfile 2>/dev/null)
  sema="/tmp/hotfix.hostapdpid"
  if [ "$pid" = "${pspid%% *}" ] ; then
    rm -f $sema.fail.$phy 2>/dev/null
    touch $sema.ok.$phy
  else
    touch $sema.fail.$phy
    rm -f $sema.ok.$phy 2>/dev/null
    pspid=$(ps|grep hostapd|grep $phy)
    pid=$(cat $pidfile 2>/dev/null)
    if [ "$pid" = "${pspid%% *}" ] ; then
      logger -s -t "neanderfunk-healthcheck" "hostapd restart due to nonmatchings pids on $phy"
      restart_wifi
      rm -f $sema.fail.$phy 2>/dev/null
      sleep 10
    fi
  fi
  wifistatus=$(wifi status)
  radio="radio"${phy:3:1}
  sema="/tmp/hotfix.wifipending"
  if [ $(echo $wifistatus|grep -A 6 $radio|cut -d":" -f1-10|grep -c "up: false") -eq 1 ] ; then
    if [ $(echo $wifistatus|grep -A 6 $radio|cut -d":" -f1-10|grep -c "pending: true") -eq 1 ] ; then
      rm -f $sema.ok.$radio.* 2>/dev/null
      if [ "$(strike $sema.fail.$radio)" -ge 3 ] ; then
        logger -s -t "neanderfunk-healthcheck" "[hostapd_pids] hostapd down and pending on $radio"
        restart_wifi
        unstrike $sema.fail.$radio
      fi
    else
      unstrike $sema.fail.$radio
      touch $sema.ok.$radio
    fi
  fi
  client="client"${phy:3:1}
  sema="/tmp/hotfix.channelunknown"
  iwstat=$(iwinfo $client info)
  if [ $(echo $iwstat|grep -i "Mode: Master"|wc -l) -eq 1 ] ; then
    if [ $(echo $iwstat|grep -i "Channel: unknown"|wc -l) -eq 1 ] ; then
      rm -f $sema.ok.$client.* 2>/dev/null
      if [ "$(strike $sema.fail.$client)" -ge 3 ] ; then
        logger -s -t "neanderfunk-healthcheck" "[hostapd_pids] channel $client unknown"
        restart_wifi
        unstrike $sema.fail.$client
      fi
    else
      unstrike $sema.fail.$client
      touch $sema.ok.$client
    fi
  fi
fi


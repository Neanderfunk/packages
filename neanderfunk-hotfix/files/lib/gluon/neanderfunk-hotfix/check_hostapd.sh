#!/bin/sh
# check_hostapd for matching pids
# strike()/unstrike() count consecutive failures, see common.sh
. /lib/gluon/neanderfunk-hotfix/common.sh
# Rueckgabe 0 nur bei tatsaechlichem Neustart - der Aufrufer setzt danach
# Semaphor-Dateien, und die duerfen nicht behaupten, es sei etwas geschehen.
restart_wifi() {
  # gemeinsame Sperre, siehe common.sh
  if ! wifi_lock ; then
    logger -s -t "neanderfunk-checkhostapd" -p 5 "wifi restart skipped, another check is already restarting wifi"
    return 1
  fi
  logger -s -t "neanderfunk-checkhostapd" "wifi hard restart"
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
      if restart_wifi ; then
        rm -f $sema.fail.$phy 2>/dev/null
        sleep 10
      fi
    fi
  fi
  # printf statt echo $var: "wifi status" liefert JSON ueber viele Zeilen (auf
  # den Testknoten 63 bzw. 125), und unquotiert macht die Wortzerlegung daraus
  # EINE Zeile. Damit war das "grep -A 6 $radio" wirkungslos - es gibt ja nur
  # eine Zeile - und "grep -c up: false" haette fuer jedes Radio angeschlagen,
  # sobald irgendeines unten ist. Der Block soll aber genau das Radio treffen,
  # um das es gerade geht.
  wifistatus=$(wifi status)
  radio="radio"${phy:3:1}
  sema="/tmp/hotfix.wifipending"
  radiostatus=$(printf '%s\n' "$wifistatus" | grep -A 6 "$radio")
  if [ "$(printf '%s\n' "$radiostatus" | grep -c "up: false")" -ge 1 ] ; then
    if [ "$(printf '%s\n' "$radiostatus" | grep -c "pending: true")" -ge 1 ] ; then
      rm -f $sema.ok.$radio.* 2>/dev/null
      if [ "$(strike $sema.fail.$radio)" -ge 3 ] ; then
        logger -s -t "neanderfunk-healthcheck" "[hostapd_pids] hostapd down and pending on $radio"
        # nur aufraeumen, wenn wirklich neu gestartet wurde
        restart_wifi && unstrike $sema.fail.$radio
      fi
    else
      unstrike $sema.fail.$radio
      touch $sema.ok.$radio
    fi
  fi
  client="client"${phy:3:1}
  sema="/tmp/hotfix.channelunknown"
  iwstat=$(iwinfo $client info)
  if [ "$(printf '%s\n' "$iwstat" | grep -ci "Mode: Master")" -ge 1 ] ; then
    if [ "$(printf '%s\n' "$iwstat" | grep -ci "Channel: unknown")" -ge 1 ] ; then
      rm -f $sema.ok.$client.* 2>/dev/null
      if [ "$(strike $sema.fail.$client)" -ge 3 ] ; then
        logger -s -t "neanderfunk-healthcheck" "[hostapd_pids] channel $client unknown"
        restart_wifi && unstrike $sema.fail.$client
      fi
    else
      unstrike $sema.fail.$client
      touch $sema.ok.$client
    fi
  fi
fi


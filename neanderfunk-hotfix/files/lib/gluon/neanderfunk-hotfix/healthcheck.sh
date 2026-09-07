#!/bin/sh
# cc0, maintained by adorfer@nadeshda.org 

# check_disabled(), uptime_ok(), reboot_uptime_limit(), now_reboot(),
# safety_exit() - see common.sh for the uci keys (hotfix.<check>.disabled,
# hotfix.settings.reboot_uptime_min)
#
# Keep the tag this script has always logged under, so anything watching the
# syslog for "neanderfunk-healthcheck" keeps working.
HOTFIX_TAG='neanderfunk-healthcheck'
. /lib/gluon/neanderfunk-hotfix/common.sh

# wait 60 minutes if autoupdater is running
UPDATEWAIT='60'

# Rueckgabe: 0 nur, wenn wirklich neu gestartet wurde. Der Aufrufer darf
# seinen Zustand (Strikes) nur dann aufraeumen - sonst faellt die Stoerung
# unter den Tisch, weil sie als erledigt gilt, ohne dass etwas geschah.
restart_wifi() {
  # same rule as now_reboot: report below the action threshold, do not act
  if ! uptime_ok ; then
    no_action_yet "[wifi] wifi restart wanted"
    return 1
  fi
  # gemeinsame Sperre, siehe common.sh: sieben Stellen koennen das WLAN
  # anfassen, und ineinanderlaufende Neustarts sind schlimmer als ein
  # ausgelassener - der naechste Lauf holt ihn nach.
  if ! wifi_lock ; then
    logger -s -t "neanderfunk-healthcheck" -p 5 "wifi restart skipped, another check is already restarting wifi"
    return 1
  fi
  logger -s -t "neanderfunk-healthcheck" "wifi hard restart"
  wifi down
  killall hostapd 2>/dev/null
  rm -f /tmp/hostapd.*.core 2>/dev/null
  rm -f /var/run/wifi-*.pid 2>/dev/null
  wifi config
  wifi up
  wifi_unlock
  return 0
}


# Two thresholds, deliberately separate:
#   below hotfix.settings.check_uptime_min (default 5 min) nothing runs at all -
#     the network is still coming up and any finding would be noise;
#   below hotfix.settings.reboot_uptime_min (default 60 min) the checks run and
#     report what they find, but nothing reboots or restarts wifi. That way
#     someone watching `logread -f` right after a boot sees the finding without
#     the node acting on a network that has not settled yet.
checks_ok || exit 0

# Einzelinstanz-Lock. Dieses Skript kann laenger laufen als sein Cron-Intervall:
# reboot_when_not_running schlaeft zweimal 20 Sekunden, ein WLAN-Neustart
# weitere 10. Ohne Lock
# startet micrond den naechsten Lauf trotzdem, und zwei gleichzeitige Laeufe
# zaehlen dieselbe Stoerung doppelt in die Strike-Dateien.
#
# Der Deskriptor 200 haelt das Skript selbst offen; busybox' flock kann diese
# Form (am Knoten geprueft). Faellt flock aus, laeuft es wie bisher weiter -
# ein fehlender Lock darf den Check nicht stilllegen.
if command -v flock >/dev/null 2>&1 ; then
	exec 200<"$0"
	if ! flock -n 200 ; then
		exit 0
	fi
fi

# check for stale autoupdater
if [ -f /tmp/autoupdate.lock ] ; then
  MAXAGE=$(($(date +%s)-60*${UPDATEWAIT}))
  LOCKAGE=$(date -r /tmp/autoupdate.lock +%s)
  if [ "$MAXAGE" -gt "$LOCKAGE" ] && ! check_disabled stale_lock ; then
    now_reboot "[stale_lock] stale autoupdate.lock file" -f
  fi
  safety_exit "autoupdate running"
fi

# batman-adv crash when removing interface in certain configurations
check_disabled kernel_bug || { dmesg | grep -q "Kernel bug" && now_reboot "[kernel_bug] gluon issue #680" ; true ; }
# ath/ksoftirq-malloc-errors (upcoming oom scenario)
check_disabled ath_malloc || { dmesg | grep "ath" | grep "alloc of size" | grep -q "failed" && now_reboot "[ath_malloc] ath0 malloc fail" ; true ; }
check_disabled ksoftirqd_malloc || { dmesg | grep "ksoftirqd" | grep -q "page allocation failure" && now_reboot "[ksoftirqd_malloc] kernel malloc fail" ; true ; }
# interate over hostapd threads running 
check_disabled hostapd_pids || ps|grep hostapd|grep .pid|xargs -r -n 10 /lib/gluon/neanderfunk-hotfix/check_hostapd.sh
#check if hostapd-DFS scanning is broken according to sylogs
# -l 200 statt -l 5: der Check laeuft alle 7 Minuten, und in dieser Zeit
# entstehen auf einem normalen Knoten weit mehr als fuenf Logzeilen (allein
# node-whisperer schreibt alle 30 Sekunden). Die Meldung haette also in genau
# den letzten fuenf Zeilen stehen muessen, und das dreimal hintereinander -
# der Check konnte praktisch nie ausloesen.
if ! check_disabled dfs_failcheck && [ "$(logread -l 200|grep -c "daemon.warn hostapd: Failed to check if DFS is required")" -gt 0 ] ; then
  if [ "$(strike /tmp/hotfix.dfscheckfail)" -ge 3 ] ; then
    logger -s -t "neanderfunk-healthcheck" "[dfs_failcheck] hostapd DFS failcheck, restarting wifi"
    # Strikes nur vergessen, wenn der Neustart auch stattgefunden hat
    if restart_wifi ; then
      unstrike /tmp/hotfix.dfscheckfail
      sleep 10
    fi
   fi
 else
  unstrike /tmp/hotfix.dfscheckfail
 fi


# too many tunneldigger restarts
check_disabled tunneldigger || {
# [t] wie in der Zeile darunter: ohne die Klammer findet das grep sich selbst in
# der ps-Ausgabe wieder (am Knoten gemessen: Grundwert 1 statt 0), die Schwelle
# lag damit faktisch bei 3 statt bei 4.
[ "$(ps |grep -c -e "[t]unneldigger restart" -e "[t]unneldigger-watchdog")" -ge "4" ] && now_reboot "[tunneldigger] too many Tunneldigger watchdogs"
[ "$(ps |grep -c -e "/usr/bin/[t]unneldigger")" -ge "7" ] && now_reboot "[tunneldigger] too many Tunneldigger instances"
true; }


reboot_when_not_running() {
  (pgrep $1 || sleep 20 ; pgrep $1 || now_reboot "[$1] $1 not running") &> /dev/null
}

# check if 5min load >2 (panic reboot)
check_disabled load || { [ "$(cat /proc/loadavg|cut -d" " -f3|tr -d .)" -ge "201" ] && now_reboot "[load] Load 5minute-avg exceeds 2!" ; true ; }

# respondd or dropbear not running
check_disabled respondd || reboot_when_not_running respondd
check_disabled dropbear || reboot_when_not_running dropbear

# br-client without an address from the site prefix. site.conf's prefix6 is the
# domain's own ULA prefix (fd..), which the node assigns to itself - so this is a
# local network-config fault, not a question of reachability, and it stays here
# rather than in linkcheck. Escalates over four runs before rebooting.
if ! check_disabled br_client_ipv6 ; then
  prefix="$(jsonfilter -i /lib/gluon/site.json -e '@.prefix6' 2>/dev/null)"
  # without a prefix6 there is nothing to compare against, so do not reboot. The
  # old version compared against an empty prefix, which made grep -c report 0 and
  # would have rebooted the node every 7 minutes.
  if [ -n "$prefix" ] ; then
    if [ "$(ip -6 addr show to "$prefix" dev br-client 2>/dev/null | grep -c inet6)" = "0" ] ; then
      [ "$(strike /tmp/hotfix.brclient-noaddr)" -ge 4 ] && now_reboot "[br_client_ipv6] br-client has no address from the site prefix"
    else
      unstrike /tmp/hotfix.brclient-noaddr
    fi
  fi
fi

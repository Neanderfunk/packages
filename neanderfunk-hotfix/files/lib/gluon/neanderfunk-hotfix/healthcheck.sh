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

# Laeuft gerade ein Autoupdater, wird hier nichts angefasst. Der Check
# "stale_lock", der frueher an dieser Stelle stand, ist entfallen: er suchte
# eine liegengebliebene /tmp/autoupdate.lock, und diese Datei legt seit ihrer
# Einfuehrung 2016 niemand an - siehe common.sh.
if autoupdater_busy ; then
  safety_exit "autoupdate running"
fi

# batman-adv crash when removing interface in certain configurations
check_disabled kernel_bug || { dmesg | grep -q "Kernel bug" && now_reboot "[kernel_bug] gluon issue #680" ; true ; }
# ath/ksoftirq-malloc-errors (upcoming oom scenario)
check_disabled ath_malloc || { dmesg | grep "ath" | grep "alloc of size" | grep -q "failed" && now_reboot "[ath_malloc] ath0 malloc fail" ; true ; }
check_disabled ksoftirqd_malloc || { dmesg | grep "ksoftirqd" | grep -q "page allocation failure" && now_reboot "[ksoftirqd_malloc] kernel malloc fail" ; true ; }
# hostapd bedient die konfigurierten AP-Interfaces?
#
# Frueher wurde hier jeder hostapd-Prozess aus der ps-Ausgabe hereingereicht:
#     ps | grep hostapd | grep .pid | xargs -r -n 10 .../check_hostapd.sh
# Seit OpenWrt 21.02 laeuft aber ein einziger globaler hostapd ohne -P, und
# damit fand dieses grep nichts - am Knoten gemessen null Treffer, das Skript
# wurde nie aufgerufen. Es zaehlt seine Interfaces jetzt selbst auf.
check_disabled hostapd_pids || /lib/gluon/neanderfunk-hotfix/check_hostapd.sh
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
# Hier stand "ps | grep -c "[t]unneldigger"". Der Klammertrick verhindert nur,
# dass das grep sich selbst findet - nicht, dass es die aufrufende Shell oder
# ein Geschwister derselben Pipeline mitzaehlt. Am Knoten gemessen: aus einem
# Aufrufer, dessen Kommandozeile das Wort fuehrt, kam die Klammervariante auf
# 5 statt auf 3. Beide Schwellen hier loesen einen REBOOT aus, ein zu hoher
# Zaehlerstand ist also teuer.
#
# nf_count vergleicht den Prozessnamen exakt, nf-ps blendet die eigene
# Prozesskette aus - siehe /lib/gluon/neanderfunk/proc.sh. Der Watchdog-Zaehler
# muss ueber nf-ps gehen, weil "tunneldigger-watchdog" ein Lua-Skript ist und
# unter comm nicht eindeutig auftaucht.
[ "$(nf-ps | grep -c -e "tunneldigger restart" -e "tunneldigger-watchdog")" -ge "4" ] && now_reboot "[tunneldigger] too many Tunneldigger watchdogs"
[ "$(nf_count tunneldigger)" -ge "7" ] && now_reboot "[tunneldigger] too many Tunneldigger instances"
true; }


reboot_when_not_running() {
  (nf_running "$1" || sleep 20 ; nf_running "$1" || now_reboot "[$1] $1 not running") &> /dev/null
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

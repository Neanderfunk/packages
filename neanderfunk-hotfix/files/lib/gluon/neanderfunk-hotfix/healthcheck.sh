#!/bin/sh
# cc0, maintained by adorfer@nadeshda.org 

# check_disabled(), uptime_ok(), reboot_uptime_limit() - see common.sh for the
# uci keys (hotfix.<check>.disabled, hotfix.settings.reboot_uptime_min)
. /lib/gluon/neanderfunk-hotfix/common.sh

# wait 60 minutes if autoupdater is running
UPDATEWAIT='60'

safety_exit() {
  logger -s -t "neanderfunk-healthcheck" "safety checks failed $@, exiting with error code 2"
  exit 2
}

now_reboot() {
  # first parameter message
  # second optional -f to force reboot even if autoupdater is running
  logger -s -t "neanderfunk-healthcheck" -p 5 "rebooting... reason: $1"
  if uptime_ok ; then
    LOG=/lib/gluon/neanderfunk-hotfix
    [ ! -d $LOG ] && mkdir $LOG
    LOG="$LOG/reboot.log"
    # the first 5 times log the reason for a reboot in a file that is rebootsave
    # (|| echo 0: on the very first reboot the file does not exist yet, and an
    # empty $() would make the -gt comparison bail out with a shell error)
    [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 5 ] || echo "$(date) $1" >> "$LOG"
    if [ "$2" != "-f" ] && [ -f /tmp/autoupdate.lock ] ; then
      safety_exit "autoupdate running"
    fi
    sync
    /sbin/reboot -f
  fi
  logger -s -t "neanderfunk-healthcheck" -p 5 "no reboot yet, uptime below hotfix.settings.reboot_uptime_min"
}

restart_wifi() { 
  logger -s -t "neanderfunk-healthcheck" "wifi hard restart"
  wifi down
  killall hostapd 2>/dev/null
  rm -f /tmp/hostapd.*.core 2>/dev/null
  rm -f /var/run/wifi-*.pid 2>/dev/null
  wifi config
  wifi up
}


# don't do anything within the first hotfix.settings.reboot_uptime_min minutes
uptime_ok || safety_exit "no check due to uptime low!"

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
if ! check_disabled dfs_failcheck && [ $(logread -l 5|grep -c  "daemon.warn hostapd: Failed to check if DFS is required") -gt 0 ] ; then
  if [ "$(strike /tmp/hotfix.dfscheckfail)" -ge 3 ] ; then
    logger -s -t "neanderfunk-healthcheck" "[dfs_failcheck] hostapd DFS failcheck, restarting wifi"
    restart_wifi
    unstrike /tmp/hotfix.dfscheckfail
    sleep 10
   fi
 else
  unstrike /tmp/hotfix.dfscheckfail
 fi


# too many tunneldigger restarts
check_disabled tunneldigger || {
[ "$(ps |grep -c -e tunneldigger\ restart -e tunneldigger-watchdog)" -ge "4" ] && now_reboot "[tunneldigger] too many Tunneldigger watchdogs"
[ "$(ps |grep -c -e "/usr/bin/[t]unneldigger")" -ge "7" ] && now_reboot "[tunneldigger] too many Tunneldigger instances"
true; }

# br-client without ipv6 in prefix-range
if ! check_disabled br_client_ipv6 && [ "$(ip -6 addr show to "$(jsonfilter -i /lib/gluon/site.json -e '$.prefix6')" dev br-client | grep -c inet6)" == "0" ]; then
  now_reboot "[br_client_ipv6] br-client without ipv6 in prefix-range (probably none)"
fi

# An eth or wifi-mesh interface can silently drop out of its bridge after an
# interface flap - everything else still looks healthy, the port is just gone
# from the bridge. Ports are read from /sys/class/net/<bridge>/brif (exact, no
# brctl column parsing) and remembered per bridge in /tmp, so the list rebuilds
# from reality after a reboot.
# Three consecutive misses are required before rebooting: `wifi reconf` takes
# wifi interfaces out of their bridge for a moment, and that must not reboot the
# node. At the */7 cron interval that means a port has to stay gone for ~21 min.
check_bridge_ports() {
  local brif bridge port seen current
  for brif in /sys/class/net/*/brif ; do
    [ -d "$brif" ] || continue
    bridge="$(basename "$(dirname "$brif")")"
    # No special case for a bridge that currently has no ports at all: losing
    # every port is exactly the failure this is looking for, and the three
    # strikes below keep a transient from rebooting the node.
    current=" $(ls "$brif" 2>/dev/null | tr '\n' ' ')"
    for port in $(ls "$brif" 2>/dev/null) ; do
      touch "/tmp/hotfix.brport.$bridge.$port.seen"
      unstrike "/tmp/hotfix.brport.$bridge.$port.gone"
    done
    for seen in /tmp/hotfix.brport."$bridge".*.seen ; do
      [ -e "$seen" ] || continue
      port="${seen#/tmp/hotfix.brport.$bridge.}"
      port="${port%.seen}"
      case "$current" in
        *" $port "*) continue ;;
      esac
      case "$(strike "/tmp/hotfix.brport.$bridge.$port.gone")" in
        1) logger -s -t "neanderfunk-healthcheck" -p 5 "interface $port missing from bridge $bridge" ;;
        2) ;;
        *) now_reboot "[bridge_ports] interface $port dropped out of bridge $bridge" ;;
      esac
    done
  done
}
check_disabled bridge_ports || check_bridge_ports

reboot_when_not_running() {
  (pgrep $1 || sleep 20 ; pgrep $1 || now_reboot "[$1] $1 not running") &> /dev/null
}

# check if 5min load >2 (panic reboot)
check_disabled load || { [ "$(cat /proc/loadavg|cut -d" " -f3|tr -d .)" -ge "201" ] && now_reboot "[load] Load 5minute-avg exceeds 2!" ; true ; }

# respondd or dropbear not running
check_disabled respondd || reboot_when_not_running respondd
check_disabled dropbear || reboot_when_not_running dropbear

iw_dev_reboot_freeze() {
  # first parameter defines the time to wait
  # calls `iw` with the rest of the arguments given to the function
  local t=$1 ; shift
  iw dev $@ &
  # get the bg process
  local p=$!
  sleep $t
  # kill -0 does nothing, but returns true if the process exists
  kill -0 $p 2>/dev/null && now_reboot "[mesh_neighbours] 'iw dev $@ freezes for more than $t s'"
}

scan() {
  # call iw $dev scan to repair defunc wifi
  logger -s -t "neanderfunk-healthcheck" -p 5 "neighbour lost, running iw scan"
  iw_dev_reboot_freeze 30 $1 scan lowpri passive>/dev/null
}

# check all radios for lost neighbours ("no island")
#
# A mesh radio that has seen a real neighbourhood (>=2 neighbours) during this
# runtime and then sees none at all for a long time is suspicious: either the
# mesh interface is broken wifi-wise, or it dropped out of its bridge.
#
# Arming only after >=2 neighbours, and only for this runtime (the markers live
# in /tmp), does two things: a node that is legitimately alone never escalates,
# and a real outage costs at most one reboot - afterwards /tmp is empty, so the
# node is not armed again until it has actually seen neighbours again.
#
# Before this, the check only ever compared against the previous run and reacted
# with an iw scan. Worse, N_LOG is rewritten every run, so once *all* neighbours
# were gone the comparison list was empty too and the check went silent exactly
# when the node was islanded.
if ! check_disabled mesh_neighbours ; then
for mesh_radio in `uci show wireless 2>/dev/null| grep -E -o '(ibss|mesh)_radio[0-9]+' | awk '!seen[$0]++'`; do
  radio="$(uci get wireless.$mesh_radio.device)"
  if [[ "$(uci -q get wireless.$radio.disabled)" != "1" && "$(uci -q get wireless.$mesh_radio.disabled)" != "1" ]]; then
    DEV="$(uci get wireless.$mesh_radio.ifname)"
    N_LOG="/tmp/hotfix.mesh-neighbours.$mesh_radio"
    INHOOD="/tmp/hotfix.mesh-inhood.$mesh_radio"
    GONE="/tmp/hotfix.mesh-gone.$mesh_radio"
    OLD_NEIGHBOURS=$(cat $N_LOG 2>/dev/null)
    # fill log with new neighbours
    iw_dev_reboot_freeze 20 $DEV station dump | grep -e "^Station " | cut -f 2 -d ' ' > $N_LOG
    NEIGHBOURS="$(wc -l < "$N_LOG" 2>/dev/null | tr -d ' ')"

    # arm once a real neighbourhood has been seen during this runtime
    [ "$NEIGHBOURS" -ge 2 ] && touch "$INHOOD"

    if [ -f "$INHOOD" ] && [ "$NEIGHBOURS" -eq 0 ] ; then
      # had >=2, now none at all: try the cheap remedies first, then reboot
      case "$(strike "$GONE")" in
        1) logger -s -t "neanderfunk-healthcheck" -p 5 "lost all mesh neighbours on $DEV (had >=2 before)"
           scan "$DEV" ;;
        2) ;;
        3) logger -s -t "neanderfunk-healthcheck" -p 5 "still no mesh neighbours on $DEV, restarting wifi"
           restart_wifi ;;
        *) now_reboot "[mesh_neighbours] no mesh neighbours on $DEV for 4 checks (had >=2 before)" ;;
      esac
    else
      unstrike "$GONE"
      # only some neighbours vanished: cheap remedy, scan once and stop.
      # The break used to sit inside a ( ) subshell, where it cannot break the
      # enclosing loop, so every lost neighbour triggered another scan - each
      # blocking for up to 30s in iw_dev_reboot_freeze.
      for NEIGHBOUR in $OLD_NEIGHBOURS; do
         if ! grep -q "$NEIGHBOUR" "$N_LOG" ; then
           scan "$DEV"
           break
         fi
      done
    fi
  fi
done
fi

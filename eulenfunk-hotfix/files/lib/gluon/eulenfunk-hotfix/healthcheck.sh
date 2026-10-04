#!/bin/sh
# cc0, maintained by adorfer@nadeshda.org 
# Sackgasse 2021.1: repairs backported from neanderfunk-hotfix (v2025.1.x).

. /lib/gluon/eulenfunk-hotfix/common.sh

safety_exit() {
  logger -s -t "eulenfunk-healthcheck" "safety checks failed $@, exiting with error code 2"
  exit 2
}

now_reboot() {
  # first parameter message
  logger -s -t "eulenfunk-healthcheck" -p 5 "rebooting... reason: $1"
  if [ "$(sed 's/\..*//g' /proc/uptime)" -gt "3600" ] ; then
    LOG=/lib/gluon/healthcheck
    [ ! -d $LOG ] && mkdir $LOG
    LOG="$LOG/reboot.log"
    # the first 5 times log the reason for a reboot in a file that is rebootsave
    [ -f $LOG ] && [ "$(wc -l < $LOG)" -gt 5 ] || echo "$(date) $1" >> $LOG
    # never reboot into a running autoupdater
    autoupdater_busy && safety_exit "autoupdate running"
    reboot_hard
  fi
  logger -s -t "eulenfunk-healthcheck" -p 5 "no reboot during first hour"
}

restart_wifi() { 
  if ! wifi_lock ; then
    logger -s -t "eulenfunk-healthcheck" -p 5 "wifi restart skipped, another check is already restarting wifi"
    return 1
  fi
  logger -s -t "eulenfunk-healthcheck" "wifi hard restart"
  wifi down
  killall hostapd 2>/dev/null
  rm -f /tmp/hostapd.*.core 2>/dev/null
  rm -f /var/run/wifi-*.pid 2>/dev/null
  wifi config
  wifi up
  wifi_unlock
  return 0
}


# don't do anything the first 60 minutes
[ "$(sed 's/\..*//g' /proc/uptime)" -gt "3600" ] || safety_exit "no check due to uptime low!"

# a run that overruns the 7 minute period must not overlap with the next one
exec 200<"$0"
flock -n 200 || exit 0

# nothing while the autoupdater runs (the old guard on /tmp/autoupdate.lock
# was dead, nobody creates that file)
autoupdater_busy && safety_exit "autoupdate running"

# one pass over dmesg for all three patterns
set -- $(dmesg 2>/dev/null | awk '
  /Kernel bug/ { k = 1 }
  /ath/ && /alloc of size/ && /failed/ { a = 1 }
  /ksoftirqd/ && /page allocation failure/ { s = 1 }
  END { print k + 0, a + 0, s + 0 }')
# batman-adv crash when removing interface in certain configurations
[ "$1" = 1 ] && now_reboot "gluon issue #680"
# ath/ksoftirq-malloc-errors (upcoming oom scenario); the ksoftirqd pattern
# used to read "allcocation" and never matched
[ "$2" = 1 ] && now_reboot "ath0 malloc fail"
[ "$3" = 1 ] && now_reboot "kernel malloc fail"
# interate over hostapd threads running 
ps|grep hostapd|grep .pid|xargs -r -n 10 /lib/gluon/eulenfunk-hotfix/check_hostapd.sh

# hostapd DFS scanning broken according to syslog; used to look at the last 5
# log lines only (and called "logger -s t"), now 200 lines and 3 runs in a row
if [ "$(logread -l 200 | grep -c "daemon.warn hostapd: Failed to check if DFS is required")" -gt 0 ] ; then
  if [ "$(strike /tmp/hotfix.dfscheckfail)" -ge 3 ] ; then
    logger -s -t "eulenfunk-healthcheck" "hostapd DFS failcheck, restarting wifi"
    restart_wifi && unstrike /tmp/hotfix.dfscheckfail
  fi
else
  unstrike /tmp/hotfix.dfscheckfail
fi

# too many tunneldigger restarts
# [t] keeps grep from counting itself; it used to, so the effective threshold
# was 3 watchdogs, kept as is
[ "$(ps |grep -c -e "[t]unneldigger restart" -e "[t]unneldigger-watchdog")" -ge "3" ] && now_reboot "too many Tunneldigger watchdogs"
[ "$(ps |grep -c -e "/usr/bin/[t]unneldigger")" -ge "7" ] && now_reboot "too many Tunneldigger instances"

# br-client without ipv6 in prefix-range, 4 runs in a row (used to reboot on
# the first miss, e.g. during a short RA gap)
if [ "$(ip -6 addr show to "$(jsonfilter -i /lib/gluon/site.json -e '$.prefix6')" dev br-client | grep -c inet6)" = "0" ]; then
  [ "$(strike /tmp/hotfix.brclient-noaddr)" -ge 4 ] && now_reboot "br-client without ipv6 in prefix-range (probably none)"
else
  unstrike /tmp/hotfix.brclient-noaddr
fi

# exact process name from /proc/<pid>/comm; pgrep matched substrings and its
# own ancestors
daemon_running() {
  local p c
  for p in /proc/[0-9]* ; do
    read -r c < "$p/comm" 2>/dev/null || continue
    [ "$c" = "$1" ] && return 0
  done
  return 1
}
reboot_when_not_running() {
  (daemon_running $1 || sleep 20 ; daemon_running $1 || now_reboot "$1 not running") >/dev/null 2>&1
}

# check if 5min load >2 (panic reboot)
[ "$(cat /proc/loadavg|cut -d" " -f3|tr -d .)" -ge "201" ] && now_reboot "Load 5minute-avg exceeds 2!"

# respondd or dropbear not running
reboot_when_not_running respondd
reboot_when_not_running dropbear

iw_dev_reboot_freeze() {
  # first parameter defines the time to wait
  # calls `iw` with the rest of the arguments given to the function
  local t=$1 ; shift
  iw dev $@ &
  # get the bg process
  local p=$!
  sleep $t
  # kill -0 does nothing, but returns true if the process exists
  kill -0 $p 2>/dev/null && now_reboot "'iw dev $@ freezes for more than $t s'"
}

scan() {
  # call iw $dev scan to repair defunc wifi
  logger -s -t "eulenfunk-healthcheck" -p 5 "neighbour lost, running iw scan"
  iw_dev_reboot_freeze 30 $1 scan lowpri passive>/dev/null
}

# check all radios for lost neighbours
for mesh_radio in `uci show wireless 2>/dev/null| grep -E -o 'mesh_radio[0-9]+' | awk '!seen[$0]++'`; do
  radio="$(uci get wireless.$mesh_radio.device)"
  if [[ "$(uci -q get wireless.$radio.disabled)" != "1" && "$(uci -q get wireless.$mesh_radio.disabled)" != "1" ]]; then
    DEV="$(uci get wireless.$mesh_radio.ifname)"
    N_LOG="/tmp/mesh_neighbours_$mesh_radio"
    OLD_NEIGHBOURS=$(cat $N_LOG 2>/dev/null)
    # fill log with new neighbours
    iw_dev_reboot_freeze 20 $DEV station dump | grep -e "^Station " | cut -f 2 -d ' ' > $N_LOG
    for NEIGHBOUR in $OLD_NEIGHBOURS; do
       # one scan per radio and run (break in a subshell used to do nothing)
       if ! grep -q $NEIGHBOUR "$N_LOG" ; then scan $DEV; break; fi
    done
  fi
done

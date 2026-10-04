#!/bin/sh
# cc0, maintained by adorfer@nadeshda.org 

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
    [ "$(wc -l < $LOG)" -gt 5 ] || echo "$(date) $1" >> $LOG
    # never reboot into a running autoupdater (it holds the flock through
    # the sysupgrade)
    flock -n /var/lock/autoupdater.lock true || safety_exit "autoupdate running"
    sync
    /sbin/reboot -f
  fi
  logger -s -t "eulenfunk-healthcheck" -p 5 "no reboot during first hour"
}

restart_wifi() { 
  logger -s -t "eulenfunk-healthcheck" "wifi hard restart"
  wifi down
  killall hostapd 2>/dev/null
  rm -f /tmp/hostapd.*.core 2>/dev/null
  rm -f /var/run/wifi-*.pid 2>/dev/null
  wifi config
  wifi up
}


# don't do anything the first 60 minutes
[ "$(sed 's/\..*//g' /proc/uptime)" -gt "3600" ] || safety_exit "no check due to uptime low!"

# nothing while the autoupdater runs (the old guard on /tmp/autoupdate.lock
# was dead, nobody creates that file)
flock -n /var/lock/autoupdater.lock true || safety_exit "autoupdate running"

# batman-adv crash when removing interface in certain configurations
dmesg | grep -q "Kernel bug" && now_reboot "gluon issue #680"
# ath/ksoftirq-malloc-errors (upcoming oom scenario)
dmesg | grep "ath" | grep "alloc of size" | grep -q "failed" && now_reboot "ath0 malloc fail"
# interate over hostapd threads running 
ps|grep hostapd|grep .pid|xargs -r -n 10 /lib/gluon/eulenfunk-hotfix/check_hostapd.sh

# too many tunneldigger restarts
# [t] keeps grep from counting itself; it used to, so the effective threshold
# was 3 watchdogs, kept as is
[ "$(ps |grep -c -e "[t]unneldigger restart" -e "[t]unneldigger-watchdog")" -ge "3" ] && now_reboot "too many Tunneldigger watchdogs"
[ "$(ps |grep -c -e "/usr/bin/[t]unneldigger")" -ge "7" ] && now_reboot "too many Tunneldigger instances"

# br-client without ipv6 in prefix-range
if [ "$(ip -6 addr show to "$(jsonfilter -i /lib/gluon/site.json -e '$.prefix6')" dev br-client | grep -c inet6)" == "0" ]; then
  now_reboot "br-client without ipv6 in prefix-range (probably none)"
fi

reboot_when_not_running() {
  (pgrep $1 || sleep 20 ; pgrep $1 || now_reboot "$1 not running") &> /dev/null
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

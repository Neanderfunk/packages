#!/bin/sh
DELAYTIME=$(</dev/urandom sed 's/[^[:digit:]]\+//g' | head -c4)
logger -s -t "neanderfunk-weeklyreboot" -p 5 "sheduled reboot in $DELAYTIME seconds"
sleep $DELAYTIME
logger -s -t "neanderfunk-weeklyreboot" -p 5 "sheduled reboot in 5 seconds"
sleep 5
# Autoupdate? 
upgrade_started='/tmp/autoupdate.lock'
if [ -f $upgrade_started ] ; then
  logger -s -t "neanderfunk-weeklyreboot" -p 5 "Autoupdate läuft! Aborting"
  exit 2
 fi
reboot

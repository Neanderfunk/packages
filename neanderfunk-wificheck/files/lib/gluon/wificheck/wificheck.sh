#! /bin/sh
mname=$(uci get wireless.mesh_radio0.ifname)
bssid=$(uci get wireless.mesh_radio0.mesh_id)
if [ -z "$mname" ] || [ -z "$bssid" ]; then
  exit 0
 else
  echo radio: $mname
  wmesh=$(iw dev $mname scan lowpri passive|grep $mname|wc -l)
  sleep 4 # this is a hack
  neighbours=$(iw dev $mname scan lowpri passive|grep $bssid|wc -l)
  sleep 4 
  mesh=$(batctl o|grep $mname|cut -d")"  -f 2|cut -d" " -f 2|grep [.?.?:.?.?:.*]|sort|uniq|wc -l)
  logger -s -t "neanderfunk-wificheck" -p 5 "ibss-bat-neighbours: $mesh wifiadhocs-neighbours: $wmesh wifimesh-neighbours: $neighbours"
  if [ ! -f /tmp/wificheck.noisland ] ; then
    if [ "$mesh" -gt 1 ] ; then #minimum 2 neighbors
      echo 1>/tmp/wificheck.noisland
    fi
   else
    if [ "$mesh" -lt 1 ] ; then # alone?
      if [ -f /tmp/wificheck.pbflag ] ; then
        if [ -f /tmp/wificheck.pbflag2 ] ; then
          logger -s -t "neanderfunk-wificheck" -p 5 "2nd time no wifi neighbours, rebooting!"
          sleep 3
          # don't reboot during the first hour
          [ $(cat /proc/uptime | sed 's/\..*//g') -gt 3600 ] || reboot -f
         else
          logger -s -t "neanderfunk-wificheck" -p 5 "still no wifi neighbours."
          echo 1>/tmp/wificheck.pbflag2
         fi
       else
        logger -s -t "neanderfunk-wificheck" -p 5 "lost wifi neighbours."
        echo 1>/tmp/wificheck.pbflag
       fi
    else
     if [ -f /tmp/wificheck.pbflag ] ; then
       rm /tmp/wificheck.pbflag
      fi
     if [ -f /tmp/wificheck.pbflag2 ] ; then
       rm /tmp/wificheck.pbflag2
      fi
    fi
   fi
 fi

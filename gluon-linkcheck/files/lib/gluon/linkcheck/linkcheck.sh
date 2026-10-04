#! /bin/sh
# Nachbarpruefung alle 15 min (micron.d). Je Pruefung (batman-Interface,
# WLAN-Radio) erst "in der Nachbarschaft" (mindestens 2 Nachbarn) merken.
# Danach ohne Nachbarn: 1. Mal merken, 2. Mal WLAN neu, 3. Mal Reboot.
# (Kommentare entfernt gluonShellDiet.sh beim Bau.)

# Waehrend der Autoupdater laeuft (haelt das flock bis in den sysupgrade
# hinein), weder WLAN noch Reboot anfassen.
flock -n /var/lock/autoupdater.lock true || exit 0

valuecheck ()
{
  f=/tmp/linkcheck.$linkname.$check
  if [ ! -f $f.inhood ] ; then
    if [ "$wert" -gt 1 ] ; then
      echo 1 >$f.inhood
    fi
  elif [ "$wert" -lt 1 ] ; then
    if [ ! -f $f.linkpb1 ] ; then
      logger -t gluon-linkcheck -p 5 "lost neighbours $linkname.$check"
      echo 1 >$f.linkpb1
    elif [ ! -f $f.linkpb2 ] ; then
      logger -t gluon-linkcheck -p 5 "still no neighbours $linkname.$check, wifi restart"
      echo 1 >$f.linkpb2
      # hoechstens ein WLAN-Neustart je Lauf, auch wenn mehrere Pruefungen
      # gleichzeitig eskalieren
      [ -n "$wr" ] && return
      wr=1
      wifi down
      killall hostapd >/dev/null 2>&1
      rm -f /var/run/wifi-*.pid
      wifi config
      wifi up
      sleep 10
    else
      # Frueher stand hier noch ein network restart vor dem Reboot, der im
      # selben Lauf sofort vom Reboot ueberholt wurde (fi an falscher Stelle).
      logger -t gluon-linkcheck -p 5 "3rd time no neighbours $linkname.$check, rebooting!"
      sleep 10
      flock -n /var/lock/autoupdater.lock true || exit 0
      reboot -f
    fi
  else
    rm -f $f.linkpb1 $f.linkpb2
  fi
}

linkname=batadv
for check in $(batctl if | cut -d: -f1); do
  wert=$(batctl n | grep $check | awk '{print $2}' | sort -u | wc -l)
  valuecheck
done

# WLAN: je Radio ein Scan und eine Pruefung, am ersten vorhandenen Interface
# (mesh vor client). Frueher eskalierten mesh- und client-Interface desselben
# Radios getrennt, der WLAN-Neustart lief dann zwei- bis dreimal.
check=bsses
for radio in radio0 radio1 radio2; do
  for sec in mesh_$radio client_$radio; do
    linkname=$(uci -q get wireless.$sec.ifname) && break
  done
  [ -n "$linkname" ] || continue
  iwfile=/tmp/linkcheck.iwscan.$radio
  sleep 4
  # Scan fehlgeschlagen (Interface weg, busy): kein Befund, nicht als
  # Nachbarverlust zaehlen
  iw dev $linkname scan lowpri passive >$iwfile 2>/dev/null || { rm -f $iwfile; continue; }
  sleep 4
  wert=$(grep -c "BSS .*:.*:.*:.*:.*:.*(on.*)" $iwfile)
  rm -f $iwfile
  valuecheck
done

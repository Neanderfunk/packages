#! /bin/sh
# Nachbarpruefung alle 15 min (micron.d). Je Pruefung (batman-Interface,
# WLAN-Radio) erst "in der Nachbarschaft" (mindestens 2 Nachbarn) merken.
# Danach ohne Nachbarn: 1. und 2. Mal melden, 3. Mal WLAN neu, 4. Mal Reboot;
# in der ersten Stunde nach dem Boot nur melden.
# Sackgasse 2021.1, Reparaturen aus neanderfunk-linkcheck (v2025.1.x): die
# alte Leiter rebootete wegen eines falsch gesetzten fi schon beim 3. Mal
# (der Netzwerk-Neustart davor wurde sofort ueberholt), der
# Autoupdater-Waechter pruefte eine Datei, die niemand anlegt, und ein
# haengender Scan blockierte den Lauf.
# (Kommentare entfernt gluonShellDiet.sh beim Bau.)

# Waehrend der Autoupdater laeuft (haelt das flock bis in den sysupgrade
# hinein), weder WLAN noch Reboot anfassen.
autoupdater_busy() {
  flock -n /var/lock/autoupdater.lock true 2>/dev/null || return 0
  pgrep sysupgrade >/dev/null
}
autoupdater_busy && exit 0
# keine ueberlappenden Laeufe
exec 200<"$0"
flock -n 200 || exit 0

uptime_ok() {
  [ "$(cut -d. -f1 /proc/uptime)" -gt 3600 ]
}

strike() {
  local n=1
  while [ -e "$1.$n" ] ; do n=$((n + 1)) ; done
  : > "$1.$n"
  echo "$n"
}
unstrike() {
  set -- "$1".*
  [ -e "$1" ] || return 0
  rm -f "$@"
}

# ein WLAN-Neustart zur Zeit ueber alle Checks (hotfix, wifi-blackout)
wifi_lock() {
  exec 201>>/var/lock/neanderfunk-wifi.lock 2>/dev/null || return 0
  flock -n 201
}

valuecheck ()
{
  f=/tmp/linkcheck.$linkname.$check
  if [ ! -f $f.inhood ] ; then
    if [ "$wert" -gt 1 ] ; then
      echo 1 >$f.inhood
    fi
    return
  fi
  if [ "$wert" -ge 1 ] ; then
    unstrike $f.linkpb
    return
  fi
  n=$(strike $f.linkpb)
  if [ "$n" -le 2 ] ; then
    logger -t gluon-linkcheck -p 5 "lost neighbours ${n}x: $linkname.$check"
  elif ! uptime_ok ; then
    logger -t gluon-linkcheck -p 5 "lost neighbours ${n}x: $linkname.$check - no action during the first hour"
  elif [ "$n" -eq 3 ] ; then
    if [ -n "$wr" ] ; then
      logger -t gluon-linkcheck -p 5 "lost neighbours 3x: $linkname.$check, wifi already restarted this run"
    elif ! wifi_lock ; then
      logger -t gluon-linkcheck -p 5 "lost neighbours 3x: $linkname.$check, another check is already restarting wifi"
    else
      logger -t gluon-linkcheck -p 5 "lost neighbours 3x: $linkname.$check, wifi restart"
      wr=1
      wifi down
      killall hostapd >/dev/null 2>&1
      rm -f /var/run/wifi-*.pid
      wifi config
      wifi up
      exec 201>&-
      sleep 15
    fi
  else
    logger -t gluon-linkcheck -p 5 "lost neighbours ${n}x: $linkname.$check, rebooting!"
    sleep 10
    autoupdater_busy && exit 0
    # Flash im Hintergrund syncen, reboot -f, sysrq als Nachschlag
    sync &
    sleep 3
    reboot -f &
    sleep 60
    echo b > /proc/sysrq-trigger
    exit 0
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
  # Scan im Hintergrund, nach 20 s abbrechen (ein haengender Scan hielt den
  # ganzen Lauf auf). Fehlgeschlagen oder haengend: kein Befund, nicht als
  # Nachbarverlust zaehlen.
  rm -f $iwfile
  ( iw dev $linkname scan lowpri passive >$iwfile.tmp 2>/dev/null && mv $iwfile.tmp $iwfile ) &
  p=$!
  n=0
  while [ $n -lt 20 ] && kill -0 $p 2>/dev/null ; do sleep 1 ; n=$((n + 1)) ; done
  if kill -0 $p 2>/dev/null ; then
    kill -9 $p 2>/dev/null
    logger -t gluon-linkcheck -p 5 "iw dev $linkname scan hangs, skipped"
  fi
  [ -f $iwfile ] || { rm -f $iwfile.tmp; continue; }
  sleep 4
  wert=$(grep -c "BSS .*:.*:.*:.*:.*:.*(on.*)" $iwfile)
  rm -f $iwfile
  valuecheck
done

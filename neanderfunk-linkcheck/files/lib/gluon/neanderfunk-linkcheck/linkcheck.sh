#! /bin/sh
# Link and topology checks: does this node still have the neighbours, batman
# interfaces and bridge ports it had before? See common.sh for the uci keys.

. /lib/gluon/neanderfunk-linkcheck/common.sh

valuecheck ()
# this checks for multiple problems on the same IF, tries to resolve, or reboots as last resort
{
  logstring=${logstring}" "${linkname}"."${check}":"${wert}
  # Signatur fuer log_status: nur "hat welche" gegen "hat keine". Die Rohzahlen
  # in logstring schwanken bei jedem Lauf - Scan-Ergebnisse und
  # Originator-Zaehler gehen staendig um ein paar hoch und runter -, als
  # Vergleichsgrundlage waeren sie also wertlos. Fuer die Frage, ob sich am
  # Zustand etwas geaendert hat, zaehlt allein die Null.
  if [ "${wert}" -ge 1 ] 2>/dev/null ; then
    sigstring=${sigstring}" "${linkname}"."${check}":+"
  else
    sigstring=${sigstring}" "${linkname}"."${check}":0"
  fi
  pb="/tmp/linkcheck.${linkname}.${check}"

  if [ ! -f "${pb}.inhood" ] ; then
    # arm only once a real neighbourhood has been seen (>=2) during this runtime
    [ "${wert}" -gt "1" ] && : > "${pb}.inhood"
    return
  fi

  if [ "${wert}" -ge "1" ] ; then
    # links are back, forget the strikes
    unstrike "${pb}.linkpb"
    return
  fi

  # armed and now down to nothing: escalate. This used to be a nested if/elif
  # cascade that also fell through into the levels below it, so the 3rd failure
  # additionally logged the 2nd one and rewrote its marker.
  case "$(strike "${pb}.linkpb")" in
    1)
      logger -s -t "neanderfunk-linkcheck" -p 5 "[${checkgroup}] lost neighbours 1st: ${linkname}.${check}"
      ;;
    2)
      logger -s -t "neanderfunk-linkcheck" -p 5 "[${checkgroup}] lost neighbours 2nd: ${linkname}.${check}"
      ;;
    3)
      # Once per run, not once per check. A real outage takes every check down
      # at the same time, so they all reach their 3rd strike in the same run -
      # which used to mean one full wifi restart plus sleep 15 per interface,
      # each new "wifi down" cutting into the previous "wifi up" before it had
      # settled. Minutes of thrashing, and the restart never got a fair chance
      # to work. The strikes are still counted per check, so the escalation to
      # the 4th (reboot) is unchanged.
      if ! uptime_ok ; then
        no_action_yet "[${checkgroup}] lost neighbours 3rd: ${linkname}.${check}"
      elif [ -n "${wifi_restarted}" ] ; then
        logger -s -t "neanderfunk-linkcheck" -p 5 "[${checkgroup}] lost neighbours 3rd: ${linkname}.${check}, wifi already restarted this run"
      elif ! wifi_lock ; then
        # gemeinsame Sperre, siehe common.sh. wifi_restarted bleibt ungesetzt:
        # der Neustart ist nicht passiert, also darf ihn der naechste Lauf
        # nachholen.
        logger -s -t "neanderfunk-linkcheck" -p 5 "[${checkgroup}] lost neighbours 3rd: ${linkname}.${check}, but another check is already restarting wifi"
      else
        logger -s -t "neanderfunk-linkcheck" -p 5 "[${checkgroup}] lost neighbours 3rd: ${linkname}.${check}, wifi restart"
        wifi_restarted=1
        wifi down
        killall hostapd >/dev/null 2>&1
        rm -f /var/run/wifi-*.pid >/dev/null 2>&1
        # Kein "wifi config" zwischen down und up: das erkennt unter OpenWrt 23.05
        # neue Radios und macht dabei "uci commit wireless" - samt offener
        # Laufzeit-Aenderungen (Offline-SSID, ap-timer). Fuer den Neustart unnoetig.
        wifi up
        wifi_unlock
        sleep 15
      fi
      ;;
    *)
      # not within the first linkcheck.settings.reboot_uptime_min minutes of
      # uptime. The .inhood arming already bounds an outage to one reboot (the
      # markers live in /tmp), this keeps the rate down on top. Report first,
      # then decide - so the finding shows up in the log either way.
      if ! uptime_ok ; then
        no_action_yet "[${checkgroup}] lost neighbours 4th: ${linkname}.${check}"
        return
      fi
      logger -s -t "neanderfunk-linkcheck" -p 5 "[${checkgroup}] lost neighbours 4th: ${linkname}.${check}, rebooting!"
      # Der Grund muss den Reboot ueberleben - der Ringpuffer tut es nicht.
      nf_reboot_log "[${checkgroup}] lost neighbours 4th: ${linkname}.${check}"
      sleep 10
      autoupdater_running && exit
      nf_reboot_hard
      # nf_reboot_hard does not necessarily return
      exit
      ;;
  esac
}
## script start

# nicht laufen, waehrend der Knoten Firmware laedt oder flasht
autoupdater_running && exit 0

# Einzelinstanz-Lock. Dieses Skript kann laenger laufen als sein Cron-Intervall:
# je Radio zwei "sleep 4" um den Scan, ein 20-Sekunden-Waechter um "iw station
# dump", 15 Sekunden nach einem WLAN-Neustart, 10 vor einem Reboot. Ohne Lock
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

# Two thresholds, deliberately separate:
#   below linkcheck.settings.check_uptime_min (default 5 min) nothing runs at
#     all - the network is still coming up, and "no neighbours" or "anycast not
#     answering" then is not a fault worth reporting;
#   below linkcheck.settings.reboot_uptime_min (default 60 min) the checks run
#     and report what they find, but nothing restarts wifi or reboots.
checks_ok || exit 0

ifnameseparator=','  # charcters like . - # or even : may cause issues

# Einmal je Lauf statt je Abschnitt und Interface, siehe nf_uci_get in common.sh.
NF_UCI_wireless="$(uci -q show wireless 2>/dev/null)"
batn="$(batctl n 2>/dev/null)"
batif="$(batctl if 2>/dev/null)"

# batman-Interfaces aus "batctl if" ("mesh0: active"), ohne cut
batmeshs=''
while IFS= read -r l ; do
  [ -n "$l" ] && batmeshs="$batmeshs ${l%%:*}"
done <<EOF
$batif
EOF

# Verschiedene Nachbar-MACs je Interface aus "batctl n", ein awk fuer alle
# Interfaces. Frueher je Interface "batctl n|tail|grep|awk|sort|uniq|wc",
# sieben Prozesse. Die zwei Kopfzeilen fallen weg (NR>2). Der Vergleich ist
# jetzt exakt: "grep eth0" traf frueher auch "eth0.1".
batncounts=" $(printf '%s\n' "$batn" | awk 'NR>2 && !s[$1" "$2]++ {c[$1]++} END {for (i in c) printf "%s=%d ", i, c[i]}')"

# Wert <name> aus einer "name=n name=n"-Liste in NF_VAL, 0 wenn nicht drin
list_count() {
  case "$1" in
    *" $2="*) NF_VAL="${1#*" $2="}" ; NF_VAL="${NF_VAL%% *}" ;;
    *) NF_VAL=0 ;;
  esac
}


# 1) running over existing batman-interface, looking for direct neighbors
checkgroup='batadv_neighbours'
if ! check_disabled "$checkgroup" ; then
linkname='batadv'
# (Hier stand eine Weiche fuer batctl-Versionen vor 2016.3, die "batctl -n"
# statt "batctl n" brauchten. Gluon 2023.2 bringt batman-adv 2023.1 mit.)
for batm in ${batmeshs}; do
  list_count "$batncounts" "$batm"
  check=${batm}
  wert=$NF_VAL
  valuecheck ${check}
done
fi

# 2) running over wifimesh-interfaces, looking for other SSIDs on the same wifi via iwscan lowpri

# The scan breaks mesh links on wifi6 hardware (mt7915). It does not on the
# older mt76 chips: a Xiaomi 4A Gigabit (ramips/mt7621, mt7603e plus mt76x2e)
# scans without trouble.
#
# This used to test the OpenWrt target for "mediatek", which did not work at
# all: a D-Link COVR-X1860 - the very device the guard was written for - is an
# mt7621 SoC with mt7915 radios and reports DISTRIB_TARGET='ramips/mt7621', so
# the test never matched and the node got scanned anyway. Ask the driver
# instead, per radio, and keep the target test only as a fallback for when the
# driver link is not readable (interface down, no sysfs entry).
. /etc/openwrt_release 2>/dev/null
gluontarget="${DISTRIB_TARGET%%/*}"
# Is this netdev actually up? uci's "disabled" flag is not enough: on a
# COVR-X1860 mesh_radio1 has disabled='0' and a netdev, but operstate "down",
# because radio1 sits on channel "auto" and a mesh interface needs a fixed one.
# Scanning or polling such an interface always yields zero - and a radio that
# had armed before it went down would escalate all the way to a reboot just
# because someone switched it off. A radio that is merely deaf is still
# operationally up, so this does not hide the case these checks exist for.
iface_is_up() {
  # $1: ifname
  local st
  [ -r "/sys/class/net/$1/operstate" ] || return 1
  read -r st < "/sys/class/net/$1/operstate"
  [ "$st" = "up" ]
}

radio_is_wifi6() {
  # $1: ifname
  # Ask for the kernel module, not the driver name: on a ZyXEL NWA50AX Pro
  # (mediatek/filogic) the radios sit in the SoC and the driver is called
  # "mt798x-wmac", while the module is the same mt7915e as on the COVR. The
  # driver name alone would miss every filogic node; here it only happened to
  # work because the target fallback below caught them.
  mod="$(readlink -f "/sys/class/net/$1/device/driver/module" 2>/dev/null)"
  [ -n "$mod" ] || mod="$(readlink -f "/sys/class/net/$1/device/driver" 2>/dev/null)"
  case "${mod##*/}" in
    mt7915*|mt798*) return 0 ;;
  esac
  [ "$gluontarget" = "mediatek" ]
}
checkgroup='bsses'
if ! check_disabled "$checkgroup" ; then
  checks=''
  linksexist=''
  # Hier stand eine feste Liste von neun Sektionsnamen fuer radio0 bis radio2.
  # owe_radio* kam darin ueberhaupt nicht vor - OWE-Interfaces wurden also nie
  # geprueft, seit es sie gibt.
  #
  # Jetzt aus uci: was konfiguriert ist, weiss uci, nicht wir. Die Praefixe sind
  # bewusst aufgezaehlt statt "alles mit ifname" - wan_radio* (privates WLAN)
  # gehoert nicht in diese Pruefung. Nebenbei traegt das auch Geraete mit mehr
  # als drei Radios, die es ab Gluon 2025.1 geben kann.
  set -f ; oldifs="$IFS" ; IFS='
'
  for l in $NF_UCI_wireless ; do
    case "$l" in
      wireless.client_radio[0-9]*.ifname=*|wireless.owe_radio[0-9]*.ifname=*|wireless.mesh_radio[0-9]*.ifname=*|wireless.batmesh_radio[0-9]*.ifname=*|wireless.ibss_radio[0-9]*.ifname=*)
        l="${l#wireless.}"
        linksexist="$linksexist wireless.${l%%.*}"
        ;;
    esac
  done
  IFS="$oldifs" ; set +f
  # alte scans wegraeumen (rm nur, wenn es welche gibt)
  set -- /tmp/linkcheck.iwscan.*
  [ -e "$1" ] && rm -f "$@"
  for linkexist in $linksexist; do
    nf_uci_get "$NF_UCI_wireless" "$linkexist.ifname" || continue
    linkname="$NF_VAL"
    if ! iface_is_up "${linkname}" ; then
      continue
     fi
    if radio_is_wifi6 "${linkname}" ; then
      # Once per boot, not every five minutes. On a ZyXEL NWA50AX Pro this
      # fires for mesh0, client0 and client1 on every run - three identical
      # lines every five minutes, about 1700 a day, saying the same thing the
      # first one said. The state is static: a radio does not stop being wifi6.
      if [ ! -e "/tmp/linkcheck.wifi6.${linkname}" ] ; then
        touch "/tmp/linkcheck.wifi6.${linkname}"
        logger -s -t "neanderfunk-linkcheck" -p 5 "[bsses] ${linkname} is wifi6/mt7915, not scanning it (logged once per boot)"
      fi
      continue
     fi
    nf_uci_get "$NF_UCI_wireless" "$linkexist.device"
    iwfile=/tmp/linkcheck.iwscan.$NF_VAL
    if [ ! -f $iwfile ] ; then
      sleep 4
      # Derselbe Waechter wie um "iw station dump" weiter unten: ein iw-Aufruf
      # gegen ein verklemmtes Radio kann haengen bleiben, und dieser hier lief
      # bisher ungesichert - der ganze Lauf haette dann gestanden, waehrend
      # micrond alle 5 Minuten den naechsten startet.
      ( iw dev "${linkname}" scan lowpri passive > "$iwfile" 2>/dev/null ) &
      scanpid=$!
      n=0
      while [ $n -lt 20 ] && kill -0 $scanpid 2>/dev/null ; do sleep 1 ; n=$((n + 1)) ; done
      if kill -0 $scanpid 2>/dev/null ; then
        kill -9 $scanpid 2>/dev/null
        logger -s -t "neanderfunk-linkcheck" -p 5 "[bsses] iw dev ${linkname} scan hangs, skipped"
        rm -f "$iwfile"
        continue
       fi
      sleep 4
     fi
    bsses=$(grep -c "BSS .*:.*:.*:.*:.*:.*(on.*)" "$iwfile")
    checks="bsses"
##   looking for BSSIDs with the name of the wifimesh
#    unset bssid
#    bssid=$(uci get $linkexist.mesh_id 2>/dev/null)
#    if [ -z "$bssid" ] ; then
#      bssid=$(uci get $linkexist.ssid)
#     fi
#    wifimeshneighbors=$(cat $iwfile|grep $bssid|wc -l)
#    checks="wifimeshneighbors bsses"
    # ${checks}, not ${check}s: the latter appended a literal "s" to whatever
    # $check happened to hold from the previous section (e.g. "primary0s"), so
    # $wert came out empty and this whole BSS check silently did nothing - while
    # the expensive part above (two sleeps plus an iw scan per radio) still ran
    # every 5 minutes. It also clobbered $check, growing it by one "s" per
    # iteration.
    for check in ${checks}; do
      eval "wert=\$${check}"
      valuecheck ${check}
     done
   done
 fi

# 3) check for disappearing batman-interfaces
  # (a companion list "wirebatlinks" used to sit here, assigned and never read)
  # Ausnahmeliste, keine Pruefliste: was hier drinsteht, wird vom
  # Originator-Check weiter unten NICHT als Reboot-Bedingung gewertet. Ein
  # fehlender Eintrag heisst also nicht "wird uebersehen", sondern "wird
  # mitgeprueft und kann bis zum Reboot eskalieren". Fest standen hier mesh0 bis
  # mesh3, was heute reicht, aber eben nur zufaellig.
  wifibatlinks=''
  set -f ; oldifs="$IFS" ; IFS='
'
  for l in $NF_UCI_wireless ; do
    case "$l" in
      wireless.mesh_radio[0-9]*.ifname=*|wireless.ibss_radio[0-9]*.ifname=*|wireless.batmesh_radio[0-9]*.ifname=*)
        l="${l#*=}" ; l="${l#\'}"
        wifibatlinks="$wifibatlinks ${l%\'}"
        ;;
    esac
  done
  IFS="$oldifs" ; set +f
  # Liefert uci nichts - kein wireless-Config, kaputtes uci -, dann lieber die
  # alte feste Liste als eine leere: eine leere Ausnahmeliste wuerde die
  # WLAN-Mesh-Interfaces in die Reboot-Bedingung hineinnehmen.
  case "$wifibatlinks" in
    *[!\ ]*) ;;
    *) wifibatlinks='mesh0 mesh1 mesh2 mesh3' ;;
  esac

  # inventory of bat-interfaces, from all possible sources, probably unneccesary
  # aus "batctl if" und den Interfaces mit Nachbarn in "batctl n" (beides
  # oben einmal geholt), ohne sort|uniq
  batinterfaces=' '
  for b in ${batmeshs} ${batncounts} ; do
    b="${b%%=*}"
    case "$batinterfaces" in
      *" $b "*) ;;
      *) batinterfaces="$batinterfaces$b " ;;
    esac
  done
#  echo batinterfaces $batinterfaces

  # create flag files in /tmp
  for batinterface in ${batinterfaces}; do
: > /tmp/linkcheck.batinterface${ifnameseparator}${batinterface}${ifnameseparator}up
   done
  # get all previously seen interfaces by flag files
  for batupfiles in "/tmp/linkcheck.batinterface${ifnameseparator}*${ifnameseparator}up"; do
    :
   done
  # check if all prviously seen are in current list
  checkgroup='batinterfaces'
  for batups in ${batupfiles}; do
    check_disabled "$checkgroup" && break
    [ -e "${batups}" ] || continue
    batifupf="${batups#*${ifnameseparator}}" ; batifupf="${batifupf%%${ifnameseparator}*}"
    if [[ "$batinterfaces" =~ "${batifupf}" ]]; then
      wert='2'
     else
      wert='0'
      logger -s -t "neanderfunk-linkcheck" -p 5 batman interface ${batifupf} gone missing
     fi
    linkname='batinterfaces'
    check=${batifupf}
    valuecheck ${check}
   done

  # check if all previously seen interface, are there batman (inhood-file) and did they disappear later?
  batmanoriginatorsfile="/tmp/linkcheck.batmanoriginators.list"
  batctl o|tail -n +3>${batmanoriginatorsfile}
  checkgroup='batman_originators'
  for batups in ${batupfiles}; do
    check_disabled "$checkgroup" && break
    [ -e "${batups}" ] || continue
    # cut on ${ifnameseparator}, field 2 - same as the loop above. This still
    # cut on "." from back when the separator was a dot (changed in 4942b30),
    # so with the comma separator there is no third dot-field at all:
    # batifupf came out empty, [[ ! "$x" =~ "" ]] is false because an empty
    # regex matches anything, and this whole originator check never ran.
    batifupf="${batups#*${ifnameseparator}}" ; batifupf="${batifupf%%${ifnameseparator}*}"
    if [[ ! "$wifibatlinks" =~ "${batifupf}" ]]; then    # do not check for wifimesh links as check/reboot condition!
#      echo check if by file: ${batifupf} # individually previsously seen file
      bators=$(grep -c -- "${batifupf}" "${batmanoriginatorsfile}")
      # Hier stand eine eigene Zeile "on bat if <if> : <n> originators", bei
      # jedem Lauf und je Interface. Sie ist ersatzlos entfallen: dieselbe Zahl
      # landet zwei Zeilen weiter ueber valuecheck als
      # "batman.originators.<if>:<n>" in der Zusammenfassung. Zwei Zeilen je
      # Lauf fuer nichts, in einem Puffer, der nur gut zwei Stunden zurueck
      # reicht.
      wert=${bators}
      linkname='batman.originators'
      check=${batifupf}
      valuecheck ${check}
     fi
   done

## 4) bridges and the ports in them
#
# Read from /sys/class/net/<bridge>/brif. That is exact; parsing brctl's
# whitespace columns (cut -c 100-) depends on the width of the bridge name and
# id and silently yields nothing when they differ.
#
# The port half of this used to exist a second time in neanderfunk-hotfix. It
# lives here now - a port dropping out of its bridge is a link question, and
# two independent copies would have escalated the same outage twice.
if ! check_disabled bridges || ! check_disabled bridge_ports ; then
  bridges_now=""
  for brif in /sys/class/net/*/brif ; do
    [ -d "$brif" ] || continue
    b="${brif%/brif}" ; b="${b##*/}"
    bridges_now="$bridges_now $b"
    : > "/tmp/linkcheck.bridge-seen.$b"
    for port in "$brif"/* ; do
      [ -e "$port" ] || continue
      : > "/tmp/linkcheck.brport-seen.$b.${port##*/}"
    done
  done

  if ! check_disabled bridges ; then
    checkgroup='bridges'
    linkname='bridge'
    for f in /tmp/linkcheck.bridge-seen.* ; do
      [ -e "$f" ] || continue
      b="${f#/tmp/linkcheck.bridge-seen.}"
      case " $bridges_now " in
        *" $b "*) wert=2 ;;
        *) wert=0 ; logger -s -t "neanderfunk-linkcheck" -p 5 "[bridges] bridge $b gone missing" ;;
      esac
      check="$b"
      valuecheck "$check"
    done
  fi

  if ! check_disabled bridge_ports ; then
    checkgroup='bridge_ports'
    linkname='bridgeport'
    for f in /tmp/linkcheck.brport-seen.* ; do
      [ -e "$f" ] || continue
      rest="${f#/tmp/linkcheck.brport-seen.}"
      b="${rest%%.*}"
      port="${rest#*.}"
      if [ -e "/sys/class/net/$b/brif/$port" ] ; then
        wert=2
      else
        wert=0
        logger -s -t "neanderfunk-linkcheck" -p 5 "[bridge_ports] $port dropped out of bridge $b"
      fi
      # ifnameseparator, not ":" - see its definition above, the file itself
      # warns that ":" may cause issues in these marker file names
      check="${b}${ifnameseparator}${port}"
      valuecheck "$check"
    done
  fi
fi

## 5) wifi mesh neighbours per mesh interface
#
# Moved here from neanderfunk-hotfix: "did this radio lose all its neighbours"
# is a link question. valuecheck already implements exactly the rule we want -
# arm at >=2 seen, then escalate when it drops to none.
checkgroup='mesh_neighbours'
if ! check_disabled "$checkgroup" ; then
  linkname='meshpeers'
  mesh_radios=' '
  set -f ; oldifs="$IFS" ; IFS='
'
  for l in $NF_UCI_wireless ; do
    case "$l" in
      wireless.mesh_radio[0-9]*|wireless.ibss_radio[0-9]*)
        l="${l#wireless.}" ; l="${l%%[.=]*}"
        case "$mesh_radios" in *" $l "*) ;; *) mesh_radios="$mesh_radios$l " ;; esac
        ;;
    esac
  done
  IFS="$oldifs" ; set +f
  for mesh_radio in $mesh_radios ; do
    nf_uci_get "$NF_UCI_wireless" "wireless.${mesh_radio}.device" ; radio="$NF_VAL"
    nf_uci_get "$NF_UCI_wireless" "wireless.${radio}.disabled" && [ "$NF_VAL" = "1" ] && continue
    nf_uci_get "$NF_UCI_wireless" "wireless.${mesh_radio}.disabled" && [ "$NF_VAL" = "1" ] && continue
    nf_uci_get "$NF_UCI_wireless" "wireless.${mesh_radio}.ifname" || continue
    dev="$NF_VAL"
    iface_is_up "$dev" || continue
    # iw can hang on a wedged radio, so run it in the background and give up
    # after 20s rather than stalling the whole run
    out="/tmp/linkcheck.meshpeers.${mesh_radio}.count"
    ( iw dev "$dev" station dump 2>/dev/null | grep -c "^Station " > "$out" ) &
    p=$!
    n=0
    while [ $n -lt 20 ] && kill -0 $p 2>/dev/null ; do sleep 1 ; n=$((n + 1)) ; done
    if kill -0 $p 2>/dev/null ; then
      kill -9 $p 2>/dev/null
      logger -s -t "neanderfunk-linkcheck" -p 5 "[mesh_neighbours] iw dev $dev station dump hangs, skipped"
      continue
    fi
    wert='' ; [ -r "$out" ] && read -r wert < "$out"
    case "$wert" in ''|*[!0-9]*) continue ;; esac
    check="${mesh_radio}"
    valuecheck "$check"
  done
fi

# Nur noch loggen, wenn sich der Zustand geaendert hat - sonst hoechstens
# stuendlich als Lebenszeichen. Siehe log_status() in common.sh: diese eine
# Zeile war mit rund 500 Bytes je Lauf der groesste laufende Posten im
# Logpuffer und hat damit genau die Meldungen verdraengt, die man nach einer
# Stoerung sucht.
log_status summary "${sigstring}" "${logstring}"

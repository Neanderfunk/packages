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
    [ "${wert}" -gt "1" ] && echo $(date) > "${pb}.inhood"
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
        wifi config
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
      reboot -f
      # reboot -f does not necessarily return immediately
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


# 1) running over existing batman-interface, looking for direct neighbors
checkgroup='batadv_neighbours'
if ! check_disabled "$checkgroup" ; then
batversion=$(batctl -v |cut -d" " -f 2|grep -o '[0-9]\+'| tr -d '\012\015')
# an unparsable version must not turn the comparison below into a shell error;
# everything current is far past that threshold anyway
case "$batversion" in ''|*[!0-9]*) batversion=999999 ;; esac
linkname='batadv'
batmeshs=$(batctl if|cut -d":" -f 1|tr '\n' ' ')
for batm in ${batmeshs}; do
  # tail -n +3 strips the two header lines, as section 3 already does. Without
  # it the grep also matched the first one, which names the primary interface
  # ("MainIF/MAC: primary0/42:6b:..."): primary0 then reported a phantom
  # neighbour count of 1 - awk pulled the word "adv" out of that header - even
  # though batctl n lists no neighbour for it at all. It never escalated only
  # because arming needs >=2 and the phantom count is always exactly 1.
  if [ "$batversion" -gt 20163 ] ; then
   result=$(batctl n|tail -n +3|grep ${batm}|awk '{print $2}'|sort|uniq|wc -l)
  else
   result=$(batctl -n|tail -n +3|grep ${batm}|awk '{print $2}'|sort|uniq|wc -l)
  fi
  check=${batm}
  wert=$result
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
gluontarget=$(cat /etc/openwrt_release|grep DISTRIB_TARGET|cut -d"=" -f2|tr -d \'|cut -d/ -f1)
# Is this netdev actually up? uci's "disabled" flag is not enough: on a
# COVR-X1860 mesh_radio1 has disabled='0' and a netdev, but operstate "down",
# because radio1 sits on channel "auto" and a mesh interface needs a fixed one.
# Scanning or polling such an interface always yields zero - and a radio that
# had armed before it went down would escalate all the way to a reboot just
# because someone switched it off. A radio that is merely deaf is still
# operationally up, so this does not hide the case these checks exist for.
iface_is_up() {
  # $1: ifname
  case "$(cat "/sys/class/net/$1/operstate" 2>/dev/null)" in
    up) return 0 ;;
  esac
  return 1
}

radio_is_wifi6() {
  # $1: ifname
  #
  # Die Frage, um die es hier eigentlich geht, ist nicht "ist das ein mt7915",
  # sondern "zerlegt ein Scan auf diesem Radio seine Mesh-Links". Das haengt an
  # der Faehigkeit des Radios, nicht am Treibernamen - und ab OpenWrt 24.10
  # steht die Faehigkeit im Klartext in /etc/board.json:
  #
  #   .wlan.<phy>.info.bands.<2G|5G|6G>.he    Wi-Fi 6
  #   .wlan.<phy>.info.bands.<...>.eht        Wi-Fi 7
  #
  # Geschrieben wird der Abschnitt von wifi-detect.uc beim Booten. Die
  # Zuordnung Interface -> phy kommt aus dem sysfs und muss ebenfalls nicht
  # geraten werden: /sys/class/net/<if>/phy80211/name.
  local phy band
  phy="$(cat "/sys/class/net/$1/phy80211/name" 2>/dev/null)"
  if [ -n "$phy" ] && [ -r /etc/board.json ] ; then
    for band in 2G 5G 6G ; do
      case "$(jsonfilter -i /etc/board.json -e "@.wlan['$phy'].info.bands['$band'].he" 2>/dev/null)" in
        true) return 0 ;;
      esac
    done
    # board.json kennt den phy, sagt aber kein HE -> belastbares Nein, kein
    # Rueckfall auf die Heuristik.
    if [ -n "$(jsonfilter -i /etc/board.json -e "@.wlan['$phy'].path" 2>/dev/null)" ] ; then
      return 1
    fi
  fi

  # Rueckfall fuer Staende ohne den wlan-Abschnitt in board.json - auf Gluon
  # 2023.2.x fehlt er komplett, dort entsteht er mangels wifi-detect.uc nie.
  # Erst nach dem Kernelmodul fragen, nicht nach dem Treibernamen: auf einem
  # ZyXEL NWA50AX Pro (mediatek/filogic) sitzen die Radios im SoC und der
  # Treiber heisst "mt798x-wmac", das Modul ist aber dasselbe mt7915e wie auf
  # der COVR. Der Treibername allein verfehlt jeden filogic-Knoten.
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
  # Zwei Luecken hatte sie: owe_radio* kam ueberhaupt nicht vor, OWE-Interfaces
  # wurden also nie geprueft - und ab Gluon 2025.1 kann ein Geraet mehr als drei
  # Radios haben (Release Notes zu #3563), die dann stumm durchgefallen waeren.
  #
  # Jetzt aus uci: was konfiguriert ist, weiss uci, nicht wir. Die Praefixe sind
  # bewusst aufgezaehlt statt "alles mit ifname" - wan_radio* (privates WLAN)
  # gehoert nicht in diese Pruefung.
  links=$(uci show wireless 2>/dev/null \
    | grep -E "^wireless\.(client|owe|mesh|batmesh|ibss)_radio[0-9]+\.ifname=" \
    | cut -d. -f1-2 | awk '!seen[$0]++')
  for link in $links; do
    linkname=$(uci get $link.ifname 2>/dev/null)
    if [ ! -z "${linkname}" ] ; then
      linksexist="$linksexist $link"
     fi
  done
  # alte scans wegr??umen
  rm /tmp/linkcheck.iwscan.* 2>/dev/null
  for linkexist in $linksexist; do
    linkname=$(uci get $linkexist.ifname)
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
    iwfile=/tmp/linkcheck.iwscan.$(uci get $linkexist.device)
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
    bsses=$(cat $iwfile|grep "BSS .*:.*:.*:.*:.*:.*(on.*)"|wc -l)
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
      wert=$(eval echo \$${check})
      valuecheck ${check}
     done
   done
 fi

# 3) check for disappearing batman-interfaces
  # (a companion list "wirebatlinks" used to sit here, assigned and never read)
  # Ausnahmeliste, keine Prueflste: was hier drinsteht, wird vom
  # Originator-Check weiter unten NICHT als Reboot-Bedingung gewertet. Ein
  # fehlender Eintrag heisst also nicht "wird uebersehen", sondern "wird
  # mitgeprueft und kann bis zum Reboot eskalieren" - deshalb ist das die
  # einzige der festen Listen, deren Luecke teuer war. Fest standen hier mesh0
  # bis mesh3; ab Gluon 2025.1 kann ein Geraet mehr Radios haben.
  wifibatlinks=$(uci show wireless 2>/dev/null \
    | grep -E "^wireless\.(mesh|ibss|batmesh)_radio[0-9]+\.ifname=" \
    | sed "s/.*='//;s/'$//" | tr '\n' ' ')
  # Liefert uci nichts - kein wireless-Config, kaputtes uci -, dann lieber die
  # alte feste Liste als eine leere: eine leere Ausnahmeliste wuerde die
  # WLAN-Mesh-Interfaces in die Reboot-Bedingung hineinnehmen.
  [ -n "$(echo $wifibatlinks)" ] || wifibatlinks='mesh0 mesh1 mesh2 mesh3'

  # inventory of bat-interfaces, from all possible sources, probably unneccesary
  batinterfaces2=$(batctl n|tail -n +3|awk '{print $1}'|sort|uniq)
  batinterfaces1=$(batctl if|cut -d: -f1|sort|uniq)
  batinterfaces3=$(echo "${batinterfaces1} ${batinterfaces2}")
  batinterfaces=$(for b in ${batinterfaces3}; do echo ${b}; done|sort|uniq)
#  echo batinterfaces $batinterfaces

  # create flag files in /tmp
  for batinterface in ${batinterfaces}; do
    echo $(date)>/tmp/linkcheck.batinterface${ifnameseparator}${batinterface}${ifnameseparator}up
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
    batifupf=$(echo ${batups}|cut -d${ifnameseparator} -f2)
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
    batifupf=$(echo ${batups}|cut -d${ifnameseparator} -f2)
    if [[ ! "$wifibatlinks" =~ "${batifupf}" ]]; then    # do not check for wifimesh links as check/reboot condition!
#      echo check if by file: ${batifupf} # individually previsously seen file
      bators=$(cat ${batmanoriginatorsfile}|grep ${batifupf}|wc -l)
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
    b="$(basename "$(dirname "$brif")")"
    bridges_now="$bridges_now $b"
    touch "/tmp/linkcheck.bridge-seen.$b"
    for port in $(ls "$brif" 2>/dev/null) ; do
      touch "/tmp/linkcheck.brport-seen.$b.$port"
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
  for mesh_radio in $(uci show wireless 2>/dev/null | grep -E -o '(ibss|mesh)_radio[0-9]+' | awk '!seen[$0]++') ; do
    radio="$(uci -q get wireless.${mesh_radio}.device)"
    [ "$(uci -q get wireless.${radio}.disabled)" = "1" ] && continue
    [ "$(uci -q get wireless.${mesh_radio}.disabled)" = "1" ] && continue
    dev="$(uci -q get wireless.${mesh_radio}.ifname)"
    [ -z "$dev" ] && continue
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
    wert="$(cat "$out" 2>/dev/null)"
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

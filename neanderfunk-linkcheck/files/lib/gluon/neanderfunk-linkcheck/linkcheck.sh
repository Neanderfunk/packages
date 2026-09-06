#! /bin/sh
# Link and topology checks: does this node still have the neighbours, batman
# interfaces and bridge ports it had before? See common.sh for the uci keys.

. /lib/gluon/neanderfunk-linkcheck/common.sh

valuecheck ()
# this checks for multiple problems on the same IF, tries to resolve, or reboots as last resort
{
  logstring=${logstring}" "${linkname}"."${check}":"${wert}
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
      if [ -n "${wifi_restarted}" ] ; then
        logger -s -t "neanderfunk-linkcheck" -p 5 "[${checkgroup}] lost neighbours 3rd: ${linkname}.${check}, wifi already restarted this run"
      else
        logger -s -t "neanderfunk-linkcheck" -p 5 "[${checkgroup}] lost neighbours 3rd: ${linkname}.${check}, wifi restart"
        wifi_restarted=1
        wifi down
        killall hostapd >/dev/null 2>&1
        rm -f /var/run/wifi-*.pid >/dev/null 2>&1
        wifi config
        wifi up
        sleep 15
      fi
      ;;
    *)
      logger -s -t "neanderfunk-linkcheck" -p 5 "[${checkgroup}] lost neighbours 4th: ${linkname}.${check}, rebooting!"
      sleep 10
      upgrade_started='/tmp/autoupdate.lock'
      [ -f ${upgrade_started} ] && exit
      # not within the first linkcheck.settings.reboot_uptime_min minutes of
      # uptime. The .inhood arming already bounds an outage to one reboot (the
      # markers live in /tmp), this keeps the rate down on top.
      uptime_ok || exit
      reboot -f
      # reboot -f does not necessarily return immediately
      exit
      ;;
  esac
}
## script start

#do not run run while node is firmware flashing
upgrade_started='/tmp/autoupdate.lock'
[ -f ${upgrade_started} ] && exit

ifnameseparator=','  # charcters like . - # or even : may cause issues


# 1) running over existing batman-interface, looking for direct neighbors
checkgroup='batadv_neighbours'
if ! check_disabled "$checkgroup" ; then
batversion=$(batctl -v |cut -d" " -f 2|grep -o '[0-9]\+'| tr -d '\012\015')
linkname='batadv'
batmeshs=$(batctl if|cut -d":" -f 1|tr '\n' ' ')
for batm in ${batmeshs}; do
  if [ $batversion -gt 20163 ] ; then
   result=$(batctl n|grep ${batm}|awk '{print $2}'|sort|uniq|wc -l)
  else
   result=$(batctl -n|grep ${batm}|awk '{print $2}'|sort|uniq|wc -l)
  fi
  check=${batm}
  wert=$result
  valuecheck ${check}
done
fi

# 2) running over wifimesh-interfaces, looking for other SSIDs on the same wifi via iwscan lowpri

# do not run on mediatek (filogic...) devices, since it seems to break meshlinks.
gluontarget=$(cat /etc/openwrt_release|grep DISTRIB_TARGET|cut -d"=" -f2|tr -d \'|cut -d/ -f1)
checkgroup='bsses'
if [ "$gluontarget" != "mediatek" ] && ! check_disabled "$checkgroup" ; then
  checks=''
  linksexist=''
  links='wireless.mesh_radio0 wireless.batmesh_radio0 wireless.mesh_radio1 wireless.batmesh_radio1 wireless.mesh_radio2 wireless.batmesh_radio2 wireless.client_radio0 wireless.client_radio1 wireless.client_radio2'
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
    iwfile=/tmp/linkcheck.iwscan.$(uci get $linkexist.device)
    if [ ! -f $iwfile ] ; then
      sleep 4
      iw dev ${linkname} scan lowpri passive > $iwfile
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
  wirebatlinks='mesh-vpn primary0 br-mesh_other br-mesh_lan br-mesh_wan br-wan br-lan br-mesh_other1 br-mesh_other2 br-mesh_other3 br-mesh_other4 br-mesh_other5'
  wifibatlinks='mesh0 mesh1 mesh2 mesh3'

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
      logger -s -t "neanderfunk-linkcheck" -p 5 on bat if ${batifupf} : ${bators} originators
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
      check="$b:$port"
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

logger -s -t "neanderfunk-linkcheck" -p 5 ${logstring}

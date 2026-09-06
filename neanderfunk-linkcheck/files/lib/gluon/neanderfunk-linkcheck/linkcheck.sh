#! /bin/sh
#
# Every single check can be switched off on a node:
#     uci set linkcheck.<check>.disabled='1' ; uci commit linkcheck
# The <check> name is part of the reason logged before a wifi restart or a
# reboot, so it can be read off `logread -f` while watching a node.
# `uci show linkcheck` lists the available names.
#
# How long after a boot no check may reboot (minutes, default 60):
#     uci set linkcheck.settings.reboot_uptime_min='90' ; uci commit linkcheck
# It can be preset community-wide from the site.conf, see
# /lib/gluon/upgrade/500-neanderfunk-linkcheck and the README.
#
# These helpers are deliberately duplicated from neanderfunk-hotfix rather than
# shared: the two packages are independent and neither may need the other
# installed.

# true when the named check is switched off on this node
check_disabled() {
	if [ "$(uci -q get linkcheck."$1".disabled)" = "1" ] ; then
		return 0
	fi
	return 1
}

# minimum uptime in seconds before a check may reboot; unset or non-numeric
# falls back to the 60 minutes this used to be hardcoded to
uptime_ok() {
	local m
	m="$(uci -q get linkcheck.settings.reboot_uptime_min)"
	case "$m" in
		''|*[!0-9]*) m=60 ;;
	esac
	[ "$(sed 's/\..*//g' /proc/uptime)" -gt "$((m * 60))" ]
}

# Count consecutive failures: strike <prefix> records one more and prints how
# many there are now. One marker file per strike rather than a single counter
# file on purpose - a counter file is truncated on every write, so being killed
# in that window resets the count to zero.
strike() {
	local n=1
	while [ -e "$1.$n" ] ; do n=$((n + 1)) ; done
	touch "$1.$n"
	echo "$n"
}

unstrike() {
	rm -f "$1".* 2>/dev/null
}

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
      logger -s -t "neanderfunk-linkcheck" -p 5 "[${checkgroup}] lost neighbours 3rd: ${linkname}.${check}, wifi restart"
      wifi down
      killall hostapd >/dev/null 2>&1
      rm -f /var/run/wifi-*.pid >/dev/null 2>&1
      wifi config
      wifi up
      sleep 15
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

## 4) check for disappearing bridge interfaces
#
# get current bridges
  bridgeslist=$(brctl show |cut -f1|sort -u|sed '/^\s*$/d'|grep -v "bridge name")
  # create flag files in /tmp
  for bridgename in ${bridgeslist}; do
    echo $(date)>/tmp/linkcheck.bridge${ifnameseparator}${bridgename}${ifnameseparator}up
    interfaces=$(brctl show ${bridgename}|sed -e 's/\t/                     /g'|cut -c 100-|sed -e 's/ //g'|tail -n +2)
    for interface in ${interfaces}; do
      echo $(date)>/tmp/linkcheck.bridgeif${ifnameseparator}${bridgename}${ifnameseparator}port${ifnameseparator}${interface}${ifnameseparator}up
     done
   done

  # get all previously seen bridges by flag files
  for upbridgesf in "/tmp/linkcheck.bridge${ifnameseparator}*${ifnameseparator}up"; do
    :
#    echo file # $upbridgesf
   done
#  echo upbridgesf ${upbridgesf}
  # check if all prviously seen are in current list
  checkgroup='bridges'
  for upbridgef in ${upbridgesf}; do
    check_disabled bridges && check_disabled bridge_ports && break
    [ -e "${upbridgef}" ] || continue
    upbridge=$(echo ${upbridgef}|cut -d${ifnameseparator} -f2)
#    echo check if by file: ${upbridge} # individually previsously seen file
    if [[ "${bridgeslist}" =~ "${upbridge}"   ]]; then
       wert='2'
#       echo ${upbridge} is golden
      else
       wert='0'
       logger -s -t "neanderfunk-linkcheck" -p 5 bridge ${upbridge} gone missing
      fi
     linkname=bridgeinterfaces
     check=${upbridge}
     checkgroup='bridges'
     check_disabled bridges || valuecheck ${check}
     for interfacesf in "/tmp/linkcheck.bridgeif${ifnameseparator}${upbridge}${ifnameseparator}port${ifnameseparator}*${ifnameseparator}up"; do
       :
      done
#     echo file  ${interfacesf}
     checkgroup='bridge_ports'
     for interfacef in ${interfacesf}; do
       check_disabled bridge_ports && break
       [ -e "${interfacef}" ] || continue
       interfaced=$(echo ${interfacef}|cut -d${ifnameseparator} -f4)
#       echo testing ${upbridge}:${interfaced}
       interfaces=$(brctl show ${upbridge}|sed -e 's/\t/                     /g'|cut -c 100-|sed -e 's/ //g'|tail -n +2)
#       echo ${interfaces}
       if [[ "${interfaces}" =~ "${interfaced}" ]]; then
         wert='2'
#         echo ${upbridge}:${interfaced} is golden
        else
         wert='0'
         logger -s -t "neanderfunk-linkcheck" -p 5 bridge-member ${upbridge}:${interfaced} gone missing
        fi
        linkname=bridgeinterfaceports
        check=${upbridge}:${interfaced}
        valuecheck ${check}
      done
   done
logger -s -t "neanderfunk-linkcheck" -p 5 ${logstring}

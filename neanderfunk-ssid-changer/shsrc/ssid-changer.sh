#!/bin/sh
# neanderfunk-ssid-changer, Shell-Fassung fuer die Sackgasse 2021.1 (OpenWrt 19.07).
# Jede Minute: ohne Gateway (bzw. TQ unter tq_limit_min) wechselt die Client-SSID
# nach switch_timeframe auf die Offline-SSID, mit Gateway zurueck.
#
# Warum Shell und nicht die Lua-Fassung aus v2025.1.x: die schaltet ueber das
# uci-Delta plus "wifi reconf", das kennt 19.07 nicht (nur config/up/down/
# reload/status) - es bliebe ein kompletter WLAN-Neustart je Wechsel; dazu
# jede Minute die Lua-Laufzeit auf 4/32.
#
# Umschalten: SSID in /var/run/hostapd-phyN.conf tauschen und HUP. hostapd
# reagiert darauf oft NICHT (adorfer); deshalb danach an der laufenden
# Schnittstelle (iwinfo ESSID) pruefen und sonst hart neu starten (wifi down,
# killall hostapd, wifi up) unter der gemeinsamen WLAN-Sperre. Damit der harte
# Neustart, der die hostapd-Konfiguration aus uci neu baut, die richtige SSID
# nimmt, steht die Offline-SSID zusaetzlich im uci-Delta von
# wireless.client_radioN.ssid (nie committet; zurueck per uci revert) - wie in
# v2025.1.x. Die Online-SSID kommt deshalb aus der committeten
# /etc/config/wireless, nicht aus "uci show".

safety_exit() {
	echo $1, exiting with error code 2
	exit 2
}
flock -n /var/lock/autoupdater.lock true 2>/dev/null || safety_exit 'autoupdater running'
UT=$(cut -d. -f1 /proc/uptime)
[ $UT -gt 60 ] || safety_exit 'less than one minute'
ls /var/run/hostapd-phy*.conf >/dev/null 2>&1 || safety_exit 'no hostapd-phy*'

# only once every timeframe minutes the SSID will change to the Offline-SSID
# (set to 1 minute to change immediately every time the router gets offline)
MINUTES="$(uci -q get ssid-changer.settings.switch_timeframe)"
: ${MINUTES:=30}

# the first few minutes directly after reboot within which an Offline-SSID always may be activated
# (must be <= switch_timeframe)
FIRST="$(uci -q get ssid-changer.settings.first)"
: ${FIRST:=5}

# the Offline-SSID will start with this prefix use something short to leave space for the nodename
# (no '~' allowed!)
PREFIX="$(uci -q get ssid-changer.settings.prefix)"
: ${PREFIX:='FF_Offline_'}

# every OpenWrt spelling of false/true (backport of v2025.1.x 45f6829)
case "$(uci -q get ssid-changer.settings.enabled)" in
	0|false|no|off|disabled) DISABLED='1' ;;
	*) DISABLED='0' ;;
esac

# generate the ssid with either 'nodename', 'mac' or to use only the prefix set to 'none'
SETTINGS_SUFFIX="$(uci -q get ssid-changer.settings.suffix)"
: ${SETTINGS_SUFFIX:='nodename'}

if [ $SETTINGS_SUFFIX = 'nodename' ]; then
	SUFFIX="$(uname -n)"
	# 32 would be possible as well
	if [ ${#SUFFIX} -gt $((30 - ${#PREFIX})) ]; then
		# calculate the length of the first part of the node identifier in the offline-ssid
		HALF=$(( (28 - ${#PREFIX} ) / 2 ))
		# jump to this charakter for the last part of the name
		SKIP=$(( ${#SUFFIX} - $HALF ))
		# use the first and last part of the nodename for nodes with long name
		SUFFIX=${SUFFIX:0:$HALF}...${SUFFIX:$SKIP:${#SUFFIX}}
	fi
elif [ $SETTINGS_SUFFIX = 'mac' ]; then
	SUFFIX="$(uci -q get network.bat0.macaddr | /bin/sed 's/://g')"
else
	# 'none'
	SUFFIX=''
fi


OFFLINE_SSID="$PREFIX$SUFFIX"

# Online-SSID eines client_radioN aus der committeten Konfiguration
committed_ssid() {
	awk -v sec="$1" -v q="'" '
		/^config / { f = (index($0, q sec q) > 0) ; next }
		f && $1 == "option" && $2 == "ssid" {
			sub(/^[ \t]*option[ \t]+ssid[ \t]+/, ""); gsub("^" q "|" q "$", ""); print; exit
		}' /etc/config/wireless
}

# Counters since boot for respondd (backport of v2025.1.x 4f48c2d, same files
# as the Lua version): offline state, switches to the offline SSID, gateway losses
C_OFF=/tmp/ssid-changer-offline
C_SW=/tmp/ssid-changer-offline-switches
C_GW=/tmp/ssid-changer-gateway-losses
for f in $C_OFF $C_SW $C_GW; do [ -f $f ] || echo 0 > $f; done
count_event() {
	n=$(cat $1 2>/dev/null)
	case "$n" in ''|*[!0-9]*) n=0 ;; esac
	echo $((n + 1)) > $1
}

# temp file to count the offline incidents during switch_timeframe
TMP=/tmp/ssid-changer-count
[ -f $TMP ] || echo 0 > $TMP
OFF_COUNT=$(cat $TMP)
# an empty or broken counter file (killed while writing) counts as 0
case "$OFF_COUNT" in ''|*[!0-9]*) OFF_COUNT=0 ;; esac

# every OpenWrt spelling of true (backport of v2025.1.x 45f6829)
case "$(uci -q get ssid-changer.settings.tq_limit_enabled)" in
	1|true|yes|on|enabled) TQ_LIMIT_ENABLED=1 ;;
	*) TQ_LIMIT_ENABLED=0 ;;
esac

if [ $TQ_LIMIT_ENABLED = 1 ]; then
	# upper limit, above that the online SSID will be used; lower limit, below
	# that the offline SSID; in between nothing changes (no toggling)
	TQ_LIMIT_MAX="$(uci -q get ssid-changer.settings.tq_limit_max)"
	: ${TQ_LIMIT_MAX:='45'}
	TQ_LIMIT_MIN="$(uci -q get ssid-changer.settings.tq_limit_min)"
	: ${TQ_LIMIT_MIN:='35'}
	GATEWAY_TQ=$(batctl gwl | grep -e "^=>" -e "^\*" | awk -F '[()]' '{print $2}' | tr -d " ")
	case "$GATEWAY_TQ" in ''|*[!0-9]*) GATEWAY_TQ=0 ;; esac
	MSG="TQ is $GATEWAY_TQ, "
	if [ $GATEWAY_TQ -ge $TQ_LIMIT_MAX ]; then
		CHECK=1
	elif [ $GATEWAY_TQ -lt $TQ_LIMIT_MIN ]; then
		CHECK=0
	else
		echo "TQ is $GATEWAY_TQ, do nothing"
		exit 0
	fi
else
	MSG=""
	CHECK="$(batctl gwl -H | grep -v "gateways in range" | wc -l)"
fi

# gateway loss = had a gateway on the last run, has none now
GWNOW=0; [ "$CHECK" -gt 0 ] && GWNOW=1
[ "$(cat /tmp/ssid-changer-gwstate 2>/dev/null)" = 1 ] && [ $GWNOW = 0 ] && count_event $C_GW
echo $GWNOW > /tmp/ssid-changer-gwstate

UP=$(($UT / 60))
M=$(($UP % $MINUTES))

# nur Konfigurationen eines vorhandenen phy (nach einem Neuladen des Treibers
# bleiben alte hostapd-phyN.conf liegen)
live_phy() {
	P=${1#/var/run/hostapd-}
	[ -d /sys/class/ieee80211/${P%.conf} ]
}

# switch_to <online|offline>: SSID in jeder hostapd-Konfiguration und im
# uci-Delta tauschen; setzt CHANGED
switch_to() {
	for HOSTAPD in /var/run/hostapd-phy*.conf; do
		live_phy $HOSTAPD || continue
		IFC=$(grep -m1 '^interface=' $HOSTAPD | cut -d= -f2)
		N=${IFC#client}
		case "$N" in ''|*[!0-9]*) continue ;; esac
		ONLINE_SSID=$(committed_ssid client_radio$N)
		[ -n "$ONLINE_SSID" ] || continue
		if [ "$1" = online ]; then FROM=$OFFLINE_SSID; TO=$ONLINE_SSID; else FROM=$ONLINE_SSID; TO=$OFFLINE_SSID; fi
		if grep -qxF "ssid=$TO" $HOSTAPD; then
			echo "SSID $TO on $IFC is correct, nothing to do"
			continue
		fi
		if grep -qxF "ssid=$FROM" $HOSTAPD; then
			logger -s -t "neanderfunk-ssid-changer" -p 5 "$MSG$2SSID on $IFC is $FROM, change to $TO"
			sed -i "s~^ssid=$FROM\$~ssid=$TO~" $HOSTAPD
			if [ "$1" = online ]; then
				uci -q revert wireless.client_radio$N.ssid
			else
				uci -q set wireless.client_radio$N.ssid="$TO"
			fi
			CHANGED=1
		else
			logger -s -t "neanderfunk-ssid-changer" -p 5 "could not set to $1 state on $IFC: found neither '$ONLINE_SSID' nor '$OFFLINE_SSID'"
		fi
	done
}

# laufende SSID an jedem Client-Interface gleich der in der Konfiguration?
# Live nur per "iw dev <if> info" (nl80211 vom Kernel): iwinfo liest die SSID
# eines AP-Interfaces aus der hostapd-Konfigurationsdatei und zeigt damit die
# neue SSID, auch wenn hostapd den HUP verschluckt hat (am WR841N v9 gesehen).
ssid_live_ok() {
	for HOSTAPD in /var/run/hostapd-phy*.conf; do
		live_phy $HOSTAPD || continue
		IFC=$(grep -m1 '^interface=' $HOSTAPD | cut -d= -f2)
		WANT=$(grep -m1 '^ssid=' $HOSTAPD | cut -d= -f2-)
		[ -n "$IFC" ] || continue
		iw dev "$IFC" info 2>/dev/null | grep -qxF "	ssid $WANT" || return 1
	done
	return 0
}

restart_wifi() {
	exec 201>>/var/lock/neanderfunk-wifi.lock
	if flock -n 201; then
		logger -s -t "neanderfunk-ssid-changer" -p 5 "$1, restarting wifi"
		wifi down
		killall hostapd >/dev/null 2>&1
		rm -f /var/run/wifi-*.pid
		wifi config
		wifi up
		exec 201>&-
	else
		logger -s -t "neanderfunk-ssid-changer" -p 5 "$1, another check is restarting wifi"
	fi
}

CHANGED=''
if [ "$CHECK" -gt 0 ] || [ "$DISABLED" = '1' ]; then
	echo "node is online"
	switch_to online ''
	echo 0 > $C_OFF
elif [ "$CHECK" -eq 0 ]; then
	echo "node is considered offline"
	# set SSID offline only if uptime is less than FIRST or exactly a multiple
	# of switch_timeframe, and only if offline more than half the time
	if [ $UP -lt $FIRST ] || [ $M -eq 0 ]; then
		if [ $UP -lt $FIRST ]; then T=$FIRST; else T=$MINUTES; fi
		if [ $OFF_COUNT -ge $(($T / 2)) ]; then
			switch_to offline "$OFF_COUNT times offline, "
			[ -n "$CHANGED" ] && count_event $C_SW
		fi
	fi
	echo "$(($OFF_COUNT + 1))" > $TMP
	for HOSTAPD in /var/run/hostapd-phy*.conf; do
		live_phy $HOSTAPD && grep -qxF "ssid=$OFFLINE_SSID" $HOSTAPD && echo 1 > $C_OFF
	done
fi

if [ -n "$CHANGED" ]; then
	# send HUP to all hostapd to load the new SSID, then check whether it
	# took - hostapd often ignores the HUP
	killall -HUP hostapd
	sleep 5
	ssid_live_ok || restart_wifi "hostapd ignored the HUP"
	echo "HUP!"
	rm -f /tmp/ssid-changer-mismatch
elif ! ssid_live_ok; then
	# Konfiguration und laufende SSID weichen ab, ohne dass hier gerade
	# umgeschaltet wurde (verschluckter HUP eines frueheren Laufs, Neustart
	# von aussen): beim zweiten Lauf in Folge hart neu starten
	if [ -f /tmp/ssid-changer-mismatch ]; then
		rm -f /tmp/ssid-changer-mismatch
		restart_wifi "running SSID differs from the hostapd config"
	else
		: > /tmp/ssid-changer-mismatch
	fi
else
	rm -f /tmp/ssid-changer-mismatch
fi

if [ $M -eq 0 ]; then
	# set counter to 0 if the timeframe is over
	echo 0 > $TMP
fi

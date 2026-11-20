#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# Wann neanderfunk-hvblocator laeuft.
#
#   run.sh boot   aus /etc/init.d: nach dem Start warten, bis batman einen
#                 Nachbarn hat (hoechstens BOOT_WAIT s Uptime), dann melden.
#                 Die LAN-Mesh-Pruefung braucht kein Internet.
#   run.sh cron   aus micron.d, stuendlich: melden, wenn die letzte Meldung
#                 OK_INTERVAL (Erfolg) bzw. FAIL_INTERVAL (Fehlschlag) her
#                 ist. Zeiten als Uptime, nicht als Uhrzeit.
#
# Ohne neanderfunk_hvblocator.urls in der aktiven Domain endet es sofort.

OK_INTERVAL=86400
FAIL_INTERVAL=21600
BOOT_WAIT=600
STAMP=/tmp/neanderfunk-hvblocator.stamp
LOCK=/tmp/neanderfunk-hvblocator.lock

. /lib/gluon/neanderfunk/site.sh

[ -n "$(nf_site_get '@.neanderfunk_hvblocator.urls[0]')" ] || exit 0
[ "$(uci -q get gluon-setup-mode.@setup_mode[0].configured)" = 1 ] || exit 0

uptime_s() {
	local up rest
	read up rest < /proc/uptime
	echo "${up%%.*}"
}

case "$1" in
boot)
	sleep 60
	while [ -z "$(batctl n -H 2>/dev/null)" ] && [ "$(uptime_s)" -lt "$BOOT_WAIT" ] ; do
		sleep 15
	done
	;;
cron)
	up="$(uptime_s)"
	if [ -r "$STAMP" ] ; then
		read last res < "$STAMP"
		iv=$OK_INTERVAL
		[ "$res" = ok ] || iv=$FAIL_INTERVAL
		[ $((up - ${last:-0})) -ge "$iv" ] || exit 0
	else
		# Der Lauf nach dem Start steht noch aus oder laeuft gerade
		[ "$up" -ge $((BOOT_WAIT + 600)) ] || exit 0
	fi
	# Je Knoten fest 0-49 min aus dem letzten Byte der primaeren MAC, damit
	# nicht alle Knoten der Domain in derselben Minute melden
	IFS=: read a a a a a m < /lib/gluon/core/sysconfig/primary_mac
	sleep $(( (0x$m % 50) * 60 ))
	;;
*)
	echo "usage: $0 boot|cron" >&2
	exit 2
	;;
esac

# Nie zwei Laeufe gleichzeitig; eine Sperre aelter als 30 min ist verwaist
if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +30 2>/dev/null)" ] ; then
	rmdir "$LOCK" 2>/dev/null
fi
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

if /usr/sbin/neanderfunk-hvblocator ; then
	res=ok
else
	res=fail
fi
echo "$(uptime_s) $res" > "$STAMP"

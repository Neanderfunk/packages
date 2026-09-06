#!/bin/sh
# Is this node still reaching the rest of the network?
#
# Two independent checks, both only armed once the node has seen the thing
# working at least once since boot - a node that never had a gateway must not
# reboot over it. Both escalate over four checks (*/8, so roughly half an hour)
# before rebooting, and neither reboots within the first
# linkcheck.settings.reboot_uptime_min minutes of uptime.
#
# This lived in neanderfunk-hotfix as rebootIfNoGw.sh. It is a "does the
# network still work" question, not a "is this node healthy" one, so it belongs
# here with the other link checks. It brings its own helpers rather than reusing
# anything from hotfix: the two packages stay independent of each other.

. /lib/gluon/neanderfunk-linkcheck/common.sh

upgrade_started='/tmp/autoupdate.lock'
[ -f $upgrade_started ] && exit

# Einzelinstanz-Lock. Dieses Skript kann laenger laufen als sein Cron-Intervall:
# bis zu zehn Pings je oeffentlichem Prefix, und davon kann es mehrere geben. Ohne Lock
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

# Nothing at all within the first linkcheck.settings.check_uptime_min minutes:
# right after a boot the anycast address is regularly not reachable yet, and
# saying so would only cause needless alarm.
checks_ok || exit 0

reboot_if_old() {
	# $1: check name for the log, $2: reason
	if ! uptime_ok ; then
		no_action_yet "[$1] $2"
		return 0
	fi
	logger -s -t "neanderfunk-linkcheck" -p 5 "[$1] $2, rebooting"
	sync
	reboot -f
	# reboot -f does not necessarily return immediately, and if it does there is
	# no point running the remaining checks - they would only log a second
	# reboot reason for the same event.
	exit
}

# --- batman gateway ---------------------------------------------------------
# `batctl gwl -H` lists the gateways without the header lines, so empty output
# means none is in range. This used to grep batctl's output for "No gateways in
# range", a message current batctl does not contain at all, so the check never
# fired.
if ! check_disabled no_gateway && [ -z "$(batctl gwl -H 2>/dev/null)" ] ; then
	if [ -f /tmp/linkcheck.gw-seen ] && [ "$(strike /tmp/linkcheck.gw-gone)" -ge 4 ] ; then
		reboot_if_old no_gateway "no batman gateway for 4 checks"
	fi
else
	touch /tmp/linkcheck.gw-seen
	unstrike /tmp/linkcheck.gw-gone
fi

# --- IPv6 anycast -----------------------------------------------------------
#
# Das Prefix kam frueher aus der ERSTEN Adresse, die "ip" auf br-client ausgibt.
# Dort stehen aber mehrere: die oeffentliche aus dem RA, die ULA aus der
# site.conf und die Link-Local-Adresse. Auf vier Knoten gemessen antwortet nur
# das oeffentliche Prefix auf ::ac1 - die ULA nicht, und auf einem Knoten mit
# zwei oeffentlichen Prefixen auch das zweite nicht. Welche Adresse zuerst
# kommt, ist eine Zufaelligkeit der Kernel-Reihenfolge; kippt sie, pingt ein
# bereits scharfer Knoten ins Leere und rebootet nach vier Laeufen.
#
# Also: nur oeffentliche Prefixe (ULA ist fc00::/7, also ^fc/^fd; Link-Local
# faellt schon durch "scope global" weg), und wenn es mehrere gibt, reicht es,
# wenn eines antwortet.
anycast_prefixes() {
	ip -6 -o addr show dev br-client scope global 2>/dev/null \
		| awk '{print $4}' | sed 's#/.*##' \
		| grep -v -i '^f[cd]' \
		| cut -d: -f1-4 \
		| awk '!seen[$0]++'
}

# --- oeffentliches Prefix ueberhaupt vorhanden? ---------------------------
#
# Ansage adorfer: faellt das oeffentliche Prefix weg, nachdem es einmal da war,
# ist das ebenfalls ein Reboot-Grund. Eigener Check, damit im Log steht, welche
# der beiden Bedingungen gegriffen hat - ohne oeffentliches Prefix schlaegt
# naemlich auch der Anycast unten fehl.
#
# Scharf erst, wenn es einmal eines gab: ein Knoten, der noch nie ein RA gesehen
# hat, rebootet dadurch nicht.
if ! check_disabled public_prefix ; then
	if [ -n "$(anycast_prefixes)" ] ; then
		touch /tmp/linkcheck.pubprefix-seen
		unstrike /tmp/linkcheck.pubprefix-gone
	elif [ -f /tmp/linkcheck.pubprefix-seen ] ; then
		logger -s -t "neanderfunk-linkcheck" -p 5 "[public_prefix] no public IPv6 prefix on br-client any more"
		if [ "$(strike /tmp/linkcheck.pubprefix-gone)" -ge 4 ] ; then
			reboot_if_old public_prefix "no public IPv6 prefix for 4 checks"
		fi
	fi
fi

ipv6_subnet=""
returnval=1
for pfx in $(anycast_prefixes) ; do
	[ -z "$ipv6_subnet" ] && ipv6_subnet="$pfx"   # nur fuer die Logmeldung
	if ping6 "${pfx}::ac1" -c 10 -w 15 >/dev/null 2>&1 ; then
		ipv6_subnet="$pfx"
		returnval=0
		break
	fi
done

if ! check_disabled ipv6_anycast && { [ "$returnval" -ne 0 ] || [ -z "$ipv6_subnet" ]; } ; then
	if [ -f /tmp/linkcheck.ip6anycast-seen ] ; then
		logger -s -t "neanderfunk-linkcheck" -p 5 "[ipv6_anycast] IPv6 anycast address not reachable"
		if [ "$(strike /tmp/linkcheck.ip6anycast-gone)" -ge 4 ] ; then
			reboot_if_old ipv6_anycast "IPv6 anycast unreachable for 4 checks"
		fi
	fi
else
	touch /tmp/linkcheck.ip6anycast-seen
	unstrike /tmp/linkcheck.ip6anycast-gone
fi

exit 0

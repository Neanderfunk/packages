#!/bin/sh
# nf_running()/nf_count(): Prozesssuche, die sich selbst nie findet.
# Aus neanderfunk-common, siehe dort die Begruendung.
. /lib/gluon/neanderfunk/proc.sh
# Shared helpers for the neanderfunk-linkcheck checks. Sourced, not executed.
#
# Every single check can be switched off on a node:
#     uci set linkcheck.<check>.disabled='1' ; uci commit linkcheck
# The <check> name is part of the reason logged before a wifi restart or a
# reboot, so it can be read off `logread -f` while watching a node.
# `uci show linkcheck` lists the available names.
#
# How long after a boot no check may reboot (minutes, default 60):
#     uci set linkcheck.settings.reboot_uptime_min='90' ; uci commit linkcheck
# Presettable community-wide from the site.conf, see
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

# true once the node is old enough for a check to ACT on what it found -
# reboot, wifi restart, any network reinit. Below this limit a check still
# runs and still logs; see no_action_yet(). Unset or non-numeric falls back to
# the 60 minutes this used to be hardcoded to.
uptime_ok() {
	local m
	m="$(uci -q get linkcheck.settings.reboot_uptime_min)"
	case "$m" in
		''|*[!0-9]*) m=60 ;;
	esac
	[ "$(sed 's/\..*//g' /proc/uptime)" -gt "$((m * 60))" ]
}

# Minimum uptime in seconds before a check may even run (minutes, default 5):
#     uci set linkcheck.settings.check_uptime_min='10' ; uci commit linkcheck
# Right after a boot the network is often not up yet; an anycast ping failing
# then is not a fault worth reporting. Below this limit nothing runs at all.
check_uptime_limit() {
	local m
	m="$(uci -q get linkcheck.settings.check_uptime_min)"
	case "$m" in
		''|*[!0-9]*) m=5 ;;
	esac
	echo $((m * 60))
}

# true once the node is old enough for the checks to run at all
checks_ok() {
	[ "$(sed 's/\..*//g' /proc/uptime)" -gt "$(check_uptime_limit)" ]
}

# reboot_uptime_limit in minutes, for log messages
reboot_uptime_min() {
	local m
	m="$(uci -q get linkcheck.settings.reboot_uptime_min)"
	case "$m" in
		''|*[!0-9]*) m=60 ;;
	esac
	echo "$m"
}

# Log that a check found something but is not acting on it yet. Between
# check_uptime_min and reboot_uptime_min the checks run and report, they just
# do not reboot or restart wifi.
no_action_yet() {
	# $1: the finding, already carrying its [check] tag
	logger -s -t "neanderfunk-linkcheck" -p 5 "$1 - no action taken, uptime below linkcheck.settings.reboot_uptime_min ($(reboot_uptime_min)min)"
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

# true while the autoupdater is downloading or flashing.
#
# Beide Skripte dieses Pakets haben sich bisher allein mit /tmp/autoupdate.lock
# geschuetzt - der Datei, die niemand anlegt (kein Gluon-Paket, kein Patch
# unseres Firmware-Trees; auf Knoten mit Wochen Laufzeit existiert sie nicht).
# Der Schutz war damit wirkungslos.
#
# Das ist hier kein Schoenheitsfehler: ffac-autoupdater-wifi-fallback holt einen
# gestrandeten Knoten zurueck, indem es das WLAN herunterfaehrt, sich als Client
# in ein fremdes Freifunk-Netz haengt und darueber eine ganze Firmware laedt.
# Ueber eine solche Strecke dauert das lange, und ein Reboot mittendrin macht
# die Rettung zunichte - beim naechsten Versuch faengt sie wieder von vorn an.
#
# Dieselbe Erkennung wie in neanderfunk-weeklyreboot, bewusst ohne Rueckgriff
# auf Marker eines anderen Pakets: die Sperrdatei, die der Autoupdater
# tatsaechlich haelt, plus die beiden Prozessnamen.
autoupdater_running() {
	if command -v flock >/dev/null 2>&1 ; then
		# exit 0 heisst, der Lock war frei - dann laeuft kein Autoupdater
		flock -n /var/lock/autoupdater.lock true 2>/dev/null || return 0
	fi
	nf_running autoupdater && return 0
	nf_running sysupgrade  && return 0
	return 1
}

# --- gemeinsame Sperre fuer WLAN-Eingriffe ----------------------------------
#
# Auf einem Knoten koennen sechs Stellen das WLAN neu starten: ssid-changer
# (jede Minute), ap-timer (jede Minute), linkcheck (*/5),
# healthcheck samt check_hostapd (*/7), wifi-blackout (*/10), IfNoWificlient
# (*/15) und stuendlich ffac-autoupdater-wifi-fallback. Die Einzelinstanz-Locks
# der einzelnen Skripte (fd 200) verhindern nur, dass ein Skript sich selbst
# ueberholt - nicht, dass linkcheck ein "wifi down" absetzt, waehrend
# IfNoWificlient zwischen "wifi config" und "wifi up" steht.
#
# Im Normalbetrieb faellt das nicht auf, weil jede Aktion hinter Arming-Markern
# und Strikes sitzt. Aber eine echte Stoerung trifft alle Checks gleichzeitig,
# und genau dann laufen die Neustarts ineinander - dasselbe Muster, das der
# Grund war, die tecff-Pakete auszubauen.
#
# Die Sperre ist nicht-blockierend: wer sie nicht bekommt, laesst seinen
# Neustart aus und versucht es in der naechsten Runde. Wichtig ist, dass der
# Aufrufer dann seinen Zustand NICHT aufraeumt (keine Strikes loeschen, keinen
# Cooldown-Marker setzen) - sonst faellt die Stoerung unter den Tisch.
#
# Gibt es kein flock, wird wie bisher ohne Sperre gearbeitet: eine fehlende
# Sperre darf einen noetigen Neustart nicht verhindern.
# --- Statusmeldungen entrauschen -------------------------------------------
#
# Die Zusammenfassung am Ende von linkcheck.sh ist reiner Zustand und wurde bei
# jedem Lauf (*/5) geschrieben, rund 500 Bytes. Am 2026-09-07 auf einem
# TL-WR1043ND v2 gemessen war neanderfunk-linkcheck damit der groesste
# laufende Posten im Logpuffer: 20956 von 68826 Bytes, also 30%, mehr als
# jeder andere Absender ausser dem einmaligen Kernel-Boot.
#
# Der Puffer ist byte-basiert (system.@system[0].log_size, hier 64 KiB) und
# reicht damit nur gut zwei Stunden zurueck. Jede wiederholte Statuszeile
# verdraengt aeltere Meldungen - also genau das, was man nach einer Stoerung
# sucht.
#
# log_status <schluessel> <signatur> <meldung> schreibt die Meldung nur, wenn
# sich die Signatur seit dem letzten Lauf geaendert hat. Damit ein stabiler
# Knoten nicht voellig verstummt, wird eine unveraenderte Signatur trotzdem
# alle linkcheck.settings.log_heartbeat_min Minuten wiederholt (Vorgabe 60):
#     uci set linkcheck.settings.log_heartbeat_min='30' ; uci commit linkcheck
#
# Ereignismeldungen - verlorene Nachbarn, fehlende Bridges, WLAN-Neustarts,
# Reboots - laufen NICHT hierueber. Die muessen jedes Mal ins Log.
log_heartbeat_limit() {
	local m
	m="$(uci -q get linkcheck.settings.log_heartbeat_min)"
	case "$m" in
		''|*[!0-9]*) m=60 ;;
	esac
	echo $((m * 60))
}

log_status() {
	local key="$1" sig="$2" msg="$3"
	local f="/tmp/linkcheck.laststatus.$key"
	local now old_t old_sig

	# Uptime statt date: fork-frei, und /tmp ist nach einem Reboot ohnehin
	# leer, also kann die Zeitbasis nicht ueber einen Neustart hinweg gelten.
	read -r now _ < /proc/uptime
	now="${now%.*}"

	old_t=''
	old_sig=''
	if [ -f "$f" ] ; then
		# IFS= ist hier nicht kosmetisch: die Signatur wird als
		# sigstring=${sigstring}" "... aufgebaut und faengt deshalb mit einem
		# Leerzeichen an. Ein blosses "read -r" schneidet fuehrenden
		# IFS-Whitespace ab, die zurueckgelesene Signatur war also immer um
		# genau ein Byte kuerzer als die aktuelle - am Knoten gemessen 458
		# gegen 459 -, der Vergleich schlug nie an und die Zusammenfassung
		# wurde weiter bei jedem Lauf geschrieben.
		{ IFS= read -r old_t ; IFS= read -r old_sig ; } < "$f"
	fi

	if [ "$sig" = "$old_sig" ] ; then
		case "$old_t" in
			''|*[!0-9]*) old_t=0 ;;
		esac
		[ $((now - old_t)) -lt "$(log_heartbeat_limit)" ] && return 0
	fi

	printf '%s\n%s\n' "$now" "$sig" > "$f"
	logger -s -t "neanderfunk-linkcheck" -p 5 "$msg"
}

WIFI_LOCK=/var/lock/neanderfunk-wifi.lock

wifi_lock() {
	command -v flock >/dev/null 2>&1 || return 0
	exec 201>>"$WIFI_LOCK" 2>/dev/null || return 0
	flock -n 201 2>/dev/null
}

wifi_unlock() {
	exec 201>&- 2>/dev/null
	return 0
}

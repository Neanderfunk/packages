#!/bin/sh
# Shared helpers for the neanderfunk-hotfix checks. Sourced, not executed.
#
# Every single check can be switched off on a node:
#     uci set hotfix.<check>.disabled='1' ; uci commit hotfix
# The <check> name is part of the reason logged before a reboot or a wifi
# restart, so whoever watches a node with `logread -f` can read straight off
# the syslog which key to set if a check produces false positives for them.
# `uci show hotfix` lists all available check names.
#
# How long after a boot no check may reboot the node (minutes, default 60):
#     uci set hotfix.settings.reboot_uptime_min='90' ; uci commit hotfix
# It can be preset for the whole community from the site.conf, see
# /lib/gluon/upgrade/500-neanderfunk-hotfix and the package README.

# true when the named check is switched off on this node
check_disabled() {
	if [ "$(uci -q get hotfix."$1".disabled)" = "1" ] ; then
		return 0
	fi
	return 1
}

# minimum uptime in seconds before any check may reboot; anything unset or
# not a plain number falls back to the 60 minutes this used to be hardcoded to
reboot_uptime_limit() {
	local m
	m="$(uci -q get hotfix.settings.reboot_uptime_min)"
	case "$m" in
		''|*[!0-9]*) m=60 ;;
	esac
	echo $((m * 60))
}

# true once the node is old enough for a check to ACT on what it found -
# reboot, wifi restart, any network reinit. A check below this limit still
# runs and still logs; see no_action_yet().
uptime_ok() {
	[ "$(sed 's/\..*//g' /proc/uptime)" -gt "$(reboot_uptime_limit)" ]
}

# Minimum uptime in seconds before a check may even run (minutes, default 5):
#     uci set hotfix.settings.check_uptime_min='10' ; uci commit hotfix
# Right after a boot the network is often not up yet, and a check firing then
# would only report a problem that is not one. Below this limit nothing runs
# and nothing is logged.
check_uptime_limit() {
	local m
	m="$(uci -q get hotfix.settings.check_uptime_min)"
	case "$m" in
		''|*[!0-9]*) m=5 ;;
	esac
	echo $((m * 60))
}

# true once the node is old enough for the checks to run at all
checks_ok() {
	[ "$(sed 's/\..*//g' /proc/uptime)" -gt "$(check_uptime_limit)" ]
}

# Log that a check found something but is not acting on it yet. Between
# check_uptime_min and reboot_uptime_min the checks run and report, they just
# do not reboot, restart wifi or otherwise touch the network - so whoever
# watches `logread -f` right after a boot sees the finding without the node
# acting on a network that is still settling.
no_action_yet() {
	# $1: the finding, already carrying its [check] tag
	logger -s -t "neanderfunk-hotfix" -p 5 "$1 - no action taken, uptime below hotfix.settings.reboot_uptime_min ($(($(reboot_uptime_limit) / 60))min)"
}

# Some faults must not wait out reboot_uptime_min. A check listed here acts as
# soon as it fires, whatever the uptime:
#
#   kernel_bug  "Kernel bug detected" is a BUG()/oops. gluon#680 reports that
#               afterwards "any invocation of ip, ifconfig, brctl, batctl etc
#               will result in a stuck system" - there is no self-recovery and
#               no remedy short of a reboot. Worse for us: our own other checks
#               shell out to exactly those tools, so a node in this state may
#               not even manage to report anything. Holding it for an hour buys
#               nothing and costs an hour of a dead node.
#
# Everything else deliberately keeps the hold-off:
#   ath_malloc, ksoftirqd_malloc  can be a transient OOM *during boot* on small
#               devices (openwrt forum on "ath: skbuff alloc of size ... failed":
#               "could be OOM during peak mem consumption while booting, but it
#               may look ok later on"). Acting at once would reboot-loop a
#               32 MiB node at every boot. Both also recur - the freifunk forum
#               reports page allocation failures every 5 to 10 seconds - so a
#               delayed reaction still fires, and the node limps rather than
#               dying outright.
#   load        right after a boot the load is legitimately high, and the 5
#               minute average is not meaningful before the node has been up
#               5 minutes at all.
#
# Per node this can be changed in either direction:
#     uci set hotfix.load.immediate='1'      ; uci commit hotfix
#     uci set hotfix.kernel_bug.immediate='0' ; uci commit hotfix
acts_immediately() {
	local v
	v="$(uci -q get hotfix."$1".immediate)"
	case "$v" in
		1) return 0 ;;
		0) return 1 ;;
	esac
	case "$1" in
		kernel_bug) return 0 ;;
	esac
	return 1
}

# Count consecutive failures. strike <prefix> records one more and prints how
# many there are now, so a check reads as
#     [ "$(strike /tmp/hotfix.gw-gone)" -ge 4 ] && reboot
# instead of a hand-written if/elif ladder over .1/.2/.3 marker files.
#
# One marker file per strike rather than a single counter file, on purpose: a
# counter file is truncated on every write, so being killed in that window
# resets the count to zero - exactly the failure that used to leave nodes stuck
# on the offline SSID in neanderfunk-ssid-changer. Losing one marker here only
# costs one round.
strike() {
	local n=1
	while [ -e "$1.$n" ] ; do n=$((n + 1)) ; done
	touch "$1.$n"
	echo "$n"
}

# forget all strikes recorded under this prefix
unstrike() {
	rm -f "$1".* 2>/dev/null
}

# The syslog tag the functions below log under. healthcheck.sh sets it to
# "neanderfunk-healthcheck" before sourcing this file, so the lines it has
# always written stay unchanged; everything else logs as the package.
: "${HOTFIX_TAG:=neanderfunk-hotfix}"

safety_exit() {
	logger -s -t "$HOTFIX_TAG" "safety checks failed $@, exiting with error code 2"
	exit 2
}

# true while the autoupdater is downloading or writing the flash.
#
# The markers come from our own hooks in /usr/lib/autoupdater/*.d - see
# 20neanderfunk-hotfix there.
#
# Zusaetzlich der Lock und die Prozessnamen, damit der Schutz auch dann traegt,
# wenn die Hooks einmal nicht greifen: der Autoupdater nimmt
# /var/lock/autoupdater.lock mit flock(LOCK_EX|LOCK_NB) und haelt ihn
# ausdruecklich ueber den sysupgrade hinweg (autoupdater.c: "Unset FD_CLOEXEC
# so the lockfile stays locked during sysupgrade").
#
# Frueher stand hier /tmp/autoupdate.lock. Diese Datei legt heute niemand mehr
# an. Ein Gluon-Mechanismus war sie nie: sie kommt in der gesamten
# Gluon-Historie (5187 Commits, Tags ab v2014.1) und im Paket-Feed (892
# Commits) kein einziges Mal vor. Sie stammt aus eulenfunk/packages e783d3a vom
# 2016-05-06, vier Monate BEVOR Gluon mit 1acb4b1 ueberhaupt einen
# Autoupdater-Lock bekam. Einen Tag nach der Pruefung kam dort auch ein Hook
# dazu, der sie tatsaechlich geschrieben hat (19d53ae,
# upgrade.d/00lockfile) - der ging 2017 beim Zusammenlegen zweier Pakete
# verloren (535b9e3, endgueltig 52685ec), die Pruefungen blieben und wurden in
# diesem Zustand weiterkopiert. Sie ist ersatzlos entfallen; die ganze
# Geschichte steht in docs/autoupdate-lock-nachlese.md.
autoupdater_busy() {
	[ -f /tmp/hotfix.autoupdater-flashing ] && return 0
	[ -f /tmp/hotfix.autoupdater-running ] && return 0
	if command -v flock >/dev/null 2>&1 ; then
		flock -n /var/lock/autoupdater.lock true 2>/dev/null || return 0
	fi
	pgrep autoupdater >/dev/null 2>&1 && return 0
	pgrep sysupgrade  >/dev/null 2>&1 && return 0
	return 1
}

now_reboot() {
	# first parameter message
	# second optional -f to force reboot even if autoupdater is running
	#
	# Below hotfix.settings.reboot_uptime_min the finding is still reported, it
	# just does not lead to a reboot - see no_action_yet() above.
	# the check name is the [tag] the caller put in front of the message
	reason_check="${1#*[}" ; reason_check="${reason_check%%]*}"
	if ! uptime_ok && ! acts_immediately "$reason_check" ; then
		no_action_yet "$1"
		return 0
	fi
	logger -s -t "$HOTFIX_TAG" -p 5 "rebooting... reason: $1"
	LOG=/lib/gluon/neanderfunk-hotfix
	[ ! -d $LOG ] && mkdir $LOG
	LOG="$LOG/reboot.log"
	# the first 5 times log the reason for a reboot in a file that is rebootsave
	# (|| echo 0: on the very first reboot the file does not exist yet, and an
	# empty $() would make the -gt comparison bail out with a shell error)
	[ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 5 ] || echo "$(date) $1" >> "$LOG"
	# -f overrides this, but never a flash write in progress: an interrupted
	# sysupgrade bricks the node, and no check is worth that.
	if [ -f /tmp/hotfix.autoupdater-flashing ] ; then
		safety_exit "autoupdater is writing the flash"
	fi
	if [ "$2" != "-f" ] && autoupdater_busy ; then
		safety_exit "autoupdate running"
	fi
	sync
	/sbin/reboot -f
}

# --- gemeinsame Sperre fuer WLAN-Eingriffe ----------------------------------
#
# Auf einem Knoten koennen sieben Stellen das WLAN neu starten: ssid-changer
# (jede Minute), ap-timer (jede Minute), mt7915-backlog (*/2), linkcheck (*/5),
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

#!/bin/sh
# Deadman watchdog for micrond itself.
#
# Every other check in this package runs from micrond - so if micrond dies
# (crash, OOM kill, or stopped and never restarted), nothing on the node would
# ever notice or reboot it again. This closes that hole:
#
# micrond starts this script every hotfix.settings.watchdog_interval_min
# minutes. Each new instance relieves its predecessor by writing its own pid
# into the pid file; the predecessor sees that on its next slice and exits. An
# instance that is *not* relieved within 3x that interval concludes that no
# micrond is starting jobs any more, and reboots the node.
#
# Everything after the sleep is deliberately fork-free: the case this exists
# for includes running out of memory, where starting another process (logger,
# /sbin/reboot, date, uci) may simply fail. echo, read and kill are ash
# builtins, so the decision and the reboot need no fork at all - the reboot
# goes through /proc/sysrq-trigger ('s' = emergency sync, 'b' = reboot now).
#
# The autoupdater legitimately stops micrond while it downloads and flashes
# (see /usr/lib/autoupdater/download.d/10gluon-autoupdater). That must never be
# mistaken for a dead micrond, so the hooks in download.d/upgrade.d/abort.d of
# this package leave markers behind and this watchdog reads them:
#   /tmp/hotfix.autoupdater-running   uptime (s) at which the download started
#   /tmp/hotfix.autoupdater-flashing  set right before sysupgrade writes the flash
# While flashing, this never reboots - interrupting a flash write bricks the
# node. While downloading, it reboots only once the run has exceeded
# hotfix.settings.autoupdater_stale_min minutes, because then the updater is
# not making progress any more.

. /lib/gluon/neanderfunk-hotfix/common.sh

check_disabled watchdog && exit 0

PIDFILE=/tmp/hotfix.watchdog.pid
RUNMARK=/tmp/hotfix.autoupdater-running
FLASHMARK=/tmp/hotfix.autoupdater-flashing

# config is read once, up front, where forking is still fine
interval="$(uci -q get hotfix.settings.watchdog_interval_min)"
case "$interval" in ''|*[!0-9]*) interval=5 ;; esac

# The deadline must never be shorter than the period micrond actually starts
# this script with - otherwise no relief can possibly arrive in time and the
# watchdog would reboot a perfectly healthy node, over and over. Read that
# period out of the cron entry instead of trusting the two to be kept in sync
# by hand, and never go below it.
cron_min="$(sed -n 's#^\*/\([0-9][0-9]*\) .*watchdog\.sh.*#\1#p' /usr/lib/micron.d/hotfix 2>/dev/null | head -1)"
case "$cron_min" in ''|*[!0-9]*) cron_min=5 ;; esac
[ "$interval" -lt "$cron_min" ] && interval="$cron_min"
stale="$(uci -q get hotfix.settings.autoupdater_stale_min)"
case "$stale" in ''|*[!0-9]*) stale=300 ;; esac

# Auch der Deckel des Reboot-Logs wird hier aufgeloest, solange forken noch
# geht - nf_reboot_log fragt danach kein uci mehr. Siehe
# /lib/gluon/neanderfunk/reboot.sh.
nf_reboot_log_preload

deadline=$((interval * 3 * 60))
stale_s=$((stale * 60))

# Relieve the predecessor by taking over the pid file - it notices on its next
# slice that the file no longer names it and exits by itself.
#
# This used to `kill` the predecessor. That worked, but it cost two things on
# every single run: the killed shell died from SIGTERM, so micrond logged
# "Terminated" at daemon.err - 288 lines a day per node, at error priority, for
# an entirely routine event - and the `sleep` it was sitting in outlived its
# shell, so three orphaned `sleep 900` accumulated (deadline 900s, started
# every 300s). Both were measured on the test nodes.
#
# Nothing has to kill anything now. The script itself only ever changes across
# a sysupgrade, and that reboots the node, so there is no case where an
# instance of an older, non-slice-aware version is still running when this one
# starts.
echo $$ > "$PIDFILE"

# fork-free from here on
reboot_now() {
	# Niemals in einen laufenden Flash-Vorgang hinein rebooten - unabhaengig
	# davon, aus welchem Zweig der Aufruf kommt. Der Test steht hier und nicht
	# nur an den Aufrufstellen weiter unten, weil genau das der Fehler war: der
	# Zweig fuer das fehlgeschlagene sleep sprang an der Marker-Pruefung der
	# Schleife vorbei und rebootete hart mitten im sysupgrade.
	[ -f "$FLASHMARK" ] && return 1

	# best effort, still fork-free: /dev/kmsg shows up in logread
	echo "neanderfunk-hotfix: [watchdog] $1, rebooting via sysrq" > /dev/kmsg 2>/dev/null

	# Und in das Log, das den Neustart ueberlebt. Der Ringpuffer tut es nicht,
	# und ausgerechnet dieser Reboot ist der, den hinterher niemand erklaeren
	# kann: er geht ueber /dev/kmsg, taucht im weitergeleiteten Syslog also
	# unter Umstaenden gar nicht auf.
	#
	# Das ist die einzige Stelle hier, die den fork-freien Teil aufweicht.
	# nf_reboot_log kommt dem entgegen: der Deckel ist oben schon aufgeloest,
	# gezaehlt wird mit Builtins, und schlaegt selbst das date fehl, steht statt
	# der Uhrzeit die Uptime in der Zeile.
	nf_reboot_log "[watchdog] $1"

	# Und dann die Zeile auch tatsaechlich auf den Flash bringen, BEVOR das 'b'
	# kommt. Hier stand vorher 's' und unmittelbar danach 'b' - das hat die
	# Zeile mit hoher Wahrscheinlichkeit nicht mehr gerettet: emergency_sync()
	# haengt die Arbeit nur als work item ein und kehrt sofort zurueck, und
	# unter Speichermangel faellt sie ganz aus, weil das work item per
	# kmalloc(GFP_ATOMIC) geholt wird. nf_reboot_flush stoesst zusaetzlich ein
	# sync im Hintergrund an (das uns nicht aufhalten kann) und wartet, notfalls
	# fork-frei ueber /proc/uptime.
	nf_reboot_flush

	echo b > /proc/sysrq-trigger 2>/dev/null

	# Nur erreicht, wenn sysrq nicht zur Verfuegung steht. Dann der regulaere
	# Weg, und falls auch der haengenbleibt, noch einmal sysrq - im
	# Hintergrund gestartet, sonst klebt die Shell mit im Syscall fest.
	reboot -f &
	nf_reboot_escalate
}

# The deadline is waited out in slices so being relieved can be noticed in
# between. 30 seconds is short enough that a relieved instance disappears
# promptly and long enough to stay negligible: one fork of `sleep` per slice,
# and `read` is a builtin.
slice=30
[ "$deadline" -lt "$slice" ] && slice="$deadline"
waited=0

while : ; do
	sleep "$slice"
	rc=$?
	if [ "$rc" -ne 0 ] ; then
		if [ "$rc" -gt 128 ] ; then
			# Ein Signal hat das sleep beendet - Exitcode 128 + Signalnummer,
			# bei TERM also 143. Das ist KEIN Speichermangel, sondern jemand
			# baut das System ab: sysupgrade schickt beim Abbau erst TERM und
			# dann KILL an alle verbliebenen Prozesse.
			#
			# Hier zu rebooten hiess, mitten in einen Flash-Vorgang zu
			# rebooten. Gemeldet aus der Firmware-Session am 2026-09-09: vier
			# von fuenf ERX-Migrationslaeufen wurden so abgebrochen, das Geraet
			# stand danach mit neuem Kernel auf altem Rootfs. Wer uns TERM
			# schickt, weiss in aller Regel, was er tut - also aussteigen.
			# micrond startet den Watchdog beim naechsten Tick ohnehin neu.
			echo "neanderfunk-hotfix: [watchdog] sleep ended by signal (rc=$rc), system is being torn down - exiting without reboot" > /dev/kmsg 2>/dev/null
			exit 0
		fi
		# rc ungleich 0, aber nicht ueber 128: sleep liess sich nicht forken.
		# Das ist der Speichermangel, fuer den dieser Zweig gedacht war, und
		# laenger zu warten hilft dagegen nicht.
		reboot_now "sleep could not fork (rc=$rc), out of memory"
	fi

	# Has a newer instance taken over? Only a readable pid file naming someone
	# else counts. An unreadable or empty one (a full /tmp, say) means we keep
	# watching rather than quietly disarming the watchdog - several instances
	# watching at once is harmless, none watching is not.
	if read cur 2>/dev/null < "$PIDFILE" ; then
		case "$cur" in
			''|*[!0-9]*) cur=$$ ;;
		esac
	else
		cur=$$
	fi
	[ "$cur" = "$$" ] || exit 0

	waited=$((waited + slice))
	[ "$waited" -lt "$deadline" ] && continue
	waited=0

	# still here: nobody relieved us, so micrond is not starting jobs any more

	# never interrupt a flash write
	[ -f "$FLASHMARK" ] && continue

	if [ -f "$RUNMARK" ] ; then
		read started < "$RUNMARK"
		read now rest < /proc/uptime
		now=${now%.*}
		case "$started" in ''|*[!0-9]*) started=$now ;; esac
		case "$now" in ''|*[!0-9]*) now=$started ;; esac
		# updater still within its allowance: keep watching, do not reboot
		[ $((now - started)) -lt "$stale_s" ] && continue
		reboot_now "autoupdater stuck for more than ${stale} min"
		# reboot_now only returns if neither sysrq nor /sbin/reboot worked
		# (e.g. no memory left to fork). Retry at the next deadline instead
		# of falling through to the branch below and logging a wrong reason.
		continue
	fi

	reboot_now "no micrond for more than $((deadline / 60)) min"
done

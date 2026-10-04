#!/bin/sh
# Gemeinsames Reboot-Log. Zum Sourcen gedacht:
#     . /lib/gluon/neanderfunk/reboot.sh
#     nf_reboot_log "[check] Grund"
#
# Warum es das gibt
# -----------------
# Ein Reboot, den ein Check ausloest, ist nach dem Neustart sonst nicht mehr
# nachweisbar: die Logzeile steht im Ringpuffer, und der ist weg. Bis hierher
# schrieb nur neanderfunk-hotfix seine Gruende mit; linkcheck rief in der
# vierten Stufe direkt "reboot -f" und hinterliess nichts. Wer danach fragte,
# warum ein Knoten neu gestartet ist, konnte es nicht beantworten.
#
# Regeln
# ------
# Eine Zeile je Reboot, die darf ausfuehrlich sein. Hoechstens so viele
# Eintraege, wie der Deckel erlaubt, gemeinsam ueber alle Pakete - es geht um
# die ERSTEN Reboots nach einem Firmwarestand, nicht um eine Chronik. Ist der
# Deckel erreicht, wird nichts mehr angehaengt; das ist eine Obergrenze und
# keine Punktbedingung, ein vorbelegtes oder zu langes File waechst also auch
# dann nicht weiter.
#
# Deckel einstellen
# -----------------
# Auf dem Knoten:
#     uci set neanderfunk.settings.reboot_log_max='10'
#     uci commit neanderfunk
# Gemeinschaftsweit in der site.conf, optional - fehlt der Schluessel, bleibt
# es bei der eingebauten Vorgabe 6:
#     neanderfunk = {
#       reboot_log_max = 6,
#     },
# Der Wert 0 schaltet das Reboot-Log ganz ab: es wird dann nichts geschrieben
# und die Datei nicht angelegt. Eine bereits vorhandene Datei wird nicht
# geloescht - sie ist beim naechsten Firmware-Update ohnehin weg.
#
# Der uci-Wert gewinnt immer ueber die site.conf; das Upgrade-Skript
# 490-neanderfunk-common traegt den site.conf-Wert nur dann nach, wenn der
# Knoten keinen eigenen hat.
#
# Die Datei ueberlebt ein Firmware-Update absichtlich NICHT: sie liegt unter
# /lib/gluon/, und dort bewahrt der sysupgrade nur /lib/gluon/core/sysconfig/.
# Nach einem Update zaehlt es also wieder von vorn - genau das ist gewollt,
# weil die Frage immer lautet "warum startet dieses Geraet auf DIESEM Stand
# neu".
#
# Der Pfad lag frueher unter /lib/gluon/neanderfunk-hotfix/. Er liegt jetzt
# hier, weil zwei Pakete hineinschreiben und keines vom anderen abhaengen
# soll. Ein Wechsel kostet keine Historie, weil ohnehin jedes Update von vorn
# beginnt.
NF_REBOOT_LOG_DIR=/lib/gluon/neanderfunk
NF_REBOOT_LOG="$NF_REBOOT_LOG_DIR/reboot.log"
NF_REBOOT_LOG_MAX_DEFAULT=6

# Wieviele Zeilen hoechstens; 0 heisst "kein Reboot-Log". Alles, was nicht aus
# reinen Ziffern besteht - unbelegt, Muell, ein negativer Wert - faellt auf die
# eingebaute Vorgabe zurueck, damit ein vertippter uci-Wert das Log nicht
# stillschweigend abschaltet.
nf_reboot_log_max() {
	local m
	m="$(uci -q get neanderfunk.settings.reboot_log_max 2>/dev/null)"
	case "$m" in
		''|*[!0-9]*) m=$NF_REBOOT_LOG_MAX_DEFAULT ;;
	esac
	echo "$m"
}

# Fuer Aufrufer, die spaeter nicht mehr forken duerfen - watchdog.sh laeuft ab
# einem bestimmten Punkt bewusst fork-frei, weil der Fall, fuer den es ihn
# gibt, Speichermangel einschliesst. Wer das hier beim Start aufruft, loest den
# Deckel auf, solange forken noch geht; nf_reboot_log fragt dann kein uci mehr.
nf_reboot_log_preload() {
	NF_REBOOT_LOG_MAX="$(nf_reboot_log_max)"
}

# Warten, ohne auf einen fork angewiesen zu sein: bevorzugt mit sleep, und wenn
# der sich nicht forken laesst - der Fall, fuer den es watchdog.sh gibt - ueber
# /proc/uptime busy. read ist ein Builtin. CPU zu verbrennen ist auf einem
# Geraet, das gleich neu startet, der kleinere Preis.
#
# Beendet ein Signal das sleep (Rueckgabe ueber 128), baut jemand das System
# ab. Dann nicht nachwarten, sondern zurueck an den Aufrufer - dieselbe
# Unterscheidung wie in watchdog.sh, und aus demselben Grund.
nf_reboot_wait() {
	local secs="${1:-3}" rc t0 t1

	case "$secs" in
		''|*[!0-9]*) secs=3 ;;
	esac

	sleep "$secs" 2>/dev/null
	rc=$?
	[ "$rc" -eq 0 ] && return 0
	[ "$rc" -gt 128 ] && return 0

	# -gt und nicht -ge: die Nachkommastellen fallen weg, ein Unterschied von
	# genau $secs kann also schon nach gut einer Sekunde weniger zustande
	# kommen (10,99 -> 12,00 sind zwei gezaehlte, aber nur 1,01 echte). Eine
	# ganze Sekunde mehr zu warten ist billiger als ein Sync, der zu frueh
	# abgeschnitten wird. Gemessen: bei "2" kam der Fallback vorher nach 1 s
	# zurueck.
	read t0 _ < /proc/uptime ; t0=${t0%.*}
	while : ; do
		read t1 _ < /proc/uptime ; t1=${t1%.*}
		[ $((t1 - t0)) -gt "$secs" ] && return 0
	done
}

# Das Geschriebene auf den Flash bringen - ohne dabei haengen zu koennen und
# ohne auf einen fork angewiesen zu sein. Direkt vor jedem Reboot aufzurufen.
#
# Keiner der drei Bausteine genuegt fuer sich, deshalb alle drei:
#
#   sync       ist bei busybox kein Shell-Builtin (CONFIG_SYNC=y, eigenes
#              Applet), kostet also einen fork - und genau davon hat ein Knoten
#              mit Speichermangel keinen mehr uebrig. Dafuer ist es das
#              einzige, was tatsaechlich wartet, bis alles geschrieben ist. Es
#              kann auf klemmendem Flash aber beliebig lange blockieren, und
#              dann unterbliebe der Reboot ganz. Also in den Hintergrund: dann
#              haelt es uns nicht auf, und der Reboot raeumt es ohnehin weg.
#
#   sysrq 's'  braucht keinen fork (echo ist ein Builtin) und blockiert nie.
#              Dafuer ist es asynchron - emergency_sync() haengt die Arbeit als
#              work item ein und kehrt sofort zurueck; die Kerneldoku sagt
#              ausdruecklich, man solle auf "Emergency Sync complete" warten,
#              bevor man 'b' schickt. Schlimmer: das work item wird mit
#              kmalloc(GFP_ATOMIC) geholt, und schlaegt das fehl, faellt der
#              Sync ersatzlos und stillschweigend aus (fs/sync.c). Ausgerechnet
#              unter Speichermangel ist darauf also kein Verlass.
#
#   warten     bevorzugt mit sleep. Laesst sich das nicht forken - der Fall,
#              fuer den es watchdog.sh gibt -, wird ueber /proc/uptime busy
#              gewartet; read ist ein Builtin. CPU zu verbrennen ist auf einem
#              Geraet, das gleich neu startet, der kleinere Preis. Beendet ein
#              Signal das sleep, baut jemand das System ab: dann nicht noch
#              nachwarten, sondern zurueck an den Aufrufer.
#
# Das [ -w ] vor dem sysrq-Schreiben ist kein Luxus: fehlt die Datei (Kernel
# ohne CONFIG_MAGIC_SYSRQ), meldet die fehlgeschlagene Umleitung die Shell
# selbst, und daran kommt ein 2>/dev/null nicht heran.
nf_reboot_flush() {
	local secs="${1:-3}"

	sync &
	[ -w /proc/sysrq-trigger ] && echo s > /proc/sysrq-trigger 2>/dev/null

	nf_reboot_wait "$secs"
}

nf_reboot_log() {
	local lines=0 max stamp line

	[ -n "$*" ] || return 0

	# Ein vorab aufgeloester Deckel spart den uci-Aufruf, siehe oben.
	max="$NF_REBOOT_LOG_MAX"
	[ -n "$max" ] || max="$(nf_reboot_log_max)"
	[ "$max" -gt 0 ] || return 0

	[ -d "$NF_REBOOT_LOG_DIR" ] || mkdir -p "$NF_REBOOT_LOG_DIR" 2>/dev/null || return 0

	# [ -f ] zuerst: eine Umleitung von einer fehlenden Datei meldet die Shell
	# selbst ("can't open"), und daran kommt ein 2>/dev/null nicht heran. Beim
	# allerersten Reboot stand diese Meldung sonst im Syslog, direkt vor dem
	# Neustart - und schickte jeden, der dem Reboot nachging, auf die falsche
	# Faehrte.
	#
	# Gezaehlt wird mit der Schleife statt mit "wc -l": read ist ein Builtin,
	# das spart einen fork auf einem Pfad, der oefter als uns lieb ist unter
	# Speichermangel begangen wird. Bei hoechstens einer Handvoll Zeilen kostet
	# die Schleife nichts.
	#
	# Das letzte read schlaegt am Dateiende fehl, legt einen angefangenen Rest
	# ohne abschliessendes Newline aber trotzdem in $line ab. Deshalb wird
	# $line in der Schleife geleert: was danach drinsteht, ist genau so ein
	# Rest. Der Fall ist hier nicht theoretisch - geschrieben wird unmittelbar
	# vor einem harten Reboot, ein abgerissener Schreibvorgang ist also die
	# Regel und nicht die Ausnahme. Er wird mitgezaehlt (sonst zaehlte der
	# Deckel eine Zeile zu wenig) und bekommt sein Newline nachgereicht, damit
	# der neue Eintrag nicht an die halbe Zeile angeklebt wird.
	if [ -f "$NF_REBOOT_LOG" ] ; then
		while IFS= read -r line ; do
			lines=$((lines + 1))
			line=''
		done < "$NF_REBOOT_LOG"
		[ -n "$line" ] && lines=$((lines + 1))
	fi

	[ "$lines" -ge "$max" ] && return 0

	# date ist der letzte verbliebene fork. Schlaegt er fehl, steht statt der
	# Uhrzeit die Uptime in der Zeile - eine Zeile ohne Zeitangabe waere beim
	# Nachsehen wertlos, und /proc/uptime liest read fork-frei. Ohne RTC ist
	# die Uptime ohnehin oft die ehrlichere Angabe.
	stamp="$(date 2>/dev/null)"
	if [ -z "$stamp" ] ; then
		read stamp _ < /proc/uptime
		stamp="uptime=${stamp%.*}s"
	fi

	[ -n "$line" ] && echo >> "$NF_REBOOT_LOG"
	echo "$stamp $*" >> "$NF_REBOOT_LOG"
}

# Zweiter Anker, falls der Reboot selbst haengenbleibt.
#
# "reboot -f" ruft reboot(RB_AUTOBOOT); der Kernel geht dann durch
# device_shutdown(), und ein Treiber, dessen shutdown haengt, haelt dort alles
# an. Das Geraet steht dann - kein Warmstart, kein Zurueckkommen, und der
# aufrufende Prozess klebt im Syscall fest. Genau deshalb wird der Reboot vom
# Aufrufer in den Hintergrund geschickt: sonst wartet die Shell mit ihm
# zusammen ewig und kaeme hier nie an.
#
# sysrq 'b' geht diesen Weg nicht: emergency_restart() ueberspringt
# device_shutdown() und startet sofort neu. Als Nachschlag nach einem
# haengenden regulaeren Reboot ist das also genau das richtige Mittel.
#
# Bewusst 'b' und nicht 'o': 'o' ist poweroff. Ein Knoten, der aus ist, ist
# schlechter dran als einer, der haengt - er kommt ohne Hand am Stecker nie
# wieder, und bei den meisten Routern tut 'o' ohnehin nichts, weil es keine
# Abschaltmoeglichkeit gibt.
nf_reboot_escalate() {
	local secs="${1:-60}"

	nf_reboot_wait "$secs"

	echo "neanderfunk: reboot did not take effect within ${secs}s, forcing via sysrq" > /dev/kmsg 2>/dev/null
	[ -w /proc/sysrq-trigger ] && echo b > /proc/sysrq-trigger 2>/dev/null
	return 0
}

# Der uebliche harte Reboot: erst alles auf den Flash, dann reboot -f, und wenn
# das Geraet danach noch laeuft, ueber sysrq nachhelfen.
#
# Das "&" ist nicht Bequemlichkeit: ohne es wartet die Shell auf ein reboot -f,
# das im Kernel haengt, und die Eskalation darunter kaeme nie zum Zug.
nf_reboot_hard() {
	nf_reboot_flush
	reboot -f &
	nf_reboot_escalate
}

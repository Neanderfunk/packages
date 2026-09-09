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

nf_reboot_log() {
	local lines=0 max

	[ -n "$*" ] || return 0

	max="$(nf_reboot_log_max)"
	[ "$max" -gt 0 ] || return 0

	[ -d "$NF_REBOOT_LOG_DIR" ] || mkdir -p "$NF_REBOOT_LOG_DIR" 2>/dev/null || return 0

	# [ -f ] zuerst: "wc -l < datei" auf eine fehlende Datei meldet die Shell
	# selbst ("can't open"), und daran kommt ein 2>/dev/null am wc nicht heran.
	# Beim allerersten Reboot stand diese Meldung sonst im Syslog, direkt vor
	# dem Neustart - und schickte jeden, der dem Reboot nachging, erst einmal
	# auf die falsche Faehrte.
	if [ -f "$NF_REBOOT_LOG" ] ; then
		lines="$(wc -l < "$NF_REBOOT_LOG")"
		case "$lines" in
			''|*[!0-9]*) lines=0 ;;
		esac
	fi

	[ "$lines" -ge "$max" ] && return 0

	echo "$(date) $*" >> "$NF_REBOOT_LOG"
}

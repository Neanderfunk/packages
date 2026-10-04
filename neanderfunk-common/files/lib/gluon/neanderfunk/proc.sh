#!/bin/sh
# Prozesssuche, die sich selbst nie findet. Zum Sourcen gedacht:
#     . /lib/gluon/neanderfunk/proc.sh
# Fuer Aufrufer, die nicht sourcen koennen (Lua), gibt es dieselben Funktionen
# als Kommandos: nf-ps und nf-pgrep.
#
# Warum es das gibt
# -----------------
# "ps | grep name" und "pgrep -f muster" finden regelmaessig den Suchenden
# statt des Gesuchten. Am Knoten gemessen (2026-09-09):
#
#   * "pgrep -f autoupdater" lieferte drei PIDs, von denen keine der
#     Autoupdater war - darunter ein Skript, das seinerseits nur nach
#     "autoupdater" suchte.
#   * "pgrep -f /usr/bin/tunneldigger" fand die SSH-Sitzung, die die Suche
#     abgesetzt hat, weil der String in ihrer Kommandozeile stand.
#
# Der Klammertrick ("[t]unneldigger") verhindert nur, dass das grep sich
# selbst sieht - nicht, dass es den aufrufenden Shell-Prozess oder ein
# Geschwister in derselben Pipeline sieht.
#
# Was hier passiert
# -----------------
# Ausgeblendet wird die eigene Elternkette bis unterhalb von PID 1, und alles,
# was ein Glied dieser Kette gestartet hat - also der Aufrufer, diese Suche
# selbst und die Geschwister derselben Pipeline. Genau das, was man nie meint,
# wenn man nach einem Prozess sucht.
#
# PID 1 gehoert bewusst nicht dazu: unter procd haengen fast alle Dienste
# direkt an der 1, wer deren Kinder ausblendet findet nie wieder einen Daemon.
#
# Fremde Prozesse, die zufaellig denselben String fuehren, kann kein
# Selbstfilter erkennen. Dagegen hilft nur, nicht die Kommandozeile zu
# durchsuchen, sondern den Prozessnamen exakt zu vergleichen - das tut
# nf_pids(). Busybox setzt comm auch bei Skripten auf den Skriptnamen
# ("watchdog.sh"), Skripte sind damit genauso findbar wie Binaries.
#
# Kosten: /proc einmal durchlesen, am Knoten 107 Prozesse in 0,03 s, fork-frei.

# Die Kette aus eigener PID und allen Vorfahren, aber OHNE PID 1.
#
# Warum ohne die 1: unter procd hat auf diesen Geraeten fast jeder Dienst
# ppid=1 - am Knoten gemessen auch tunneldigger. Wer die Kinder von PID 1
# ausblendet, blendet saemtliche Daemons aus und findet nie wieder etwas.
#
# Ein erster Versuch ueber die Prozessgruppe ist aus demselben Grund
# gescheitert: procd startet ohne Job Control, deshalb steht dort ueberall
# pgrp=1, beim Suchenden wie beim Gesuchten.
nf_own_chain() {
	local pid=$$ out='' line rest next
	while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null ; do
		out="$out $pid"
		# Lesbarkeit zuerst pruefen: eine fehlgeschlagene Umleitung meldet die
		# Shell selbst, daran kommt ein 2>/dev/null am read nicht heran.
		[ -r "/proc/$pid/stat" ] || break
		read -r line < "/proc/$pid/stat" 2>/dev/null || break
		# Feld 2 ist der Prozessname und darf Leerzeichen und Klammern
		# enthalten - deshalb hinter der letzten schliessenden Klammer
		# aufsetzen. Danach: $1 state, $2 ppid, $3 pgrp.
		rest="${line##*) }"
		set -- $rest
		next="$2"
		[ "$next" = "$pid" ] && break
		pid="$next"
	done
	echo "$out"
}

# Trifft der Prozess uns selbst? Wahr fuer die eigene Kette und fuer alles,
# was ein Glied dieser Kette gestartet hat - also auch fuer das grep in
# derselben Pipeline, dessen Elter die aufrufende Shell ist.
nf_is_own() {
	local pid="$1" chain="$2" line rest
	case " $chain " in *" $pid "*) return 0 ;; esac
	# Der Prozess kann zwischen ps und hier verschwunden sein - das ist der
	# Normalfall bei kurzlebigen Kommandos, kein Fehler.
	[ -r "/proc/$pid/stat" ] || return 1
	read -r line < "/proc/$pid/stat" 2>/dev/null || return 1
	rest="${line##*) }"
	set -- $rest
	case " $chain " in *" $2 "*) return 0 ;; esac
	return 1
}

# nf_pids <comm> - PIDs aller Prozesse mit exakt diesem Namen, ohne uns
# selbst. Kein Muster, kein Teilstring: exakter Vergleich.
nf_pids() {
	local want="$1" chain p pid c out=''
	[ -n "$want" ] || return 1
	chain="$(nf_own_chain)"
	for p in /proc/[0-9]* ; do
		pid="${p#/proc/}"
		[ -r "$p/comm" ] || continue
		read -r c < "$p/comm" 2>/dev/null || continue
		[ "$c" = "$want" ] || continue
		nf_is_own "$pid" "$chain" && continue
		out="$out $pid"
	done
	[ -n "$out" ] || return 1
	echo "${out# }"
}

# nf_count <comm> - Anzahl. Immer eine Zahl, auch bei null Treffern.
nf_count() {
	set -- $(nf_pids "$1" 2>/dev/null)
	echo $#
}

# nf_running <comm> - Rueckgabe 0, wenn mindestens einer laeuft.
nf_running() {
	nf_pids "$1" >/dev/null 2>&1
}

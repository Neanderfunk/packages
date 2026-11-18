#!/bin/sh
# Werte aus site.conf und Domain lesen, ohne Lua. Zum Sourcen gedacht:
#     . /lib/gluon/neanderfunk/site.sh
#     prefix="$(nf_site_get '@.prefix6')"
#
# Warum es das gibt
# -----------------
# Im Multi-Domain-Image steht ein Teil der Werte nur in der Domain
# (/lib/gluon/domains/<code>.json), nicht in /lib/gluon/site.json. Gluon
# selbst erzwingt das fuer Schluessel mit in_domain, etwa prefix6. Wer nur
# site.json liest, bekommt dort nichts: der hotfix-Check br_client_ipv6 lief
# deshalb im Multi-Image still nicht (gefunden 18.11.2026).
#
# nf_site_get sucht wie Gluons gluon.site zuerst in der aktiven Domain
# (gluon.core.domain), dann in der Site. Ohne Domains oder ohne Treffer in
# der Domain ist es dasselbe wie jsonfilter auf site.json. Bei Listen gewinnt
# die ganze Liste der Domain, Gluon fuehrt dagegen elementweise zusammen; fuer
# unsere Schluessel steht eine Liste immer nur an einer Stelle.
#
# Bewusst Shell und jsonfilter statt "lua -e require('gluon.site')": die
# Checks laufen alle paar Minuten, und auf 64-MB-Geraeten kostet jeder
# Lua-Start spuerbar Speicher.

# Pfad der Domain-Datei der aktiven Domain, sonst Rueckgabe 1
nf_site_domain_file() {
	local d
	d="$(uci -q get gluon.core.domain)"
	case "$d" in
		''|*/*|.*) return 1 ;;
	esac
	[ -f "/lib/gluon/domains/$d.json" ] || return 1
	echo "/lib/gluon/domains/$d.json"
}

# nf_site_get <jsonfilter-Ausdruck>: Wert aus Domain, sonst aus Site; leer,
# wenn er nirgends steht
nf_site_get() {
	local f v
	if f="$(nf_site_domain_file)" ; then
		v="$(jsonfilter -i "$f" -e "$1" 2>/dev/null)"
		if [ -n "$v" ] ; then
			echo "$v"
			return 0
		fi
	fi
	jsonfilter -i /lib/gluon/site.json -e "$1" 2>/dev/null
}

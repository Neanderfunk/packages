#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
#
# Manifeste auf dem Firmware-Server gegen die Images daneben pruefen.
# Hilfe: manifest-pruefen.sh --help

set -o nounset -o pipefail

hilfe() {
	cat <<'EOT'
manifest-pruefen.sh - pruefen, ob die Manifeste eines Zweigs zu den Images auf
dem Firmware-Server passen.

Laeuft auf dem Server, direkt auf den Dateien. Gehoert zu den Werkzeugen
manifeste-unterschreiben.sh (Signer) und manifest-signaturen-einspielen.sh
(Server). Die Unterschrift bestaetigt nur das Manifest selbst; ob die Dateien
daneben dazu passen, prueft dieses Skript.

AUFRUF
  manifest-pruefen.sh [optionen] <basisverzeichnis> [domain ...]

  <basisverzeichnis>  Server-Pfad des Zweigs, z. B. /var/www/firmware/stable
  [domain ...]        nur diese Domains (Vorgabe: alle Unterverzeichnisse
                      ohne ".key")

OPTIONEN
  -b zweig     Name des Manifests (Vorgabe: letzter Teil des Basisverzeichnisses)
  -g           grob: nur Vorhandensein und Groesse, keine sha256 (schnell)
  -K           auch die ".key"-Verzeichnisse pruefen
  -q           nur Probleme ausgeben
  -L           statt zu pruefen: identische Dateien wieder zu Symlinks machen
  -U           statt zu pruefen: Symlinks wieder zu echten Dateien machen
  -n           mit -L/-U: nur anzeigen, nichts aendern
  -h, --help   diese Hilfe

WAS GEPRUEFT WIRD, je Domain (<domain>/sysupgrade/<zweig>.manifest)
  FEHLER    eine im Manifest genannte Datei hat eine andere sha256 oder Groesse.
            Das ist der schlimme Fall: Knoten laden das Image und verwerfen es
            nach dem Download (oder schlimmer, wenn das Manifest falsch ist).
  WARNUNG   eine im Manifest genannte Datei fehlt
  WARNUNG   im sysupgrade-Verzeichnis liegt eine Datei, die kein Manifest nennt
  Jede Datei wird einmal gehasht, auch wenn mehrere Modellzeilen (Aliase)
  auf sie zeigen.

SYMLINKS (-L, -U)
  Gluon legt Images fuer Geraete-Aliase als Symlinks an. Beim Kopieren vom
  Bauserver werden daraus volle Kopien. -L macht daraus wieder Symlinks: Je
  Verzeichnis (<domain>/sysupgrade, factory, other) werden Dateien mit gleicher
  Groesse und gleicher sha256 gesucht, per cmp bestaetigt, und alle bis auf
  eine durch einen relativen Symlink auf diese ersetzt. Behalten wird die
  Datei, auf die die meisten Manifest-Zeilen zeigen (bei Aliasen traegt Gluon
  den Dateinamen des Hauptgeraets ein), sonst die alphabetisch erste.
  Ersetzt wird atomar (neuer Link, dann mv).
  Vorausgesetzt ist, dass der Webserver Symlinks ausliefert.
  -U ist der Rueckweg: Symlinks auf Dateien im selben Verzeichnis werden
  wieder zu echten Kopien. Es gibt derzeit keinen Anlass dafuer; es ist nur
  fuer den Fall da, dass Symlinks doch stoeren.
  Ein neuer Abgleich vom Bauserver kann die Kopien wieder anlegen; dann -L
  erneut laufen lassen.

BEISPIELE
  manifest-pruefen.sh /var/www/firmware/stable
  manifest-pruefen.sh -g -q /var/www/firmware/stable
  manifest-pruefen.sh -b broken /var/www/firmware/broken 21_dias 18_nefuk
  manifest-pruefen.sh -L -n /var/www/firmware/stable      (nur anzeigen)
  manifest-pruefen.sh -L /var/www/firmware/stable

VORAUSSETZUNGEN
  bash, awk, sha256sum (coreutils) bzw. shasum

EXIT-CODES
  0  keine Fehler (Warnungen moeglich); bei -L/-U: fertig
  1  mindestens ein FEHLER (falscher Hash oder falsche Groesse); bei -L/-U:
     ein Ersetzen ist fehlgeschlagen
  2  falscher Aufruf
EOT
}

falsch() { echo "$1" >&2; echo "Hilfe: $0 --help" >&2; exit 2; }

for arg in "$@"; do
	case "$arg" in --help|-h) hilfe; exit 0 ;; esac
done

BRANCH=""; GROB=0; MIT_KEY=0; LEISE=0; MODUS=pruefen; TROCKEN=0
while getopts "b:gKqLUn" opt; do
	case "$opt" in
		L) MODUS=verlinken ;;
		U) MODUS=entlinken ;;
		n) TROCKEN=1 ;;
		b) BRANCH="$OPTARG" ;;
		g) GROB=1 ;;
		K) MIT_KEY=1 ;;
		q) LEISE=1 ;;
		*) falsch "Unbekannte Option." ;;
	esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] || falsch "Erwartet: <basisverzeichnis> [domain ...]"

BASE="${1%/}"; shift
[ -d "$BASE" ] || falsch "$BASE ist kein Verzeichnis."
[ -n "$BRANCH" ] || BRANCH="${BASE##*/}"
if command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"; else SHA="shasum -a 256"; fi

if [ $# -gt 0 ]; then
	DOMAINS="$*"
else
	DOMAINS="$(cd "$BASE" && for d in */; do d="${d%/}"; [ -d "$d/sysupgrade" ] || continue
		case "$d" in *.key) [ "$MIT_KEY" = 1 ] || continue ;; esac; echo "$d"; done)"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

sag() { [ "$LEISE" = 1 ] || echo "$@"; }

# Dateigroesse ohne GNU-stat-Abhaengigkeit
groesse() { wc -c < "$1" | tr -d ' '; }

# verlinken <verzeichnis>: identische Dateien (Groesse, sha256, cmp) durch
# relative Symlinks auf die alphabetisch erste ersetzen
verlinken() {
	local dir="$1" f g h behalten n=0 gespart=0 tmp
	( cd "$dir" && for f in *; do [ -f "$f" ] && [ ! -L "$f" ] && echo "$f"; done ) | sort > "$TMP/dateien"
	[ -s "$TMP/dateien" ] || return 0
	while read -r f; do echo "$(groesse "$dir/$f") $f"; done < "$TMP/dateien" > "$TMP/groessen"
	# nur Groessen, die mehrfach vorkommen, hashen
	awk '{ n[$1]++; z[NR] = $0 } END { for (i = 1; i <= NR; i++) { split(z[i], a, " "); if (n[a[1]] > 1) print z[i] } }' "$TMP/groessen" |
	while read -r g f; do echo "$g $($SHA "$dir/$f" | cut -d' ' -f1) $f"; done > "$TMP/hashes.roh"
	# Behalten wird je Gruppe die Datei, auf die die meisten Manifest-Zeilen
	# zeigen (Gluon traegt bei Aliasen den Dateinamen des Hauptgeraets ein),
	# sonst die alphabetisch erste.
	cat "$dir"/*.manifest 2>/dev/null | awk 'NF == 5 { n[$5]++ } END { for (f in n) print f, n[f] }' > "$TMP/refs"
	awk 'NR == FNR { r[$1] = $2; next } { print $1, $2, 1000000 - (r[$3] + 0), $3 }' "$TMP/refs" "$TMP/hashes.roh" |
		sort -k1,1n -k2,2 -k3,3n -k4,4 | awk '{ print $1, $2, $4 }' > "$TMP/hashes"
	behalten=""; letzt=""
	while read -r g h f; do
		if [ "$g $h" != "$letzt" ]; then behalten="$f"; letzt="$g $h"; continue; fi
		if ! cmp -s "$dir/$behalten" "$dir/$f"; then
			echo "   gleiche sha256, aber cmp verschieden (?): $behalten / $f - nicht angefasst"
			continue
		fi
		if [ "$TROCKEN" = 1 ]; then
			echo "   -n: $f -> $behalten"
		else
			tmp="$dir/.$f.link.$$"
			ln -s "$behalten" "$tmp" && mv -f "$tmp" "$dir/$f" \
				|| { rm -f "$tmp"; echo "   FEHLER beim Ersetzen von $f" >&2; FEHLGESCHLAGEN=1; continue; }
			sag "   $f -> $behalten"
		fi
		n=$((n + 1)); gespart=$((gespart + g))
	done < "$TMP/hashes"
	echo "$n $gespart" >> "$TMP/summe"
}

# entlinken <verzeichnis>: Symlinks auf Dateien im selben Verzeichnis wieder
# zu echten Kopien machen
entlinken() {
	local dir="$1" f ziel tmp n=0
	for f in "$dir"/*; do
		[ -L "$f" ] || continue
		ziel="$(readlink "$f")"
		case "$ziel" in */*) continue ;; esac
		[ -f "$dir/$ziel" ] || continue
		if [ "$TROCKEN" = 1 ]; then
			echo "   -n: ${f##*/} (Link auf $ziel) -> Kopie"
		else
			tmp="$dir/.${f##*/}.kopie.$$"
			cp -p "$dir/$ziel" "$tmp" && mv -f "$tmp" "$f" \
				|| { rm -f "$tmp"; echo "   FEHLER beim Kopieren nach ${f##*/}" >&2; FEHLGESCHLAGEN=1; continue; }
			sag "   ${f##*/}: jetzt Kopie von $ziel"
		fi
		n=$((n + 1))
	done
	echo "$n 0" >> "$TMP/summe"
}

if [ "$MODUS" != pruefen ]; then
	FEHLGESCHLAGEN=0; : > "$TMP/summe"
	for d in $DOMAINS; do
		for sub in sysupgrade factory other; do
			[ -d "$BASE/$d/$sub" ] || continue
			sag "== $d/$sub"
			"$MODUS" "$BASE/$d/$sub"
		done
	done
	read -r anzahl bytes < <(awk '{ n += $1; b += $2 } END { print n + 0, b + 0 }' "$TMP/summe")
	echo
	[ "$TROCKEN" = 1 ] && echo "Probelauf (-n), nichts geaendert."
	if [ "$MODUS" = verlinken ]; then
		echo "Durch Symlinks ersetzt: $anzahl Dateien, $((bytes / 1048576)) MB"
	else
		echo "Symlinks wieder zu Kopien gemacht: $anzahl"
	fi
	[ "$FEHLGESCHLAGEN" = 0 ] || exit 1
	exit 0
fi

N_FEHLER=0; N_FEHLT=0; N_UEBRIG=0; N_OK=0; N_DOM=0
for d in $DOMAINS; do
	dir="$BASE/$d/sysupgrade"
	m="$dir/$BRANCH.manifest"
	if [ ! -f "$m" ]; then
		sag "-- $d: kein $BRANCH.manifest"
		continue
	fi
	N_DOM=$((N_DOM + 1))
	sed '/^---$/,$d' "$m" | awk 'NF == 5 { print $5, $3, $4 }' | sort -u > "$TMP/soll"
	ausgabe=""
	fehler=0; fehlt=0; ok=0
	# Gleicher Dateiname mit verschiedenen Hashes im Manifest ist selbst ein Fehler
	for f in $(cut -d' ' -f1 "$TMP/soll" | uniq -d); do
		ausgabe="$ausgabe
   FEHLER: $f steht mit verschiedenen Hashes/Groessen im Manifest"
		fehler=$((fehler + 1))
	done
	while read -r f hash groesse; do
		if [ ! -f "$dir/$f" ]; then
			ausgabe="$ausgabe
   WARNUNG: fehlt: $f"
			fehlt=$((fehlt + 1)); continue
		fi
		ist_groesse="$(wc -c < "$dir/$f" | tr -d ' ')"
		if [ "$ist_groesse" != "$groesse" ]; then
			ausgabe="$ausgabe
   FEHLER: $f ist $ist_groesse Byte, Manifest sagt $groesse"
			fehler=$((fehler + 1)); continue
		fi
		if [ "$GROB" != 1 ]; then
			ist="$($SHA "$dir/$f" | cut -d' ' -f1)"
			if [ "$ist" != "$hash" ]; then
				ausgabe="$ausgabe
   FEHLER: $f hat sha256 $ist, Manifest sagt $hash"
				fehler=$((fehler + 1)); continue
			fi
		fi
		ok=$((ok + 1))
	done < "$TMP/soll"

	# Dateien, die kein Manifest dieses Verzeichnisses nennt
	cat "$dir"/*.manifest 2>/dev/null | sed '/^---$/,/^BRANCH=/d' | awk 'NF == 5 { print $5 }' | sort -u > "$TMP/genannt"
	( cd "$dir" && for f in *; do [ -f "$f" ] || continue; case "$f" in *.manifest) continue ;; esac; echo "$f"; done ) | sort > "$TMP/da"
	uebrig="$(comm -23 "$TMP/da" "$TMP/genannt")"
	# Alias-Dateien sind keine Warnung: Gluon traegt bei Aliasen den
	# Hauptdateinamen ins Manifest ein, die Alias-Datei daneben ist ein Symlink
	# darauf oder (nach dem Kopieren vom Bauserver) eine gleiche Kopie.
	awk '{ print $1, $3 }' "$TMP/soll" > "$TMP/soll.groessen"
	n_uebrig=0; n_alias=0; n_kopie=0
	for f in $uebrig; do
		if [ -L "$dir/$f" ]; then
			ziel="$(readlink "$dir/$f")"
			if grep -qxF -- "$ziel" "$TMP/genannt"; then n_alias=$((n_alias + 1)); continue; fi
		else
			g="$(wc -c < "$dir/$f" | tr -d ' ')"
			kandidat="$(awk -v g="$g" '$2 == g { print $1 }' "$TMP/soll.groessen")"
			if [ -n "$kandidat" ]; then
				if [ "$GROB" = 1 ]; then n_kopie=$((n_kopie + 1)); continue; fi
				h="$($SHA "$dir/$f" | cut -d' ' -f1)"
				if awk -v h="$h" '$2 == h { found = 1 } END { exit !found }' "$TMP/soll"; then
					n_kopie=$((n_kopie + 1)); continue
				fi
			fi
		fi
		ausgabe="$ausgabe
   WARNUNG: von keinem Manifest genannt: $f"
		n_uebrig=$((n_uebrig + 1))
	done
	if [ "$n_kopie" -gt 0 ]; then
		ausgabe="$ausgabe
   Hinweis: $n_kopie Alias-Datei(en) als volle Kopie$( [ "$GROB" = 1 ] && echo ' (nach Groesse)'), mit -L wieder Symlinks"
	fi

	N_FEHLER=$((N_FEHLER + fehler)); N_FEHLT=$((N_FEHLT + fehlt)); N_UEBRIG=$((N_UEBRIG + n_uebrig)); N_OK=$((N_OK + ok))
	if [ -n "$ausgabe" ] || [ "$LEISE" != 1 ]; then
		echo "== $d: $ok in Ordnung, $fehler Fehler, $fehlt fehlen, $n_uebrig ohne Manifest, $((n_alias + n_kopie)) Alias-Dateien"
		[ -n "$ausgabe" ] && printf '%s\n' "$ausgabe" | sed '1d'
	fi
done

echo
if [ "$N_DOM" -eq 0 ]; then
	echo "Kein $BRANCH.manifest gefunden - stimmt der Zweig (-b)?" >&2
	exit 1
fi
echo "Domains: $N_DOM, Dateien in Ordnung: $N_OK$( [ "$GROB" = 1 ] && echo ' (nur Groesse geprueft)')"
echo "FEHLER (Hash/Groesse): $N_FEHLER, WARNUNG fehlende Dateien: $N_FEHLT, WARNUNG Dateien ohne Manifest: $N_UEBRIG"
[ "$N_FEHLER" -eq 0 ] || exit 1
exit 0

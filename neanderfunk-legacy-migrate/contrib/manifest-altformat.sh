#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
#
# Ein heutiges Gluon-Manifest um die Zeilen der alten Formate ergaenzen, damit
# auch Knoten mit sehr alter Firmware (Gluon 2016.2 bis 2017.1) es lesen.
# Hilfe: manifest-altformat.sh --help

set -o nounset -o pipefail

hilfe() {
	cat <<'EOT'
manifest-altformat.sh - ein Manifest um die alten Zeilenformate ergaenzen,
damit Knoten mit alter Gluon-Firmware es lesen koennen.

HINTERGRUND (Gluon-Quellen, Einzelheiten in docs/gluon-manifest-format.md)
  bis v2016.2.3   "<modell> <version> <sha512> <datei>"            (4 Felder)
                  Autoupdater (Lua) nimmt die LETZTE passende 4-Feld-Zeile
                  und prueft sha512.
  v2016.2.4/2017.1 zusaetzlich "<modell> <version> <sha256> <datei>"; der
                  2017.1-Autoupdater nimmt nur 4-Feld-Zeilen mit 64 Zeichen
                  Pruefsumme und prueft sha256. Erzeugt wurden sha256- und
                  sha512-Zeile, in dieser Reihenfolge.
  v2018.1-2020.2  zusaetzlich "<modell> <version> <sha256> <groesse> <datei>"
                  (5 Felder); der C-Autoupdater liest nur diese. Die beiden
                  4-Feld-Zeilen wurden weiter mit erzeugt.
  ab v2021.1      nur noch die 5-Feld-Zeile.
  Die Unterschriften decken alles vor "---" ab, egal welches Format.

WAS DAS SKRIPT TUT
  Fuer jede 5-Feld-Zeile gibt es aus:
    <modell> <version> <sha256> <groesse> <datei>   (wie gehabt)
    <modell> <version> <sha256> <datei>             (Gluon 2016.2.4-2017.1)
    <modell> <version> <sha512> <datei>             (Gluon bis 2016.2)
  genau in dieser Reihenfolge wie Gluon 2018.1-2020.2. Die sha512 wird aus
  der Datei neben dem Manifest berechnet (je Datei einmal).
  Fuer alte Modellnamen (ar71xx-Zeit, z. B. tp-link-tl-wr1043n-nd-v4) kommen
  dieselben drei Zeilen noch einmal mit dem alten Namen dazu; die Zuordnung
  alt -> neu steht als Konstante im Skript (Array ALIAS_ALT), -a ergaenzt sie.
  CPE210/220/510/520 v1 bekommen nur die 5-Feld-Zeile (Array OHNE_4FELD):
  Ihr 2016.2-sysupgrade lehnt ath79-Images ab, der Knoten bliebe offline. Vorhandene 4-Feld-Zeilen und alle Unterschriften werden
  verworfen: Das Ergebnis traegt keine Unterschrift und muss neu
  unterschrieben werden (manifeste-unterschreiben.sh), auch mit Schluesseln,
  die nur noch in der alten Firmware stehen (beim Einspielen -A).

X86-ALTKNOTEN
  Gluon baut fuer x86 seit 2023.2 das EFI-Image (Bootpartition FAT). Gluon bis
  2021.1 legt beim sysupgrade die Konfiguration per "mount -t ext4" auf
  Partition 1 ab und verliert sie dort (Gluon #2967). Liegt zum
  x86-sysupgrade-Image ein "...-<target>-mbr-sysupgrade.img.gz" (MBR,
  Bootpartition ext4) im Image-Verzeichnis, zeigen die x86-Zeilen darauf:
    Vorgabe (-x alt): nur die 4-Feld-Zeilen (Knoten bis 2017.1); fuer
      x86-generic das x86-legacy-MBR-Image, wenn vorhanden (bis 2016.2 war
      "generic" i486-Klasse, seit 2017.1 braucht es SSE2).
    -x alle: auch die 5-Feld-Zeile, nur fuer Manifeste, die allein alte
      Knoten lesen (ein UEFI-only-Rechner bootet kein MBR).
    -x aus: nichts umlenken.
  Das MBR-Image baut Gluon in images/other/; hier muss es im
  Image-Verzeichnis liegen (Symlink). Liegt es nur in ../other, bricht das
  Skript mit dem passenden ln-Befehl ab; fehlt es ganz, ebenfalls (ausser -x
  aus). Ablauf: router-werkstatt docs/howto-x86-altknoten-2025.md

GRENZEN
  Ein Knoten mit alter Firmware kann nicht beliebig springen. Gluon 2025.1
  aktualisiert nur ab v2022.1, und ar71xx -> ath79 braucht passende Images.
  Das Manifest muss auf ein Zwischen-Image zeigen, das die alte Firmware
  flashen kann; dieses Skript macht nur das Manifest lesbar.

AUFRUF
  manifest-altformat.sh [optionen] <manifest> [image-verzeichnis]

  <manifest>          z. B. /var/www/firmware/stable/21_dias/sysupgrade/stable.manifest
  [image-verzeichnis] Vorgabe: das Verzeichnis des Manifests

OPTIONEN
  -a datei   weitere alte Modellnamen; Format "alt neu" je Zeile, "#" als
             Kommentar. Die bekannten (manifest_aliases von Gluon v2023.2.6,
             Namen aus v2022.1/v2023.1 und der 4-Feld-Zeit) sind eingebaut.
  -o datei   Ausgabe in diese Datei statt auf die Standardausgabe
  -x modus   x86-Altknoten: alt (Vorgabe), alle oder aus, siehe X86-ALTKNOTEN
  -h, --help diese Hilfe

BEISPIELE
  manifest-altformat.sh stable.manifest > stable.manifest.alt
  manifest-altformat.sh -o /tmp/stable.manifest \
      /var/www/firmware/stable/21_dias/sysupgrade/stable.manifest

VORAUSSETZUNGEN
  bash, awk, sha512sum (coreutils) bzw. shasum

EXIT-CODES
  0  fertig
  1  Image fehlt oder passt nicht zur sha256 im Manifest (dann keine Ausgabe)
  2  falscher Aufruf
EOT
}

# Diese Namen bekommen nie 4-Feld-Zeilen: Das sysupgrade von OpenWrt 15.05
# (Gluon 2016.2) lehnt ath79-Images dieser Geraete ab (support-list an anderem
# Offset). Der Autoupdater hat das Netz dann schon gestoppt, der Knoten bleibt
# bis zum Stromreset offline.
declare -ra OHNE_4FELD=(
	"tp-link-cpe210-v1.0"
	"tp-link-cpe210-v1.1"
	"tp-link-cpe220-v1.0"
	"tp-link-cpe220-v1.1"
	"tp-link-cpe510-v1.0"
	"tp-link-cpe510-v1.1"
	"tp-link-cpe520-v1.0"
	"tp-link-cpe520-v1.1"
)

# Alte -> heutige Modellnamen ("alt neu"), Stand 05.10.2026: manifest_aliases aus Gluon v2023.2.6 (in v2025.1 entfernt),
# Namen nur aus v2022.1/v2023.1 und die Namen der 4-Feld-Zeit, wie Gluon sie
# damals selbst zugeordnet hat. Abgeschlossen; Ergaenzungen per -a.
declare -ra ALIAS_ALT=(
	# Alte Gluon-Modellnamen -> heutige, aus den manifest_aliases von Gluon v2023.2.6
	# (targets/*, "upgrade from OpenWrt 19.07"; in v2025.1 entfernt, Gluon 4e2bf620).
	# Am Ende ergaenzt: Namen, die nur v2022.1/v2023.1 kannten.
	# Die alten Namen sind die der ar71xx-/ramips-Zeit, so wie sie auch Gluon
	# 2016.2 bis 2020.2 meldet (z. B. tp-link-tl-wr1043n-nd-v4). Format: alt neu
	"asus-rt-ac57u asus-rt-ac57u-v1"
	"buffalo-wzr-hp-g300nh buffalo-wzr-hp-g300nh-rtl8366s"
	"cudy-wr1300 cudy-wr1300-v1"
	"d-link-dir-505-rev-a1 d-link-dir-505"
	"d-link-dir-505-rev-a2 d-link-dir-505"
	"d-link-dir-825-rev-b1 d-link-dir825b1"
	"gl-inet-6416a-v1 gl.inet-6416"
	"gl.inet-gl-ar300m gl.inet-gl-ar300m-nor"
	"netgear-ex3700-ex3800 netgear-ex3700"
	"netgear-wndr3700v2 netgear-wndr3700-v2"
	"netgear-wndr3700v5 netgear-wndr3700-v5"
	"netgear-wndr3800chmychart netgear-wndr3800ch"
	"netgear-wnr2200 netgear-wnr2200-8m"
	"openmesh-mr1750 openmesh-mr1750-v1"
	"openmesh-mr1750v2 openmesh-mr1750-v2"
	"openmesh-mr600 openmesh-mr600-v1"
	"openmesh-mr600v2 openmesh-mr600-v2"
	"openmesh-mr900 openmesh-mr900-v1"
	"openmesh-mr900v2 openmesh-mr900-v2"
	"openmesh-om2p openmesh-om2p-v1"
	"openmesh-om2p-hs openmesh-om2p-hs-v1"
	"openmesh-om2p-hsv2 openmesh-om2p-hs-v2"
	"openmesh-om2p-hsv3 openmesh-om2p-hs-v3"
	"openmesh-om2p-hsv4 openmesh-om2p-hs-v4"
	"openmesh-om2pv2 openmesh-om2p-v2"
	"openmesh-om2pv4 openmesh-om2p-v4"
	"openmesh-om5p-ac openmesh-om5p-ac-v1"
	"openmesh-om5p-acv2 openmesh-om5p-ac-v2"
	"raspberry-pi-2-model-b-rev-1.1 raspberrypi-2-model-b"
	"raspberry-pi-3-model-b-plus-rev-1.3 raspberrypi-3-model-b"
	"raspberry-pi-3-model-b-rev-1.2 raspberrypi-3-model-b"
	"raspberry-pi-4-model-b-rev-1.1 raspberrypi-4-model-b"
	"raspberry-pi-4-model-b-rev-1.2 raspberrypi-4-model-b"
	"raspberry-pi-4-model-b-rev-1.4 raspberrypi-4-model-b"
	"raspberry-pi-4-model-b-rev-1.5 raspberrypi-4-model-b"
	"raspberry-pi-model-b-plus-rev-1.2 raspberrypi-model-b"
	"raspberry-pi-model-b-rev-1 raspberrypi-model-b"
	"raspberry-pi-model-b-rev-2 raspberrypi-model-b"
	"raspberrypi-3-model-b-plus raspberrypi-3-model-b"
	"raspberrypi-model-b-plus raspberrypi-model-b"
	"raspberrypi-model-b-rev2 raspberrypi-model-b"
	"tp-link-archer-c50 tp-link-archer-c50-v1"
	"tp-link-archer-c6-v2 tp-link-archer-c6-v2-eu-ru-jp"
	"tp-link-cpe210-v1.0 tp-link-cpe210-v1"
	"tp-link-cpe210-v1.1 tp-link-cpe210-v1"
	"tp-link-cpe210-v2.0 tp-link-cpe210-v2"
	"tp-link-cpe210-v3.0 tp-link-cpe210-v3"
	"tp-link-cpe210-v3.1 tp-link-cpe210-v3"
	"tp-link-cpe210-v3.20 tp-link-cpe210-v3"
	"tp-link-cpe510-v1.0 tp-link-cpe510-v1"
	"tp-link-cpe510-v1.1 tp-link-cpe510-v1"
	"tp-link-tl-wr1043n-nd-v2 tp-link-tl-wr1043nd-v2"
	"tp-link-tl-wr1043n-nd-v3 tp-link-tl-wr1043nd-v3"
	"tp-link-tl-wr1043n-nd-v4 tp-link-tl-wr1043nd-v4"
	"tp-link-tl-wr2543n-nd-v1 tp-link-tl-wr2543n-nd"
	"tp-link-tl-wr842n-nd-v3 tp-link-tl-wr842n-v3"
	"tp-link-wbs210-v1.20 tp-link-wbs210-v1"
	"tp-link-wbs510-v1.20 tp-link-wbs510-v1"
	"ubiquiti-unifi ubiquiti-unifi-ap"
	"ubiquiti-unifi-6-lr ubiquiti-unifi-6-lr-v1"
	"ubiquiti-unifiap-outdoor+ ubiquiti-unifi-ap-outdoor+"
	"ubnt-erx ubiquiti-edgerouter-x"
	"ubnt-erx-sfp ubiquiti-edgerouter-x-sfp"
	"x86-kvm x86-generic"
	"x86-xen_domu x86-generic"
	"zbt-wg3526 zbtlink-zbt-wg3526-16m"
	"zbt-wg3526-16m zbtlink-zbt-wg3526-16m"
	"zbt-wg3526-32m zbtlink-zbt-wg3526-32m"
	# Ergaenzt 04.10.2026: nur in v2022.1.4 und v2023.1.2, in v2023.2 schon entfernt
	"tp-link-re355 tp-link-re355-v1"
	"tp-link-re450 tp-link-re450-v1"
	# Bewusst NICHT (05.10.2026):
	# - netgear-wndr3700v4 -> netgear-wndr3700-v4: Upgrade-Pfad nie gegangen
	#   (Kernelpartition gewachsen), Gluon e1437781 / OpenWrt 0d28e5d6.
	# Ergaenzt 05.10.2026: Gluon hat keinen Alias, OpenWrt ath79 fuehrt den
	# ar71xx-Namen aber in SUPPORTED_DEVICES (sysupgrade nimmt das Image an):
	"d-link-dap-1330-rev-a1 d-link-dap-1330-a1"
	"netgear-wndrmacv2 netgear-wndrmac-v2"
	# Ubiquiti NanoStation XW (ar71xx -> ath79), ergaenzt 05.10.2026 (adorfer): Gluon hat
	# die Aliase mit dem AirMax-Ausbau (a0f5b4e9, Gefahr eines schreibgeschuetzten
	# Flash, betrifft die Erstinstallation aus AirOS) entfernt und beim Wiedereinbau
	# (37bbab91) nicht zurueckgeholt. Der Sprung Sackgasse -> 2023.1.5 ging aber per
	# handgemachtem Manifest an einer Station in RDV ohne Eingriff durch.
	# ubiquiti-nanostation-m-xw heisst in beiden gleich und braucht keinen Alias.
	# Rocket M XW nicht: ath79 baut dafuer kein Gluon-Image.
	"ubiquiti-loco-m-xw ubiquiti-nanostation-loco-m-xw"
	"ubiquiti-nanostation-loco-m2-xw ubiquiti-nanostation-loco-m-xw"
	"ubiquiti-nanostation-loco-m5-xw ubiquiti-nanostation-loco-m-xw"
	"ubiquiti-nanostation-m2-xw ubiquiti-nanostation-m-xw"
	"ubiquiti-nanostation-m5-xw ubiquiti-nanostation-m-xw"
	# Achtung fuer Manifeste, die Gluon-2016.2-Knoten lesen: tp-link-cpe210-v1.x und
	# tp-link-cpe510-v1.x NICHT aufnehmen. Das sysupgrade von OpenWrt 15.05 lehnt das
	# ath79-Image ab (support-list fehlt), nachdem der Autoupdater das Netz schon
	# gestoppt hat; der Knoten bleibt bis zum Stromreset offline.
	# Ergaenzt 05.10.2026: Namen der 4-Feld-Zeit (Gluon 2015.1-2017.1), die weder
	# 2023.2 noch die Sackgasse fuehren, abgebildet wie damals in Gluon selbst
	# (fuer manifeste-zusammenfuehren.sh / manifest-altformat.sh -a).
	# WR940N v1-v3 liefen bis 2016.2 als GluonModelAlias der WR941N/ND v4-v6:
	"tp-link-tl-wr940n-nd-v1 tp-link-tl-wr941n-nd-v4"
	"tp-link-tl-wr940n-nd-v2 tp-link-tl-wr941n-nd-v5"
	"tp-link-tl-wr940n-nd-v3 tp-link-tl-wr941n-nd-v6"
	# Gluon 2015.1: Loco M und PicoStation M (XM) bekamen das ubnt-bullet-m-Image:
	"ubiquiti-loco-m ubiquiti-bullet-m"
	"ubiquiti-picostation-m ubiquiti-bullet-m"
	# x86-Varianten: dasselbe combined-Image wie generic bzw. 64 (VDI/VMDK nur
	# als Factory-Format verschieden):
	"x86-virtualbox x86-generic"
	"x86-vmware x86-generic"
	"x86-64-virtualbox x86-64"
	"x86-64-vmware x86-64"
	# x86-xen (Ziel x86-xen_domu, bis Gluon 2016.2) hat KEINEN Weg: x86-xen_domu steht in
	# keinem heutigen Manifest, der Knoten meldet "No matching firmware found". Ein Alias
	# auf x86-generic waere ungetestet und bricht vermutlich (domU paravirtualisiert, heute
	# GRUB). Solche Knoten von Hand umstellen.
	"x86-xen x86-xen_domu"
)

falsch() { echo "$1" >&2; echo "Hilfe: $0 --help" >&2; exit 2; }

for arg in "$@"; do
	case "$arg" in --help|-h) hilfe; exit 0 ;; esac
done

ALIASE=""; AUS=""; X86="alt"
while getopts "a:o:x:" opt; do
	case "$opt" in
		a) ALIASE="$OPTARG" ;;
		o) AUS="$OPTARG" ;;
		x) X86="$OPTARG" ;;
		*) falsch "Unbekannte Option." ;;
	esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] && [ $# -le 2 ] || falsch "Erwartet: <manifest> [image-verzeichnis]"

M="$1"
DIR="${2:-$(dirname "$M")}"
[ -r "$M" ] || falsch "$M nicht lesbar."
[ -d "$DIR" ] || falsch "$DIR ist kein Verzeichnis."
[ -z "$ALIASE" ] || [ -r "$ALIASE" ] || falsch "$ALIASE nicht lesbar."
case "$X86" in alt|alle|aus) ;; *) falsch "-x kennt nur alt, alle oder aus." ;; esac
if command -v sha512sum >/dev/null 2>&1; then S512="sha512sum"; S256="sha256sum"
else S512="shasum -a 512"; S256="shasum -a 256"; fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Teil vor "---"; 4-Feld-Zeilen fliegen raus, sie werden neu erzeugt
sed '/^---$/,$d' "$M" > "$TMP/oben"
grep -q '^BRANCH=' "$TMP/oben" || { echo "$M ist kein Manifest (keine BRANCH-Zeile)." >&2; exit 1; }

# sha512 je Datei einmal; dabei die sha256 aus dem Manifest gegenpruefen
awk 'NF == 5 { print $5, $3 }' "$TMP/oben" | sort -u > "$TMP/dateien"
: > "$TMP/sha512"
fehler=0
while read -r f h256; do
	if [ ! -f "$DIR/$f" ]; then
		echo "fehlt: $DIR/$f" >&2; fehler=1; continue
	fi
	ist="$($S256 "$DIR/$f" | cut -d' ' -f1)"
	if [ "$ist" != "$h256" ]; then
		echo "sha256 passt nicht: $f (Datei $ist, Manifest $h256)" >&2; fehler=1; continue
	fi
	echo "$f $($S512 "$DIR/$f" | cut -d' ' -f1)" >> "$TMP/sha512"
done < "$TMP/dateien"

# x86-Altknoten: EFI-Image -> MBR-Image, siehe X86-ALTKNOTEN.
# Je Zeile: <datei> <4feld-datei> <sha256> <sha512> <5feld-datei> <sha256> <groesse>
: > "$TMP/mbr"
if [ "$X86" != aus ]; then
	leg="$(cd "$DIR" && find . -maxdepth 1 -name '*-x86-legacy-mbr-sysupgrade.img.gz' -printf '%f\n' | head -n 1)"
	while read -r f _; do
		m="${f%-sysupgrade.img.gz}-mbr-sysupgrade.img.gz"
		if [ ! -f "$DIR/$m" ]; then
			if [ -f "$DIR/../other/$m" ]; then
				echo "x86: $m liegt nur in other/; verlinken: ln -s ../other/$m $DIR/" >&2
			else
				echo "x86: $m fehlt; x86-Knoten bis 2021.1 verlieren mit $f die Konfiguration (-x aus, wenn gewollt)" >&2
			fi
			fehler=1; continue
		fi
		m4="$m"
		case "$f" in
			*-x86-generic-sysupgrade.img.gz)
				if [ -n "$leg" ]; then m4="$leg"
				else echo "x86: kein x86-legacy-MBR-Image; Knoten bis 2016.2 ohne SSE2 bekaemen x86-generic (pentium4)" >&2; fi ;;
		esac
		echo "$f $m4 $($S256 "$DIR/$m4" | cut -d' ' -f1) $($S512 "$DIR/$m4" | cut -d' ' -f1)" \
			"$m $($S256 "$DIR/$m" | cut -d' ' -f1) $(wc -c < "$DIR/$m" | tr -d ' ')" >> "$TMP/mbr"
	done < <(grep -E -- '-x86-(generic|legacy|64)-sysupgrade\.img\.gz ' "$TMP/dateien")
fi
[ "$fehler" = 0 ] || { echo "Abbruch, keine Ausgabe." >&2; exit 1; }

# alte Namen: Zuordnung neu -> alt (ein neuer Name kann mehrere alte haben)
{ printf '%s\n' "${ALIAS_ALT[@]}"; [ -n "$ALIASE" ] && cat "$ALIASE"; } \
	| sed 's/#.*//' | awk 'NF == 2 { print $2, $1 }' > "$TMP/alias"
printf '%s\n' "${OHNE_4FELD[@]}" > "$TMP/ohne4"

{
	awk -v shafile="$TMP/sha512" -v aliasfile="$TMP/alias" -v ohnefile="$TMP/ohne4" \
	    -v mbrf="$TMP/mbr" -v alle="$( [ "$X86" = alle ] && echo 1 || echo 0)" '
		BEGIN {
			while ((getline z < shafile) > 0) { split(z, a, " "); s512[a[1]] = a[2] }
			while ((getline z < mbrf) > 0) { split(z, a, " ")
				m4[a[1]] = a[2]; m4s[a[1]] = a[3]; m4x[a[1]] = a[4]
				m5[a[1]] = a[5]; m5s[a[1]] = a[6]; m5g[a[1]] = a[7] }
			while ((getline z < aliasfile) > 0) { split(z, a, " "); alt[a[1]] = alt[a[1]] " " a[2] }
			while ((getline z < ohnefile) > 0) ohne[z] = 1
		}
		function drei(modell) {
			if (alle && ($5 in m5)) print modell, $2, m5s[$5], m5g[$5], m5[$5]
			else print modell, $2, $3, $4, $5
			if (modell in ohne) return
			if ($5 in m4) {
				print modell, $2, m4s[$5], m4[$5]
				print modell, $2, m4x[$5], m4[$5]
				return
			}
			print modell, $2, $3, $5
			print modell, $2, s512[$5], $5
		}
		NF == 4 { next }
		NF == 5 {
			drei($1)
			n = split(alt[$1], namen, " ")
			for (i = 1; i <= n; i++) if (!(namen[i] in schon)) { drei(namen[i]); schon[namen[i]] = 1 }
			next
		}
		{ print }' "$TMP/oben"
	echo "---"
} > "$TMP/neu"

n_alt="$(awk 'NF == 5' "$TMP/oben" | wc -l | tr -d ' ')"
n_neu="$(awk 'NF == 5' "$TMP/neu" | wc -l | tr -d ' ')"
echo "Modellzeilen: $n_alt -> $n_neu (davon $((n_neu - n_alt)) alte Namen), je drei Formate; Unterschriften verworfen, neu unterschreiben." >&2

if [ -n "$AUS" ]; then
	cp "$TMP/neu" "$AUS" || exit 1
else
	cat "$TMP/neu"
fi
exit 0

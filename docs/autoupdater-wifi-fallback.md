# ffac-autoupdater-wifi-fallback: Verhalten und Praxistest

Stand 07.10.2026. Paket `ffac-autoupdater-wifi-fallback` aus
freifunk-gluon/community-packages (bei uns gepinnt auf `1900131`, unter 2025.1
über den Feed `community`; für die Sackgasse 2021.1 als Kopie im Feed-Zweig
`v2021.1.x`, Stand `1493e17`). Zwischen beiden Ständen hat sich am Paket nichts
geändert; was hier steht, gilt für beide Linien. Die Beschreibung folgt dem Code
(`/usr/sbin/autoupdater-wifi-fallback`, `autoupdater-wifi-fallback/util.lua`,
`510-autoupdater-wifi-fallback`), der Praxistest lief am 06.10.2026 auf einem
TL-WR1043ND v2 unter Gluon 2025.1.

## Wozu

Ein Knoten, der weder über WLAN-Mesh noch über Kabel-Mesh noch über VPN ins Netz
kommt, bekommt auch keine neue Firmware. Der Fallback hängt ihn in diesem Fall
als WLAN-Client an ein offenes Freifunk-WLAN in Reichweite und lässt den
Autoupdater von dort aus laufen. Typischer Fall: Ein Knoten nur mit WLAN-Mesh,
dessen Nachbarn schon auf einer neuen Firmware mit inkompatiblem Mesh sind.

## Ablauf laut Code

**Wann er läuft:** stündlich per micrond. Die Minute legt
`510-autoupdater-wifi-fallback` fest: 10 Minuten nach der Minute des
Autoupdaters (`/usr/lib/micron.d/autoupdater`). Beim 4402 lief der Autoupdater
zur :49, der Fallback zur :59. Eine Sperre (`/var/lock/autoupdater-wifi-fallback.lock`)
verhindert parallele Läufe.

**Vorbedingungen** (alle, sonst passiert nichts):

- `autoupdater-wifi-fallback.settings.enabled = 1`. Beim ersten Einrichten
  übernimmt `510` den Wert von `autoupdater.settings.enabled`.
- `autoupdater.settings.enabled = 1`. Wer den Autoupdater abschaltet, schaltet
  damit auch den Fallback ab.
- Uptime mindestens 3600 s.
- Für den Zweig (`autoupdater.settings.branch`, mit `-b` überschreibbar) gibt
  es eine Sektion in `/etc/config/autoupdater`, sonst bricht er mit Fehler ab.

**Was als „offline“ gilt:** keine Datei `/var/gluon/state/has_default_gw4`
(gluon-state-check: kein Gateway in `batctl gwl`; in der 2021.1-Kopie direkt
geprüft) **und** keiner der Mirror-Hosts des Zweigs antwortet auf
`ping -w2 -c1`. Ist eines davon erfüllt, gilt der Knoten als online und der
Merker wird gelöscht.

**Zeitgrenze:**

- Der erste Lauf, der offline feststellt, schreibt die Uhrzeit nach
  `autoupdater-wifi-fallback.settings.unreachable_since`, jeder weitere nach
  `last_run`. Beides nur per `uci save`, also im RAM: **ein Neustart setzt die
  Zeit zurück.**
- Fallback erst, wenn `unreachable_since + 7200 < jetzt`, also **streng mehr
  als 2 h**. Weil der Lauf stündlich zur selben Minute kommt, liegt der Lauf
  „genau 2 h später“ oft wenige Sekunden darunter. Praktisch kommt der Fallback
  deshalb meist **3 h nach dem ersten Offline-Vermerk**. Mit der Mindest-Uptime
  von 1 h liegt er frühestens gut 3 h, meist 4 bis 5 h nach dem Boot.
- Gerechnet wird mit der Uhrzeit (`os.time()`), nicht mit der Uptime. Springt
  die Uhr per NTP, verschiebt sich die Grenze. Ohne Gateway kommt meist kein NTP,
  die Uhr läuft dann gleichmäßig von der Startzeit (sysfixtime) aus.

**Fallback:**

1. Log `going to fallback mode`, `wifi down`, wpad aus. Damit sind auch die
   eigenen Client-WLANs weg.
2. Je Radio ein Scan (iwinfo), behalten werden SSIDs, die „freifunk“ in
   beliebiger Groß/Kleinschreibung enthalten. Das trifft „Freifunk“ und
   „Freifunk verschluesselt“ (OWE), aber nicht die Offline-SSIDs anderer
   Knoten (`FF_Offline_...`). Die Reihenfolge ist die des Scans, nicht nach
   Signal sortiert.
3. Je Treffer: Interface `fallback_if` (managed) auf dem phy, `iw connect`
   offen auf SSID und BSSID, dynamische Interfaces `fallback` (DHCP) und
   `fallback6` (DHCPv6), 20 s warten, dann `autoupdater -f -b <zweig>`.
   Bei OWE scheitert der offene Connect; das kostet nur Zeit.
4. Findet der Autoupdater ein neueres Image, flasht er, und der Knoten startet
   mit der neuen Firmware. Die Konfiguration bleibt.
5. Sonst geht es zum nächsten Treffer. Der Rückgabewert des Autoupdaters wird
   nicht ausgewertet (`run_autoupdater()` gibt nichts zurück), es werden also
   immer **alle** passenden WLANs nacheinander versucht. Danach wpad an,
   `wifi up`, 30 s warten.
6. Der Merker bleibt stehen: Ohne Update wiederholt sich der Fallback **jede
   Stunde**, und jedes Mal ist das eigene WLAN für alle Versuche zusammen weg.
   Bei vielen Freifunk-WLANs in Reichweite können das einige Minuten sein.
   Für Clients ist das kaum ein Verlust (ohne Gateway ist ohnehin die
   Offline-SSID an), für die Fehlersuche vor Ort schon.

**Dauerhaft in der Konfiguration:** `510` legt `network.fallback` und
`network.fallback6` an, ohne Gerät. Sie stehen im Normalbetrieb mit
`NO_DEVICE` in `ubus call network.interface dump`; das ist kein Rest eines
Fallbacks.

**Von Hand:** `autoupdater-wifi-fallback -f` überspringt Vorbedingungen und
Zeitgrenze und geht sofort in den Fallback, sobald die Offline-Prüfung
fehlschlägt, mit `-b <zweig>` auf einem anderen Zweig. **Das flasht**, wenn es
ein Image gibt.

**respondd:** `nodeinfo.software.autoupdater.wifi-fallback` (true/false, nur
`enabled`).

## Zusammenspiel mit unseren Paketen

- **wifi-blackout** (Neustart des WLANs, später Reboot, wenn lange keine Station
  da ist): greift frühestens 281 min nach Boot oder letzter Aktion und nach
  171 min ohne Station ein, zuerst nur mit WLAN-Neustart, den Reboot erst
  281 min später. Der Fallback kommt bei einem offline gegangenen Knoten
  davor. Während der Fallback läuft, ist kein WLAN-Interface oben, wifi-blackout
  tut dann nichts. Nur Knoten, die schon vorher nie Clients hatten, können einen
  Zyklus Verzögerung bekommen.
- **Weekly Reboot und andere Neustarts** setzen den Merker zurück (RAM). Ein
  Knoten, der in kürzeren Abständen als etwa 3 bis 4 h neu startet, kommt nie in
  den Fallback.
- **ssid-changer** stellt ohne Gateway auf die Offline-SSID um; der Hostname
  wird darin mit „...“ gekürzt (`FF_Offline_dias-104...est-4402`).
- **ap-timer**: Er schaltet das Client-WLAN über das uci-Delta ab. `wifi up` am
  Ende eines Fallbacks ohne Update baut die WLANs aus uci samt Delta neu, eine
  laufende Aus-Zeit bleibt also bestehen (aus dem Code abgeleitet, nicht
  getestet).

## Praxistest am 06.10.2026 (TL-WR1043ND v2, Gluon 2025.1)

Knoten `dias-1043v2-test-4402`, Domain 21_dias. Ziel: Ein isolierter Knoten mit
herabgesetzter Versionsnummer soll ohne Eingriff per Fallback auf die aktuelle
Testfirmware kommen.

**Vorbereitung** (alles per uci und commit, danach Neustart):

- Firmware 2025.1-Testbau, `/lib/gluon/release` auf `26100500-tst` gesetzt,
  damit `26100604bro` als neuer gilt.
- Autoupdater Zweig `broken`, Mirror auf den Testbau-Server
  (images-1791252771).
- WLAN-Mesh aus (2.4 GHz nur Client), Kanal 13, auf dem es keine eigenen
  Mesh-Nachbarn gab; VPN aus; LAN ohne Rolle; Checks von linkcheck und hotfix
  aus (außer dem Watchdog), wifi-blackout aus.
- Rückweg ohne Handarbeit: ein Skript in `sysupgrade.conf`, aufgerufen aus
  `rc.local`, das nach dem ersten Boot mit echter Firmware die Testeinstellungen
  zurücknimmt und neu startet.
- Mitschnitt des Syslogs über einen WLAN-Stick an einem PC in Reichweite,
  verbunden mit dem Client-WLAN des Knotens.

**Zeitablauf:**

| Uhrzeit | Uptime | Ereignis |
|---|---|---|
| 18:26:30 | 0 | Boot in den Testzustand |
| 18:32 | 6 min | ssid-changer: Offline-SSID (kein Gateway) |
| 18:59 | 33 min | Fallback-Lauf: Uptime unter 1 h, nichts |
| 19:49 | 1 h 23 min | normaler Autoupdater: `no usable mirror found` (so auch 20:49, 21:49, 22:49) |
| **19:59:26** | 1 h 33 min | `connectivity check failed`, **`unreachable_since` gesetzt** |
| 20:59:06 | 2 h 33 min | `connectivity check failed`, erst 59 min seit dem Vermerk |
| 21:59:05 | 3 h 33 min | `connectivity check failed`, 1 h 59 min 39 s, **21 s unter der Grenze** |
| **22:59:06** | 4 h 33 min | `connectivity check failed`, **`going to fallback mode`**, WLAN aus (Mitschnitt reißt ab) |
| 22:59 bis 23:01 | | Scan, Client-Verbindung, DHCP, Autoupdater lädt `26100604bro` (6,8 MB) und flasht |
| **23:02:26** | etwa 30 s | **`26100604bro` läuft**, Konfiguration erhalten, Rückweg-Skript startet |

Vom Beginn des Fallbacks bis zum laufenden neuen Image vergingen etwa
3 Minuten. Mit welchem der Freifunk-WLANs in Reichweite sich der Knoten
verbunden hat, ist nicht belegt: Der Mitschnitt riss mit `wifi down` ab, das
Remote-Syslog bekam über die Client-Verbindung keine Zeilen, und das lokale Log
ging mit dem Flash verloren.

**Belegt** sind damit am Gerät: die Offline-Erkennung, die Mindest-Uptime, die
strenge 2-h-Grenze, Client-Verbindung und DHCP über ein fremdes Freifunk-WLAN
(die Firewall lässt das ohne Zone zu), Autoupdate und Flash aus dem Fallback
heraus, Erhalt der Konfiguration.

**Nicht belegt:** der Weg ohne Update (zurück ins normale WLAN, stündliche
Wiederholung) und der Fall mehrerer Treffer mit fehlschlagendem ersten.

**Fehler im Testaufbau** (nicht im Paket), als Hinweis für Wiederholungen:

- Die Autoupdater-Einstellungen erst **nach** dem letzten `gluon-reconfigure`
  ändern. Das Reconfigure schreibt die Zweige aus der site.conf neu, und
  neanderfunk-migrate-updatebranch stellt `broken` auf `stable` zurück. Beim
  ersten Anlauf stand der Knoten deshalb auf `stable` und hätte nichts gefunden
  (um 20:05 von Hand korrigiert).
- Interface-Rollen nur per `uci delete` und `uci add_list` setzen. Ein
  `uci set gluon.iface_lan.role=mesh` macht eine einfache Option; Gluons
  `021`, `110` und `210` brechen daran ab, und nach dem Reconfigure fehlen WAN,
  Client-Bridge und Kabel-Mesh. So geschehen im Rückweg-Skript; von Hand
  repariert, um 23:42 war der Knoten wieder normal im Netz.
- Den Mitschnitt-Supplicant auf die Offline-SSID mit der **gekürzten** Form
  einstellen, sonst ist der Knoten nach der Umstellung nicht mehr erreichbar.

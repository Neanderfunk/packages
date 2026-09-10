# Neanderfunk-Pakete gegen Gluon 2025.1.x

Statische Prüfung vom 2026-09-08, Quellenstand `v2023.2.6` (unser Betrieb) gegen
`v2025.1.3`. Verglichen wurde der Gluon-Baum unter
`~/projekte/freifunk/firmware/gluon`, dazu die beiden gepinnten OpenWrt-Stände
und die Feed-Pins für `autoupdater` und `batctl`. Ohne Hardware mit 2025.1
konnte nichts davon am lebenden Objekt gegengeprüft werden; wo eine Aussage nur
aus dem Quelltext stammt, steht das dabei.

Grundlage: **OpenWrt 23.05 → 24.10**, Kernel 5.15 → 6.6, 265 geänderte Dateien
im Gluon-Baum.

## Kurzfassung

Nichts von uns bricht hart. Drei Stellen tragen echtes Risiko, zwei davon sind
Zeitbomben mit langer Zündschnur, eine ist schon heute toter Code. Der größte
inhaltliche Einschnitt ist, dass **tunneldigger aus Gluon geflogen ist**.

## 1. Was sich ändert und uns betrifft

### 1.1 `radioN` ist nicht mehr dasselbe wie `phyN`

In OpenWrt 24.10 erzeugt nicht mehr die Shell die `wifi-device`-Sektionen,
sondern ucode (`/usr/share/hostap/wifi-detect.uc` und `/lib/wifi/mac80211.uc`).
Die Sektionen heißen weiterhin `radio0`, `radio1`, … — aber der Zähler läuft
jetzt über **Radios**, nicht über phys:

```ucode
let radios = length(info.radios) > 0 ? info.radios : [{ bands: info.bands }];
for (let radio in radios) {
    while (config[`radio${idx}`]) idx++;
    let name = "radio" + idx;
```

Ein einzelner wiphy kann mehrere Radios melden (nl80211 `radios`, gedacht für
MLO/Wi-Fi-7-Chips). Dann belegt phy0 zum Beispiel `radio0` **und** `radio1`, und
phy1 wird `radio2`. Die Sektion referenziert das Gerät über `path=` plus
`option radio '<index>'`, nicht über den phy-Namen.

Betroffen bei uns: **`neanderfunk-hotfix/check_hostapd.sh`**, die einzige Stelle
mit echter Index-Arithmetik:

```sh
radio="radio"${phy:3:1}
client="client"${phy:3:1}
```

Das leitet Radio- und Client-Index aus dem phy-Namen ab. Auf unserer Hardware
(ath9k, ath10k, mt7915, filogic) meldet jeder phy genau ein Radio, die Annahme
hält also weiter. Auf Wi-Fi-7-Hardware hielte sie nicht mehr.

**Praktisch ist das aber egal, weil der Check heute schon nicht läuft** — siehe
Abschnitt 4.

### 1.2 Unsere Iteratoren hören bei Radio 2 auf

Die Release Notes zu 2025.1 sagen ausdrücklich: *„This change also enables
support for devices with more than 2 radios in total."* Zwei Stellen bei uns
zählen fest bis 2:

| Datei | Stelle |
| --- | --- |
| `neanderfunk-ssid-changer/…/ssid-changer.lua` | `for i = 0, 2` an zwei Stellen (`client_radio`, `owe_radio`) |
| `neanderfunk-linkcheck/…/linkcheck.sh:197` | feste Liste `wireless.{mesh,batmesh,client}_radio{0,1,2}` |

Drei Radios sind damit abgedeckt, vier nicht. Das bricht nichts — es macht ein
viertes Radio nur unsichtbar: der ssid-changer würde es nicht auf die
Offline-SSID schalten, linkcheck würde es nicht scannen. Beide Schleifen
überspringen fehlende Sektionen sauber (`if [ ! -z "${linkname}" ]` bzw.
`if client_ssid then`), es gibt also keine Fehlerkaskade.

Die dynamische Schleife in `linkcheck.sh:395`
(`uci show wireless | grep -oE '(ibss|mesh)_radio[0-9]+'`) hat das Problem
nicht.

### 1.3 `wifi-iface`-Sektionen werden bei jedem Reconfigure neu erzeugt

Aus den Release Notes (`#3563`):

> All ``wifi-iface`` sections in ``/etc/config/wireless`` are regenerated on
> upgrades and config changes now. The ``gluon_preserve`` option can be used for
> custom interface sections.

Für den **ssid-changer** heißt das: die Offline-SSID überlebt ein `wifi reconf`
(das wendet nur an), aber kein `gluon-reconfigure`. Das ist heute schon so, wird
in 2025.1 aber verbindlich und vollständig. Kein Handlungsbedarf, solange wir
keine eigenen `wifi-iface`-Sektionen anlegen — täten wir das, bräuchten sie
`gluon_preserve`.

Für **txpowerfix** (`215-`) ist es unkritisch: es schreibt in
`wifi-device`-Sektionen (`country`, `htmode`), nicht in `wifi-iface`, und läuft
nach `200-wireless`. Regeneriert werden nur die `wifi-iface`-Sektionen.
(`ch13to9` stand hier ebenfalls; das Paket ist seit 2026-09-10 entfernt.)

### 1.4 tunneldigger ist aus Gluon entfernt

`e0d649c3 gluon-mesh-vpn-tunneldigger: drop package (#3109)` — verschoben nach
`community-packages/ff-mesh-vpn-tunneldigger`. In 2025.1 bleiben nur `fastd` und
`wireguard`.

Folgen für uns:

* Der Check `hotfix.tunneldigger` (zu viele Watchdogs/Instanzen) wird toter
  Code. Harmlos, er zählt dann eben null.
* `gluon-mesh-vpn-tunneldigger/luasrc/usr/bin/tunneldigger-watchdog` ist weg —
  damit erledigt sich auch die gestrige Log-Rausch-Frage, sobald ein Knoten auf
  WireGuard läuft.
* `mesh-vpn` als Interface-Name bleibt, den legt auch WireGuard an. Unsere
  linkcheck-Prüfungen darauf bleiben gültig.

### 1.5 mt7915: der Kernel räumt jetzt selbst auf

Neu in 2025.1: `patches/openwrt/0012-mt7915-detect-and-purge-stuck-PLE-queues.patch`
(David Bauer) — der Treiber pollt die Queue-Zustände und leert festhängende
Queues selbst.

Das ist ein Treiber-seitiger Fix für genau die Symptomklasse, gegen die
**`neanderfunk-mt7915-backlog`** als Notbehelf gebaut wurde (`gluon#3154`).
Unser Paket misst den mac80211-txq-Backlog über `iw phy … get txq` und startet
bei >50 das WLAN neu. Unter 2025.1 sollte der Zustand seltener bis gar nicht
mehr auftreten — dann wirft unser Workaround im Zweifel grundlos Clients ab.

Vor einem Umstieg wäre das die Frage, die ich zuerst stellen würde: läuft das
Paket dort noch, und wenn ja, schlägt es an? Ein Blick auf
`/tmp/mt7915backlog.last-restart` und die Logzeilen des Pakets beantwortet das
in fünf Minuten.

## 2. Was unverändert bleibt

Geprüft, nicht vermutet:

| Punkt | Ergebnis |
| --- | --- |
| Netzwerk-Sektionen `client`, `wan`, `mesh_other` | unverändert → `br-client`, `br-wan`, `br-mesh_other` heißen weiter so |
| `local-node`, `local-port`, `bat0`, `primary0`, `mesh-vpn` | alle in beiden Versionen vorhanden |
| WLAN-ifnames `clientN`, `meshN`, `oweN` | Erzeugung in beiden Versionen `'client' .. suffix` mit `suffix = radio_name:match('^radio(%d+)$')` |
| `wifi`-Unterkommandos | `up down detect config status reload reconf` in 23.05 und 24.10 identisch |
| hostapd-Konfigdatei | `/var/run/hostapd-$phy.conf` → `hostapd-$phy$vif_phy_suffix.conf`; unser Glob `hostapd-*.conf` passt weiter, und der ssid-changer prüft ohnehin nur „mehr als null" |
| `batctl o`, `n`, `if`, `gwl -H` | in batctl 2024.3 alle vorhanden (COMMAND-Makros in `originators.c`, `neighbors.c`, `interface.c`, `gateways.c` geprüft); 2023.1 → 2024.3 |
| Autoupdater-Hooks `download.d`/`upgrade.d`/`abort.d` | Verzeichnisse und `gluon-autoupdater`-Dateiliste identisch |
| `/var/lock/autoupdater.lock` | unverändert, inklusive `fcntl(lock_fd, F_SETFD, 0)` vor `execl(sysupgrade)` — unser `autoupdater_busy()` trägt weiter |
| micrond, `/usr/lib/micron.d/` | unverändert |
| Upgrade-Konvention `001-reset-uci` / `998-commit` | unverändert, 59 → 61 Skripte |
| `gluon.util.readfile`, `.glob` | vorhanden |
| `gluon.wireless.device_uses_wlan` | vorhanden (`device_uses_11a` ist weg, das nutzen wir nicht) |
| `gluon.site`, `simple-uci`, `iwinfo`-Lua | vorhanden |
| `/lib/gluon/site.json` | unverändert |
| Firewall | Gluon 2025.1 wählt in `targets/generic` weiterhin `-nftables` und `-firewall4` ab und `+firewall` an — es bleibt bei **fw3/iptables**. Kein nftables-Umstieg. |

Besonders erwähnenswert: **die phy-Namen bleiben `phyN`.** OpenWrt 24.10 würde
wiphys umbenennen, Gluon schaltet das per
`patches/openwrt/0010-base-files-disable-wiphy-renaming.patch` ab
(`ucidef_add_wlan() { return 0; …`). Damit bleiben unsere Globs auf
`/sys/class/ieee80211/phy*` und `/sys/kernel/debug/ieee80211/phy*/mt76/rf_regval`
gültig.

Der Patch trägt allerdings seine eigene Ablauffrist im Kommentar:

> Only needed for openwrt-24.10 branch as later releases will be able to handle
> renaming early enough.

Für ein künftiges Gluon auf OpenWrt 25.x ist die phy-Benennung also wieder offen.
Das betrifft `check_wifi_firmware.sh` und `mt7915-backlog/backlog.sh`.

## 3. Nicht geprüft

Ehrlichkeitshalber, weil ohne 2025.1-Hardware nicht feststellbar:

* Ob `/sys/kernel/debug/ieee80211/phy*/mt76/rf_regval` unter mt76 in 24.10 noch
  existiert und sich gleich verhält.
* Die genaue JSON-Struktur von `wifi status`, die `check_hostapd.sh` mit
  `grep -A 6 "$radio"` durchsucht. (Auch das ist toter Code, siehe unten.)
* Das Ausgabeformat von `batctl n` / `batctl o` in 2024.3 — die Kommandos
  existieren, das Format hat sich zwischen batman-adv-Versionen aber schon
  geändert. `linkcheck.sh` zählt dort Zeilen, das ist robust gegen
  Spaltenverschiebungen, aber nicht gegen einen geänderten Kopfzeilen-Aufbau.

## 4. Was ohnehin schon tot ist

Beim Prüfen aufgefallen, unabhängig von 2025.1: der Check **`hostapd_pids`**
läuft heute nicht. Er wird so aufgerufen:

```sh
ps | grep hostapd | grep .pid | xargs -r -n 10 /lib/gluon/neanderfunk-hotfix/check_hostapd.sh
```

Auf einem Knoten mit 2023.2.6 gemessen: `ps | grep hostapd | grep -c "\.pid"`
liefert **0**. Seit OpenWrt 21.02 läuft ein einziger globaler hostapd
(`/usr/sbin/hostapd -s -g /var/run/hostapd/global`), ohne `-B` und ohne `-P`.
`check_hostapd.sh` wird also nie aufgerufen — und damit laufen auch die beiden
anderen Prüfungen darin (`wifi status` auf `up: false`/`pending: true`, und
`iwinfo … Channel: unknown`) nicht.

Ebenfalls tot: `rm -f /var/run/wifi-*.pid` in `restart_wifi()` — die Dateien gibt
es nicht (am Knoten geprüft).

Das ist keine 2025.1-Frage, sondern eine offene Baustelle für sich: entweder den
Check auf den globalen hostapd umbauen oder ihn ehrlich entfernen.

## 5. Was 2025.1 uns später an Arbeit abnimmt

Nur als Notiz, nichts davon ist jetzt zu tun. In 2025.1 ist deklariert, was wir
heute detektieren:

* `gluon.band_2g` / `gluon.band_5g` mit einer `role`-Liste (`client`, `mesh`,
  `private`) — neu über `022-wireless-roles`
* `wireless.<radioN>.band` steht explizit auf `2g` oder `5g`
* `gluon.wireless.outdoor` als Schalter, der 5-GHz-Mesh abschaltet
* `gluon.wireless.private_ssid` / `_key` / `_encryption` / `_mfp`
* `gluon_preserve` für eigene `wifi-iface`-Sektionen

Damit ließen sich unsere Band-Erkennungen (`radio_is_wifi6`, die 2,4-/5-GHz-Logik
in txpowerfix) später auf eine Abfrage statt auf Heuristik
umstellen. Solange das Bestehende funktioniert, ist das reine Kür.

## 6. Nebenbefund: Ethernet-Namen auf x86

Release Notes, interne Änderungen: zwischen 23.05 und 24.10 hat sich die
Ladereihenfolge von `igc` und `r8169` geändert, wodurch Ethernet-Interfaces die
Namen tauschen können. Gluon migriert das für den Zwei-Interface-Fall, „does not
cover setups with more than two Ethernet interfaces". Betrifft unseren
x86-Testknoten und ggf. Server-Hardware, nicht unsere Pakete — aber
`linkcheck`s Bridge-Port-Marker (`bridgeport.br-wan,eth1`) würden sich nach so
einem Tausch neu scharfschalten. Da die Marker in `/tmp` liegen, kostet das
nichts.

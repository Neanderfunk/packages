neanderfunk-domainhelper
========================

Hilfen rund um die Domain eines Knotens. Das Paket ist als Sammelstelle
gedacht, weitere Teile können dazukommen (automesh,
[docs/entwurf-automesh.md](../docs/entwurf-automesh.md)). Bisher gibt es
zwei:

**bridge: Domain-Brücken am LAN-Mesh erkennen und trennen**, in allen
Domains, siehe Abschnitt „bridge“ unten.

**island: Insel ohne Gateway wieder ans Netz bringen**, über einen
Kanal- oder Domainwechsel, siehe Abschnitt „island“ unten.

**locate: Lokator und Abschleppdienst für die Halteverbots-Defaultdomain.**
Scannt die WLANs in der Umgebung eines Knotens und meldet sie per POST an den
Locator (`locator.ffnef.de`). Hängt ein Knoten per LAN-Mesh an genau einer
anderen Domain, schaltet er selbst dorthin um. Konzept und Format:
[docs/konzept-hvb-ortung.md](../docs/konzept-hvb-ortung.md), Abschnitte 4.2
und 4.3.

Wann welcher Teil Domain oder Kanal wechselt (Ausgang, Attraktor, mit VPN
oder Insel): [docs/matrix-domainwechsel.md](../docs/matrix-domainwechsel.md).

**Stand 0.16 (25.11.2026):** Drei Scans je Interface, zusammengefasst (ein einzelner passiver Scan fand am WR1043ND v2 im Mittel nur 64 % der Mesh-Punkte); `scan.list` hat je BSSID eine Zeile. 0.15 (25.11.2026): Alle Scans passiv (`iw scan passive`), damit ath11k bei laufendem AP alle Kanäle sieht; der Scan mit kurz abgeschaltetem AP aus 0.14 entfällt. 0.14 (25.11.2026): `island` scannt auf 2.4 GHz mit kurz abgeschaltetem AP, wenn der Scan dort nur den eigenen Kanal sieht (ath11k, siehe unten); `domainhelper` als Kurzbefehl (0.13-r3). 0.13 (23.11.2026): Auch ältere Codes zählen als ihre Domain (#5), erhoben aus der Git-Historie von FirmwareConfigs, site-ffnef und ansible-ffnef: `<NN>_<name>` mit oder ohne Präfix nach der Nummer (also auch umbenannte wie `18_dusuk`, `13_dus`, `bgl-43_bglgl`, `48_rdv`), `ffnefd<NN>`/`FFNEFd<NN>` der Supernodes (damit besteht auch die Gegenprobe vor `follow` R2 gegen ältere Supernodes), die Namen vor den Domainnummern (`ffnef-vel`, `ffnef_lvr`, `ffbar`, `wip`, `ffgl-bgl`, `ffrrh` …) und die Tippfehler `nef-01_erk` (= `07_erk`) und `nef-mon_05`. Mehrdeutige Codes (`ffnef` ohne `domain_code`, `ffdus` (bis 2020 eine Domain, daraus 12_dusuk und 13_dusfl), Siegerland vor 2020, Kürten, Overath, Köln-rrh, Langenfeld der GL-Gruppe) bleiben unbekannt, ebenso Nachbar-Communities. Folge: Ein Nachbar mit alter Firmware einer anderen Domain am Kabel ist jetzt fremd und kann getrennt werden. 0.12: Nachbarn aus der Sackgasse 2021.1 (`site_code` wie `nef-21_dias_EOL`) zählen als Knoten ihrer Domain (`21_dias`), auch für `lan_switch`; bis 0.11 schaltete ein 25_hvb-Knoten neben einem Sackgassen-Knoten nicht um. 0.11: neu `follow` (#9): Knoten ohne VPN folgen nach 60 min der Domain, aus der ihr Netz über das Kabel kommt, WLAN-Kanäle bleiben (braucht neanderfunk-preserve-wifichannel 3). `bridge` trennt mit DSA nur den Port, ohne Bridge (swconfig) später und nicht gegen eigene Nachbarn am LAN, und verbindet wieder, wenn der getrennte Nachbar in die eigene Domain gewechselt ist. 0.10: `island` in einer Domain mit Ortung (`25_hvb`) nach 5 min statt 60/600 min, ohne Versatz. Der Standardkanal der neuen Domain setzt `preserve_channels_<band>=0` (braucht neanderfunk-banner 5). 0.9: `bridge` trennt nicht gegen Nachbarn aus einer Domain mit Ortung (`25_hvb`), die schalten per `lan_switch` selbst um. 0.8: Fall b von `island` verwirft vor dem Domainwechsel alle Laufzeit-Deltas (sonst schriebe das pauschale `uci commit` in `001-reset-uci` etwa die Offline-SSID in den Flash). 0.7: neu `island`. 0.6: `bridge` trennt bis zum
Neustart, Takt 91 s. 0.5: neu `bridge`. Seit 0.4 ganz in Shell:
`/usr/sbin/neanderfunk-domainhelper` verteilt nur noch auf
`/lib/gluon/neanderfunk-domainhelper/cmd_<unterbefehl>.sh`, gemeinsame
Funktionen stehen in `lib.sh`.

**Stand 0.4 (21.11.2026):** ganz in Shell, kein Lua mehr. Meldeformat und
Verhalten wie 0.3, das noch ein Lua-Skript war. Bis 0.2 hieß das Paket
`neanderfunk-hvblocator`, davor als Prototyp `neanderfunk-locate`.

Warum Shell: Teile des Pakets sollen später im Minutentakt laufen
(automesh, [docs/entwurf-automesh.md](../docs/entwurf-automesh.md)). Ein
Lua-Lauf zieht `liblua`, `jsonc`, `uci` und die gluon-Module vom Flash in
den Speicher; auf 64-MB-Geräten werden solche selten genutzten Seiten
unter Speicherdruck verdrängt und immer wieder neu gelesen. Die
Shell-Fassung nutzt busybox, `jsonfilter` und `jshn`, die ohnehin ständig
gebraucht werden. Gemessen an einem M60 (je Lauf, Summe aller Prozesse):
eigener Speicher (`RssAnon`) etwa gleich, 0.8 bis 1.3 MB mit Lua, 0.75 bis
0.9 MB mit Shell; der Unterschied liegt in den Datei-Seiten. Flash und RAM
heute: Abschnitt [Platzbedarf](#platzbedarf).

Die gemeinsamen Funktionen (LAN-Mesh-Nachbarn und ihre Domain,
Umschaltziel) stehen in `/lib/gluon/neanderfunk-domainhelper/lib.sh`, zum
Sourcen für weitere Teile.

**Falle busybox `sort`:** Die busybox der Knoten kennt bei `sort` nur
`-n -r -u -s -z`. `-t`, `-k` und `-o` werden ohne Fehlermeldung ignoriert.
Deshalb steht der Sortierschlüssel vorn in der Zeile. Weitere Fallen:
[docs/gluon-laufzeit-fallen.md](../docs/gluon-laufzeit-fallen.md).

Einschalten (locate)
--------------------

Nur über die Domain-Datei, nicht über die site.conf (`check_site.lua`
erlaubt den Schlüssel nur `in_domain`):

```lua
neanderfunk_domainhelper = {
  locator = {
    urls = {
      'https://locator.ffnef.de/hvb/locate',
      'http://locator.ffnef.de/hvb/locate',
    },
  },
},
```

Bei uns steht das nur in `25_hvb`. In jeder anderen Domain fehlt der
Schlüssel, dann tut locate nichts. Nach einer Verschiebung ist die Ortung
damit von selbst aus. Im Code steht keine Domain.

Wann locate läuft
-----------------

- **Nach dem Start:** `/etc/init.d/neanderfunk-domainhelper` startet
  `/lib/gluon/neanderfunk-domainhelper/locate.sh boot` im Hintergrund. Es
  wartet 60 s, dann bis batman einen Nachbarn hat, höchstens bis 600 s
  Uptime, und meldet dann einmal. Die LAN-Mesh-Prüfung braucht kein
  Internet.
- **Täglich:** micron.d ruft `locate.sh cron` stündlich zur Minute 9 auf.
  Es meldet erst, wenn die letzte Meldung 24 h her ist (nach einem
  Fehlschlag 6 h). Gemessen wird in Uptime, Stand in
  `/tmp/neanderfunk-domainhelper-locate.stamp`. Gemeldet wird je Knoten
  fest 0 bis 49 min später (letztes Byte der primären MAC). Ohne Schlüssel
  endet `locate.sh` nach einem `jsonfilter`.
- Nicht im Setup-Mode, nie zwei Läufe gleichzeitig (Sperre in `/tmp`).

Aufruf
------

Kurz geht es auch mit `domainhelper` statt `neanderfunk-domainhelper`
(Symlink in `/usr/sbin`, seit 0.13-r3); `help` auf dem Knoten listet die
Trockenläufe mit `-n`.

```sh
neanderfunk-domainhelper locate        # scannen und melden
neanderfunk-domainhelper locate -n     # nur scannen, JSON ausgeben, nichts senden
neanderfunk-domainhelper locate -u URL # an diese URL melden, auch ohne
                                       # Schlüssel in der Domain (schaltet nie um)
neanderfunk-domainhelper locate -n -a 25_hvb  # Trockenlauf, als stünde der
                                              # Knoten mit Ortung in 25_hvb
```

Ergebnis steht im Syslog (`logread | grep neanderfunk-domainhelper`).

Was locate tut
--------------

- **Scan:** je Band ein Interface. Ein Mesh-Punkt kommt zuerst, dann eine
  Station, zuletzt ein AP; nur beim AP wird mit `ap-force` gescannt. Auf
  MR90X und COVR-X1860 (26111912bro) ging der Scan auf `mesh0`/`mesh1` ohne
  `ap-force` und dauerte etwa 5 s für beide Bänder.
- **Filter:** Eigene Interfaces fallen weg, SSIDs auf `_nomap` auch. Eine
  BSSID wird nur einmal gemeldet, mit dem stärksten Pegel. Gemeldet werden
  höchstens 50 Netze, die stärksten zuerst.
- **Mesh-ID:** Mesh-Punkte (802.11s) melden ihre Mesh-ID im Feld `mesh_id`.
  Daran erkennt der Locator die Domain.
- **Exit-IPv4:** Das Skript fragt `ipv4.icanhazip.com` bzw.
  `checkip.amazonaws.com`, wie `nodestatus` es tut. Ein Knoten ohne
  IPv4-Uplink (reiner Mesh-Knoten) lässt das Feld weg.
- **Uplink:** ob der Knoten eigenes VPN hat (batman-Nachbar auf
  `mesh-vpn`), über welches Interface sein Gateway läuft (`batctl gwl`) und
  wie viele batman-Nachbarn er je Art hat. Ein Knoten ohne eigenes VPN wird
  nicht verschoben (Konzept 4.4, „Wer darf gehen?“).
- **LAN-Mesh-Nachbarn:** Je batman-Interface außer `mesh-vpn` und `meshN`
  fragt das Skript die direkten Nachbarn per respondd
  (`gluon-neighbour-info ... -r nodeinfo`) und meldet sie mit Domain im Feld
  `lan_mesh`. Die Domain kommt aus `system.domain_code`, bei älteren Images
  aus dem `site_code` hinter dem Bindestrich, ältere Codes über ihre Domainnummer oder ihren Namen (siehe Stand 0.13). Antworten kommen nicht immer
  sofort, deshalb fragt das Skript wiederholt, bis jeder batman-Nachbar am
  LAN geantwortet hat, höchstens 60 s. Wer schweigt, steht nur mit MAC da.
  An den beiden M60-Testknoten kam die Antwort im ersten Durchgang; ein
  Lauf mit Scan dauerte etwa 10 s.
- **Umschalten:** Ist die Ortung an und hängen am Kabel Nachbarn
  genau einer anderen Domain, die im Image steht, meldet das Skript
  `lan_switch` und ruft danach `gluon-switch-domain` auf (Neustart), auch wenn
  die Meldung nicht ankam. Mehrere fremde Domains oder eine, die das Image
  nicht kennt: kein Umschalten. Mit `-n` schaltet das Skript nie um; `-a`
  gibt es nur zusammen mit `-n`.
- **Koordinaten:** aus `gluon-node-info`, falls eingetragen, auch wenn sie
  nicht veröffentlicht sind.
- **Senden:** zuerst `https`, wenn `libustream-ssl` da ist, sonst `http`.
  User-Agent ist `neanderfunk-domainhelper/<version>`. Der Locator antwortet mit
  200. Das Skript nimmt trotzdem jede 2xx-Antwort an: `uclient-fetch` zählt
  nur 200 als Erfolg und meldet etwa 202 als „HTTP error 202“ mit rc 8. Den
  Inhalt der Antwort wertet das Skript nicht aus.

bridge
------

Wir fahren `mesh.vxlan = false`. Steckt am LAN-Mesh ein Knoten einer
anderen Domain, verschmelzen beide batman-Wolken sofort (Domain-Brücke).
`neanderfunk-domainhelper bridge` läuft alle 91 s und trennt solche
Brücken, wo es niemanden abschneidet. Fall A aus dem automesh-Entwurf.
Die Schleife `bridge-loop.sh` ist eine procd-Instanz von
`/etc/init.d/neanderfunk-domainhelper` (respawn). 91 s statt jeder vollen
Minute aus micron.d, damit die Läufe nicht immer auf denselben
Sekundenpunkt fallen und zwei Knoten an derselben Brücke nicht im
Gleichschritt prüfen. Die Schleife belegt dauerhaft etwa 50 bis 60 KB
eigenen Speicher.

- **Erkennen:** LAN-Mesh-Nachbarn (alle batman-Interfaces außer
  `mesh-vpn` und `meshN`) per respondd nach ihrer Domain fragen, wie
  `locate`. Neue Nachbarn sofort, bekannte alle 15 min. Ohne
  LAN-Mesh-Nachbarn endet der Lauf nach `batctl n`.
- **Fremd** nur auf positiven Beleg: Der Nachbar nennt eine Domain, die in
  dieser Firmware steht und nicht die eigene ist (`_EOL` zählt nicht).
  Unbekannte Codes, etwa von Nachbar-Communities, lösen nichts aus.
- **Melden:** Syslog bei jedem Zustandswechsel, eine Zeile im Login-Banner
  (`nodestatus` liest `/tmp/neanderfunk-domainhelper.banner`), Zustand in
  `/tmp/neanderfunk-domainhelper.bridge/state`. Ein Feld in respondd fehlt
  noch.
- **Trennen** im nächsten Durchgang (91 s später) nach frischer Nachfrage,
  nur wenn alles zutrifft:
  - Trennen ist nicht abgeschaltet (`neanderfunk-domainhelper.bridge.cut`);
  - der Knoten hat eigenes VPN, behält also seinen Uplink;
  - die Gegenseite hat einen eigenen Uplink: Ein fremder Nachbar an dieser
    Schnittstelle erreicht sein Gateway direkt (`gateway_nexthop` gleich
    `gateway` in seiner statistics, das geht nur über einen eigenen
    Tunnel), oder in `batctl gwl` steht ein Gateway seiner Domain
    (Originator `02:ca:ff:ee:<NN>:..`);
  - ohne Bridge (swconfig, etwa Archer C7 oder TL-WR1043ND: alle LAN-Ports
    sind ein Gerät, der Switch leitet in Hardware weiter, keine
    Port-Isolation): erst 2 min später, damit eine Gegenseite mit DSA
    zuerst ihren Port trennt, und nur, wenn am LAN kein Nachbar der eigenen
    Domain hängt. Sonst nur Meldung, mit dem Switch-Port aus `swconfig ...
    get arl_table`, wo der Switch ihn kennt: Trennen kappte nur unsere
    eigenen Links, die fremden Knoten blieben über unseren Switch mit den
    eigenen verbunden.
  Sonst bleibt die Brücke stehen und wird gemeldet. Ohne eigenes VPN
  trennt ein Knoten nie, dafür wechselt er per `follow`.
- **Wie getrennt wird:** nur zur Laufzeit, kein uci commit.
  - Ist der Hardif eine Bridge (`br-mesh_other`, `br-wan` bei
    Mesh-on-WAN; mit DSA ist jeder Port ein eigenes Gerät): ebtables
    verwirft batman-Frames (0x4305) an genau dem Port, hinter dem der
    fremde Nachbar steht (Port aus der Weiterleitungstabelle
    `/sys/class/net/<bridge>/brforward`), für uns (`INPUT -i`, `OUTPUT -o`)
    und für die Weiterleitung zu den anderen Ports (`FORWARD -i`/`-o`).
    Nachbarn der eigenen Domain an anderen Ports bleiben dran, und die
    Brücke durch uns hindurch ist weg. Ist der Port nicht zu finden, wie
    bis 0.10 die ganze Bridge für uns (`--logical-in`/`--logical-out`).
  - Sonst (ein einzelnes Gerät, etwa `eth1.1`): `ifdown` nur auf der
    batman-Schnittstelle (`mesh_other_mesh`, proto `gluon_mesh`). Das Gerät
    behält seine link-local-Adresse, der getrennte Nachbar lässt sich
    weiter per respondd fragen; unser eigener respondd hört dort dann
    nicht mehr. Wieder verbunden wird mit `ifup mesh_other`, das die
    Schnittstelle neu anlegt (am TL-WR1043ND v2 geprüft, 22.11.).
  - Jeder Lauf prüft, ob die Trennung noch greift (ein Neuladen der
    Firewall löscht die Regeln), und setzt sie neu.
- **Wieder verbinden** nur, wenn der getrennte Nachbar inzwischen selbst in
  unserer Domain steht (per `follow` herübergewechselt, adorfer 22.11.);
  gefragt wird alle 270 s per respondd über das getrennte Kabel. Sonst
  **getrennt bis zum Neustart** (adorfer 21.11.): keine Freigabe
  zwischendurch, die Domains wachsen also nicht alle paar Stunden wieder
  zusammen. Fällt danach ein VPN weg und steht die Wolke ohne Gateway da,
  startet ein Wächter (linkcheck `no_gateway`) den Knoten neu, dann
  beginnt die Prüfung von vorn. Nach jedem Neustart hängen die Domains
  etwa 2 bis 3 min zusammen, bis wieder getrennt ist.
- **Beide Seiten trennen**, wenn beide die Bedingungen erfüllen, ohne
  Absprache: Die Regeln sperren nur batman-Frames, eine Seite allein
  reicht schon, beide schaden nicht. Dann haben beide VPN, und keiner
  wechselt. Läuft auf
  der Gegenseite eine Firmware ohne `bridge`, trennt eben nur unsere.
- **In einer Domain mit Ortung** (`25_hvb`) trennt `bridge` nicht, sondern
  startet einmal `locate`, das meldet und selbst in die Domain des
  Nachbarn umschaltet. Umgekehrt zählt ein Nachbar aus einer Domain mit
  Ortung nicht als fremd: Er kommt per `lan_switch` von selbst herüber,
  eine Trennung hielte ihn danach bis zum Neustart ab.

Abschalten (nur das Trennen, gemeldet wird weiter):

```sh
uci set neanderfunk-domainhelper.bridge.cut=0 ; uci commit neanderfunk-domainhelper
```

Nur zum Testen: `uci set neanderfunk-domainhelper.bridge.test_domain=<d>`
ohne commit lässt `bridge` so tun, als stünde der Knoten in `<d>`. Damit
lässt sich das Trennen gegen Nachbarn der eigenen Domain prüfen, ohne eine
fremde Domain anzuschließen. `neanderfunk-domainhelper bridge -n` zeigt,
was passieren würde, und ändert nichts.

follow
------

Knoten **ohne eigenes VPN** folgen der Domain, aus der ihr Netz kommt
(#9). Ohne VXLAN nutzt ein solcher Knoten am Kabel einer anderen Domain
deren Gateways und Präfix und bliebe sonst dauerhaft im Mischbetrieb.
Läuft alle 91 s nach `bridge`, außerhalb von 25_hvb (dort schaltet
`locate` per `lan_switch`). Zwei Regeln, beide erst nach **60 min** am
Stück:

- **R1 Kabel:** Ein Nachbar an einem Kabel steht in einer fremden Domain
  D und hat dort ein eigenes VPN (in seiner statistics ist das Gateway sein
  eigener Nexthop), und ein Gateway der eigenen Domain kommt höchstens
  über WLAN. Dann nach D, auch wenn über WLAN ein eigenes Gateway da ist:
  LAN-Mesh schlägt WLAN-Mesh (adorfer 22.11.). Abgefragt wird per respondd
  an jedem Kabel direkt, nicht über `batctl n`: Der Nachbar mit VPN trennt
  per `bridge` sofort, die Trennung verwirft aber nur batman, IPv6 geht
  durch. Direkt vor dem Wechsel wird noch einmal frisch gefragt, damit der
  Knoten sich nicht selbst auf eine Insel schiebt. Nach dem Wechsel
  verbindet die Gegenseite wieder (`bridge`).
- **R2 nur fremde Gateways:** In `batctl gwl` stehen nur Gateways einer
  fremden Domain D, erkannt am Originator `02:ca:ff:ee:<NN>:..`. Das
  betrifft Knoten, die nur per WLAN hinter einem R1-Knoten hängen.

Wechsel: alle Laufzeit-Deltas verwerfen, Marke
`/lib/gluon/core/sysconfig/neanderfunk_preserve_wifichannel_keep`, dann
`gluon-switch-domain D` mit Neustart. Die **WLAN-Kanäle bleiben**, soweit
`preserve_channels` oder `preserve_channels_<band>` steht
(neanderfunk-preserve-wifichannel 3): Die WLAN-Nachbarn wechseln mit und
finden sich auf denselben Kanälen wieder.

Nichts tut `follow` mit eigenem VPN, wenn ein Gateway der eigenen Domain
über ein Kabel kommt (LAN gegen LAN), in eine Domain mit Ortung oder
außerhalb dieser Firmware, und wenn mehrere fremde Domains in Frage
kommen. **Beide Seiten ohne VPN, beide sehen ein Gateway der eigenen
Domain:** Alle sind versorgt, das wird nur gemeldet (Syslog).

**Nachfolgen über `island`:** Der Zeitpunkt, seit dem die Lage gilt, bleibt
stehen, wenn zwischendurch gar kein Gateway zu sehen ist, etwa weil der
Kabel-Knoten vor uns gewechselt hat und neu startet. Ist er älter als
60 min, wechselt `island` Fall b ohne Wartezeit und ohne 6-h-Sperre in
genau diese Domain. Zurückgesetzt wird er nur durch ein Gateway der
eigenen Domain, eigenes VPN oder eine andere Zieldomain.

Banner: `/tmp/neanderfunk-domainhelper.banner.follow`, Zustand in
`/tmp/neanderfunk-domainhelper.follow/state`. Abschalten:
`uci set neanderfunk-domainhelper.follow.enabled=0 ; uci commit
neanderfunk-domainhelper`. `neanderfunk-domainhelper follow -n` zeigt
Gateways, fremde Nachbarn am Kabel und was passieren würde.

island
------

Steht längere Zeit kein Gateway in `batctl gwl`, sucht der Knoten per
Scan ein WLAN-Mesh einer Domain dieser Firmware (Mesh-IDs aus
`/lib/gluon/domains/*.json`). Läuft im selben 91-s-Takt wie `bridge`,
gescannt wird höchstens alle 5 min.

- **Passiver Scan:** Alle Scans des Domainhelpers sind passiv
  (`iw dev <if> scan passive`). ath11k verlässt bei einem aktiven Scan
  seinen Kanal nicht, solange auf dem Radio ein AP läuft: gemessen am
  Mercusys MR80X v2 (IPQ5018, Firmware `WLAN.HK.2.7.0.1-01744`) auf 2.4 GHz
  über `mesh0` wie über `client0`, auch mit `scan freq …` und `ap-force`
  nur Netze des eigenen Kanals; auch auf einem Xiaomi AX3600 (ipq807x)
  nachgestellt. Passiv sieht derselbe Knoten mit laufendem AP alle Kanäle,
  samt Mesh-Punkten auf anderen Kanälen (25.11.2026). Mesh-Punkte und APs
  senden Beacons, passiv fehlt also nichts, was hier gesucht wird.
  `lowpri` (wie im linkcheck) lehnt ath11k ab (-95), deshalb ohne; MT7986
  meldet zeitweise -105, dann einmal nach 3 s wiederholen. Ein AP-Interface
  bekommt notfalls `ap-force passive`; nur wenn passiv gar nichts kommt,
  zuletzt aktiv. `offlinescan` und `channel` (neanderfunk-banner) scannen
  über iwinfo, das ohnehin passiv scannt.
- **Drei Scans je Interface** (`DH_SCAN_ROUNDS`), zusammengefasst, je BSSID
  der stärkste Pegel. Ein einzelner passiver Scan verpasst viel; gemessen am
  25.11.2026 im 21_dias-Labor, je 5 Scans auf 2.4 GHz, Anteil der Mesh-Punkte
  je Scan im Mittel / im schlechtesten Fall:

  | Gerät (Chip) | 1 Scan | 2 Scans | 3 Scans |
  | --- | --- | --- | --- |
  | WR1043ND v2 (ath9k) | 64 / 44 % | 83 / 67 % | 96 / 89 % |
  | M60 (mt7981) | 83 / 67 % | 92 / 67 % | 100 % |
  | MR80X v2 (ath11k) | 98 / 88 % | 100 % | 100 % |
  | Xiaomi 4A Gigabit (mt76) | 100 % | 100 % | 100 % |

  Kosten: `island -n` dauert damit am WR1043ND v2 etwa 14 s, am MR80X v2
  (zwei Bänder) etwa 40 s. `offlinescan` und `channel` machen es genauso
  (`neanderfunk.wifiscan` im Banner-Paket). 0.14 schaltete für den 2.4-GHz-Scan
  von `island` noch kurz die APs ab; das ist mit 0.15 entfallen, `-k` wird
  still angenommen.

- **a) Mesh der eigenen Domain auf einem anderen Kanal**, ab 60 min ohne
  Gateway: Das Radio dieses Bands geht auf diesen Kanal. `channel = auto`
  zählt als anderer Kanal (auf auto kommt das Mesh nicht hoch).
- **b) Mesh einer anderen Domain**, ab 600 min: `gluon-switch-domain
  --no-reboot`, dann der Kanal, dann Neustart. Der Kanal kommt nach dem
  Domainwechsel, weil neanderfunk-preserve-wifichannel im
  `gluon-reconfigure` des Wechsels einmal die Kanäle der neuen Domain
  einträgt.
- **Versatz:** zu beiden Zeiten kommen je Knoten 0 bis 15 min aus der MAC.
  Fällt eine Wolke gemeinsam aus, wechselt einer zuerst; die anderen sehen
  danach über das LAN-Mesh wieder ein Gateway.
- **In 25_hvb (Domain mit Ortung) so bald wie möglich:** Fall a und b nach
  5 min ohne Gateway (Zeit für VPN und Gateway-Wahl nach dem Boot), ohne
  Versatz, der nächste Wechsel frühestens nach 15 min. Außerhalb von
  25_hvb bleibt es bei den langen Zeiten: keine hastigen Wechsel.
- **Kanal dauerhaft:** über den Befehl `channel` (neanderfunk-banner), der
  ohne das uci-Delta speichert und nur das Radio neu startet
  (`wifi up <radio>`). Ist der neue Kanal der Standardkanal der (neuen)
  Domain, mit `--no-keep` (`preserve_channels_<band>=0`, das Band folgt
  wieder der Domain), sonst mit `preserve_channels_<band>=1`, egal was
  vorher stand, damit ein Update ihn nicht zurücksetzt. Ein Wechsel hält auch über den Weekly
  Reboot; aufräumen, wenn der eigentliche Uplink wieder steht, muss man
  von Hand.
- **Nicht gewechselt wird**
  - zu einem Mesh-Punkt, dessen Knoten selbst offline ist: Ein AP auf
    derselben Frequenz mit verwandter BSSID sendet die Offline-SSID
    (`ssid_changer.prefix`, bei uns `FF_Offline_`). Verwandt: bis auf die
    unteren 3 Bit des letzten Bytes oder die Bits 0x0e des ersten Bytes
    gleich (beides kommt vor, je nach Treiber). Fällt das Internet für
    alle aus, bleibt so jeder, wo er ist;
  - auf einem Band ohne Mesh-Rolle (`gluon.band_<band>.role`), auf 5 GHz
    im Outdoor-Modus, in eine Domain mit Ortung (`25_hvb`), zu
    Mesh-Punkten unter -80 dBm.
  Eigene Domain geht vor fremder, dann das stärkste Signal.
- **Nach einem Wechsel** frühestens nach 6 h der nächste (in 25_hvb 15 min).
- Ein aktives LAN-Mesh oder weitere Knoten in der Wolke verhindern den
  Wechsel nicht; maßgeblich ist nur: kein Gateway.
- **Zusammen mit linkcheck:** Fällt der Uplink zur Laufzeit weg, startet
  linkcheck den Knoten nach etwa 20 bis 30 min einmal neu. Danach hat er
  seit dem Boot weder Nachbarn verloren noch ein Gateway gesehen, linkcheck
  hält still, und die Wartezeit von `island` zählt ab dem Boot.

Abschalten: `uci set neanderfunk-domainhelper.island.enabled=0 ; uci commit
neanderfunk-domainhelper`. `neanderfunk-domainhelper island -n` übergeht
die Wartezeiten, scannt und zeigt je Mesh-Punkt, warum er Kandidat ist
oder nicht.

Getestet
--------

20.11.2026 als neanderfunk-hvblocator 0.2 auf einer Gluon-x86-VM
(26111816bro, Multi-Key) in `25_hvb`:
ohne Schlüssel kein Lauf und keine Ausgabe; mit Schlüssel in der
Domain-Datei liest `gluon.site` die URLs, der Startlauf meldete nach dem
ersten batman-Nachbarn (VPN) an `https://locator.ffnef.de/hvb/locate`, ein
`run.sh cron` direkt danach tat nichts. Den Paketbau selbst prüft erst der
Testbau. 0.3 benennt nur um (Paket, Befehl `locate`, Schlüssel
`neanderfunk_domainhelper.locator`), ohne neuen Lauf auf einem Knoten.

21.11.2026 mit 0.3 in der Testfirmware 26112017sta (Multi, mit und ohne
Key), zusammen mit nodeplacer 0.1-r2 (D-045):

- **Zwei Gluon-x86-VMs in `25_hvb`** (Key-Image; Nonkey-Image mit dem
  Wizard per uci nachgespielt), Mesh-VPN an, kein WLAN: Der Startlauf
  meldete jeweils nach etwa 75 s Laufzeit (`gemeldet: 0 Netze an
  https://locator.ffnef.de/hvb/locate`). Mit einem Handeintrag im
  HVB-Manifest zogen beide per nodeplacer nach `21_dias` um. Dort läuft
  `locate` nicht mehr (keine URLs in der Domain).
- **D-Link M60 im Testfeld, am Kabel an zwei Knoten in `21_dias`:** nach
  `gluon-switch-domain 25_hvb` meldete der Startlauf bei 85 s Laufzeit
  50 Netze mit `lan_switch` und schaltete selbst nach `21_dias` zurück,
  ohne Mapserver.
- **Derselbe M60 ohne LAN-Mesh** (LAN-Ports zur Laufzeit abgeschaltet,
  `batctl if del` allein reicht nicht, netifd hängt die Bridge wieder
  an): Meldung mit 50 Netzen, ohne `lan_switch`. Der Locator ermittelte
  `21_dias` aus den Mesh-Punkten der Nachbarn (E11) und nahm den Knoten
  von selbst ins Manifest auf. Der planmäßige nodeplacer-Lauf (die Minute
  ist je Knoten verschieden) schaltete ihn nach `21_dias`, etwa 50 min
  nach dem Wechsel nach `25_hvb`: etwa 15 min, bis die Karte ihn in
  `25_hvb` führte und der Manifest-Lauf ihn aufnahm, dann noch 37 min bis
  zum stündlichen nodeplacer-Lauf.

21.11.2026, 0.4 (Shell) live eingespielt, ohne Build:

- **M60 (mediatek-filogic), 26112017sta:** Trockenlauf `-n -a 25_hvb`
  neben 0.3: gleiche Felder und Werte (Uplink, Mesh-MACs, Nachbarzahlen,
  LAN-Nachbarn mit Domain, `lan_switch`, Exit-IP), je 50 Netze, davon
  13 Mesh-Punkte `dias-mesh` und 2 `hvb-mesh` in beiden, 47 von 50 BSSIDs
  gleich (Rest Schwankung zwischen zwei Scans). Dann mit 0.4 an
  `/usr/sbin` nach `25_hvb` gesetzt: Startlauf meldete 50 Netze an
  `https://locator.ffnef.de/hvb/locate`, erkannte die LAN-Nachbarn und
  schaltete nach `21_dias` zurück, wie 0.3. Der Locator nahm die Meldung
  an (User-Agent `neanderfunk-domainhelper/0.4`); Schlüssel und Typen
  aller Felder gleich wie bei 0.3, E11 ergab wie vorher `21_dias`.
- **TL-WR1043ND v2 (ath79, 64 MB), 26111912bro:** Trockenlauf aus `/tmp`:
  rc 0 nach 9 s, 43 Netze nach Pegel, kein VPN, Gateway über `mesh0`,
  LAN-Nachbar mit Domain erkannt.

21.11.2026, 0.5 (`bridge`) live auf dem M60 und dem TL-WR1043ND v2, ohne
Build. Eine fremde Domain wurde mit `test_domain=13_dusfl` vorgetäuscht,
die Nachbarn standen wirklich in `21_dias`:

- **M60 (eigenes VPN, Bridge `br-mesh_other`, Nachbarn ERX mit VPN und
  1043v2 ohne):** Brücke um 05:24:05 erkannt und gemeldet (Syslog, Banner),
  um 05:26:11 getrennt (ebtables, zwei Regeln). Von Hand gelöschte Regeln
  setzte der nächste Lauf neu. Nach 10 min frei, gleich wieder erkannt,
  nach der Frist erneut getrennt, jetzt mit 20 min. Vorher von Hand
  geprüft: Mit den Regeln fallen die LAN-Nachbarn nach gut 200 s aus
  `batctl n`, ohne Regeln sind sie nach 20 s zurück.
- **TL-WR1043ND v2 (kein eigenes VPN, `eth1.1` ohne Bridge):** Trockenlauf
  meldet die Brücke und lässt sie stehen („kein eigenes VPN“); das Ziel
  wäre `ifdown mesh_other`.
- Nicht getestet: eine echte Brücke zwischen zwei Domains und der Fall
  „Gegenseite ohne eigenen Uplink“ mit eigenem VPN.

21.11.2026, 0.6 auf dem M60, gekürzt wie aus dem Bau
(`strip-shell-comments`): Schleife als procd-Instanz, Brücke um 06:38:09
erkannt, um 06:39:51 getrennt (ein Durchgang später, nicht auf der vollen
Minute), keine Freigabe mehr.

21.11.2026, 0.7 (`island`) live auf dem M60, Fall a. Als Insel hergerichtet:
Mesh-VPN mit `ifdown`, LAN-Mesh per ebtables getrennt, Kanäle 1 und 36
statt 9 und 44, alle linkcheck-Prüfungen als uci-Delta aus. Die Nachbarn
in `21_dias` blieben auf 9 und 44.

- Gateway ab 09:03 weg. Um 10:07:31, also nach 63 min (60 min plus 3 min
  Versatz aus der MAC), meldete der Knoten: „Insel: Mesh der eigenen
  Domain 21_dias auf 2g Kanal 9 (-14 dBm, …), stelle Kanal von 1 auf 9
  (Standardkanal, ohne Festschreiben)“. Eine Minute später war das
  Gateway wieder da. 5 GHz blieb auf 36: Ein Band reicht.
- Ein erster Lauf ohne abgeschaltetes linkcheck endete nach 13 min mit
  einem Neustart („lost neighbours 4th: batinterfaces.mesh-vpn“). Auf
  einer echten Insel ist das der erwartete eine Neustart: linkcheck greift
  nur, wenn seit dem Boot Nachbarn oder ein Gateway gesehen wurden. Danach
  läuft die Wartezeit ab dem Boot ungestört.
- Fall b nur als Trockenlauf.

21.11.2026, 0.8/0.9 live, Fall b und die LAN-Fälle der Matrix:

- **Fall b auf einem WS-AP3825i** (26111912bro, 0.8 eingespielt), in
  `21_dias`, in Reichweite von `wlf-mesh` (10_wlf, Kanal 9, -17 dBm).
  Wartezeiten nur auf dem Gerät auf 5/10 min gekürzt, VPN per `ifdown` aus,
  linkcheck als uci-Delta aus. VPN um 19:14 aus, Neustart nach 11 min, um
  19:29 in `10_wlf` mit je 2 Mesh-Nachbarn auf beiden Bändern und VPN.
  Kanäle 9/44 sind dort Standard, also nicht festgeschrieben. Im Flash
  keine Offline-SSID und kein abgeschaltetes linkcheck: Das Verwerfen der
  Deltas vor dem Wechsel greift. Der Mitschnitt des Syslogs blieb leer
  (busybox-`grep` ohne `--line-buffered`), belegt sind Zeiten und Endzustand.
- **A1 ohne VPN auf einem NWA50AX Pro** (26112107bro, 0.9 eingespielt) am
  LAN-Mesh von 18_nefuk: nach `gluon-switch-domain 25_hvb` über das
  verschmolzene Mesh erreichbar, bei 90 s Laufzeit per `lan_switch` zurück
  nach 18_nefuk.
- **B1 ohne VPN, derselbe Knoten in `21_dias`** am Kabel von 18_nefuk:
  `bridge` meldet die Brücke und lässt sie stehen; der Knoten nutzt das
  Gateway und das öffentliche Präfix von 18_nefuk (Mischbetrieb).
- Beim Domainwechsel nimmt der Knoten die Kanäle der neuen Domain, auch
  mit `preserve_channels=1` (8/auto wurde 9/48).
- Nicht getestet: B1h (Gegenseite ohne `bridge`), eine echte Brücke
  zwischen zwei VPN-Knoten verschiedener Domains.

22.11.2026, 0.11 live:

- **`follow` R1 auf dem NWA50AX Pro** (26112107bro, 0.11 und
  neanderfunk-preserve-wifichannel 3 eingespielt): per
  `gluon-switch-domain 21_dias` aus 18_nefuk geholt, dort Kanäle 8/auto per
  `channel` gesetzt (Band-Schlüssel 1). Kein eigenes VPN, am Kabel die
  FRITZ!Box 4040 und der Cudy WR3000E mit VPN in 18_nefuk. `follow` meldet
  R1 bei 59 s Laufzeit; Wartezeit nur auf dem Gerät auf 5 min gekürzt. Nach
  dem Wechsel in 18_nefuk, Gateway da, **Kanäle 8/auto geblieben**, die
  Marke in sysconfig verbraucht. Vorher in 21_dias kurz Mischbetrieb: per
  SSH über das Präfix von 18_nefuk zeitweise nicht erreichbar.
- **`bridge` je Port auf dem M60** (DSA, `br-mesh_other` mit lan1 bis
  lan4, eigenes VPN), fremde Domain mit `test_domain=10_wlf` vorgetäuscht:
  Port `lan3` aus `brctl showmacs`, vier Regeln (`INPUT -i`, `OUTPUT -o`,
  `FORWARD -i`/`-o`), der Nachbar fiel aus `batctl n`, respondd über das
  getrennte Kabel antwortete weiter. Nach `uci revert` von `test_domain`
  stand der Nachbar in der eigenen Domain: Trennung nach 4 min 36 s
  aufgehoben, Nachbar wieder in `batctl n`.
- **Ohne Bridge auf dem TL-WR1043ND v2** (swconfig, AR8327) nur von Hand:
  `ifdown mesh_other_mesh` nimmt batman vom LAN, `eth1.1` behält die
  link-local-Adresse, respondd-Abfrage über das Kabel geht, `ifup
  mesh_other` legt die Schnittstelle neu an; `swconfig dev switch0 get
  arl_table` nennt den Port des Nachbarn.
- Nicht getestet: B1w (eigenes Gateway über WLAN, R1 trotzdem), R2 und das
  Nachfolgen über `island`, Trennen und Aufheben ohne Bridge im echten
  Lauf, die Regel „nicht gegen eigene Nachbarn am LAN“.

Platzbedarf
-----------

Schätzung (22.11.2026, Bau 26112210bro). Methode und alle Pakete im
Vergleich: [docs/platzbedarf.md](../docs/platzbedarf.md).

- **Flash:** etwa 13 KB im squashfs (xz).
- **RAM dauerhaft:** etwa 0,1 MB: die Schleife `bridge-loop.sh` (40 bis 52 KB eigener Speicher) und ihr `sleep` (40 bis 50 KB), dazu 20 bis 40 KB Zustand unter `/tmp`.
- **RAM kurzzeitig:** alle 91 s für wenige Sekunden `bridge`, `follow` und `island` (je bis 136 KB eigener Speicher, dazu kurze Hilfsprozesse und respondd-Abfragen an die Nachbarn), höchstens alle 5 min ein WLAN-Scan; stündlich `locate.sh`, das außerhalb von 25_hvb sofort endet.

Lizenz
------

BSD-3-Clause, siehe [LICENSE](LICENSE).

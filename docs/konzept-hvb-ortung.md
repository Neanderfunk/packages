# Konzept: Ortung und vereinfachtes Verschieben in der Domain 25_hvb

Entwurf zur Diskussion und Entscheidung. Stand 20.11.2026: Die meisten
Entscheidungen sind gefallen (Abschnitt 6). Gebaut ist bisher nur die
Ankündigung im Wizard (Abschnitt 4.1).

## 1. Ausgangslage

- Im Multi-Domain-Image startet ein neuer Knoten in der Domain `25_hvb`
  („Halteverbot“). Sie ist im Wizard ausgeblendet, solange der Knoten nicht
  schon darin steht, und ihr Name bittet darum, eine andere Domain zu wählen.
- Wer den Knoten trotzdem in `25_hvb` in Betrieb nimmt, dem ist angekündigt,
  dass der Knoten verschoben wird.
- Verschieben geht heute mit dem nodeplacer: ein signiertes Manifest mit
  einer Zeile `<node_id> domain target=<code>` je Knoten. Geprüft wird es mit
  den Schlüsseln und der Schwelle des Autoupdater-Branches des Knotens
  (D-031), bei `stable` also 3 Signaturen.
- Damit ist jede Verschiebung Handarbeit mit drei Unterschriften. Für
  Knoten in `25_hvb` ist das unverhältnismäßig, zumal man erst herausfinden
  muss, wo der Knoten steht.

## 2. Ziel und Nicht-Ziele

Ziel:

- Ein Knoten, der in `25_hvb` läuft, meldet die WLANs in seiner Umgebung an
  einen Dienst auf dem Mapserver.
- Der Dienst bestimmt daraus die passende Domain: zuerst über Freifunk-Knoten
  in Funkreichweite, sonst über einen Ortungsanbieter.
- Ist das Ergebnis sicher genug, verschiebt der Dienst den Knoten selbst
  („abschleppen“). Dazu nutzt er einen eigenen Schlüssel, der nur für den
  Umzug aus `25_hvb` in eine andere Domain gilt.
- Der Mapserver berichtet per Mail, welche Knoten wann abgeschleppt wurden.

Nicht-Ziele:

- Keine Ortung in anderen Domains. Ausschließlich `25_hvb`.
- Keine automatische Veröffentlichung der ermittelten Position auf der
  Karte.
- Kein Ersatz für die Domainwahl durch den Betreiber im Wizard.
- Kein Firmwarewechsel über diesen Weg, nur der Domainwechsel innerhalb der
  installierten Firmware.

## 3. Erfahrungen anderer Communities

- **4830.org** macht WLAN-Ortung produktiv (Paket
  `ffgt-config-mode-wizard`, Repo `ffgtso/4830_packages-v2025.x`):
  - `iw`-Scan, bis zu 30 Netze (BSSID, SSID, Signal) per GET an einen
    eigenen Dienst.
  - Zurück kommen Koordinaten, Adresse, PLZ und Ort. Der Knoten trägt sie
    ein und schaltet „Position veröffentlichen“ selbst an. Der Hostname
    entsteht aus PLZ und Adresse.
  - Ein zweites Skript fragt den Server nach der Zieldomain und wechselt zu
    einem vom Server genannten Zeitpunkt.
  - Welcher Dienst hinter dem Server steckt, ist nicht öffentlich.
  - 4830 hat eine Auffang-Domain für Knoten außerhalb der eigenen Gebiete,
    vergleichbar mit `25_hvb`.
- **Freifunk Nordwest** (GSoC 2017, „gluon-geolocator“):
  - BSSIDs an einen eigenen Dienst, mit dem Mozilla Location Service als
    Rückfall.
  - Der Pull-Request an Gluon (freifunk-gluon/gluon#1201) wurde am
    04.11.2019 wegen Datenschutz abgelehnt („with its privacy impact we are
    not going to merge this package“).
  - Der Hood-Selector von Nordwest wählt dagegen nach eingetragenen
    Koordinaten und Nachbar-Knoten, nicht per WLAN-Ortung.
- **Freifunk Franken** hatte ein Beispielskript, das direkt die Google-API
  fragt, mit fest eingebautem Schlüssel.

Daraus für uns:

- Das Verfahren funktioniert.
- Der heikle Teil ist das automatische Veröffentlichen der Position. Den
  lassen wir weg.
- Nachbar-Knoten als Hinweis auf die Domain (wie bei Nordwest) nehmen wir
  dazu, und zwar mit Vorrang (4.4).

## 4. Bausteine

### 4.1 Ankündigung im Wizard (umgesetzt)

- Ist `25_hvb` in der Domain-Auswahl gewählt, erscheint darunter ein
  Hinweis: Nicht dort betreiben; eventuell kein Internet; Knoten können
  anhand der WLANs in der Umgebung geortet und in eine andere Domain
  verschoben werden.
- Umsetzung:
  - Patch `config-mode/domain-select-hint` im Patch-Repo.
  - Text im Site-i18n-Schlüssel `gluon-config-mode:domain-hint:25_hvb`
    (de, en, fr).
- Kommt mit dem nächsten Multi-Bau.

### 4.2 Konfiguration in der Domain-Datei

- Die Ortung wird nur über die Domain-Datei von `25_hvb` eingeschaltet,
  nicht über die site.conf:

  ```lua
  neanderfunk_locate = {
    urls = {
      'https://locator.ffnef.de/hvb/locate',
      'http://locator.ffnef.de/hvb/locate',
    },
  },
  ```

- `check_site.lua` des neuen Pakets lässt den Schlüssel nur in der
  Domain-Datei zu (`in_domain`).
- Fehlt er in der aktiven Domain, tut das Paket nichts. Im Code steht
  nirgends „25_hvb“.
- Nach einer Verschiebung läuft beim Neustart `gluon-reconfigure`. Die neue
  Domain hat den Schlüssel nicht, die Ortung ist damit aus.
- **Öffentliche Adresse, kein Weg über ULA oder interne Namen.** Die Meldung
  geht direkt über das Internet zum Mapserver. Das hält das Konzept einfach,
  auch wenn die gemeldeten Netze dabei durchs Internet gehen.
- **Adresse:** `locator.ffnef.de`, öffentlich über IPv4 und IPv6. Der Name
  ist für Geräte und Configs gedacht. Zieht der Dienst um, ändern sich nur
  DNS und Proxy, nicht das Image. Unter `http` gibt es keine Umleitung auf
  `https`, damit POST auch ohne TLS ankommt.
- **TLS, wo der Knoten es kann:** Hat das Image TLS (`libustream-ssl`), nimmt
  der Knoten die `https`-Adresse. Sonst überspringt er sie und nimmt `http`.

### 4.3 Knoten: Ortungsskript (neues Paket)

**Auslöser:**

- Einmal nach dem Start, sobald der Knoten Internet hat.
- Danach einmal am Tag, solange der Knoten in `25_hvb` ist. Ohne
  Obergrenze: Es endet mit der Verschiebung.

**LAN-Mesh-Nachbarn einer anderen Domain** (adorfer 20.11.): Hier
entscheidet der Knoten selbst, ohne den Mapserver.

- Unsere Domains meshen am Kabel ohne VXLAN (`mesh.vxlan = false` in der
  Site). Ein LAN-Mesh-Nachbar aus einer anderen Domain ist also sofort
  batman-Partner, die Wolken sind schon verbunden. Ein sinnvolles Szenario,
  in dem der Knoten dann in `25_hvb` bleiben sollte, gibt es nicht.
- Der Knoten fragt die direkten Nachbarn je LAN-Mesh-Interface per respondd,
  wie die Statusseite: `gluon-neighbour-info -i <if> -d ff02::2:1001 -p 1001
  -r nodeinfo`. LAN-Mesh heißt jedes batman-Interface außer `mesh-vpn` und
  den WLAN-Meshes `meshN`.
- Die Antworten kommen nicht immer sofort: Auf der Statusseite stehen
  Nachbarn oft bis zu 30 s nur als MAC da (adorfer 20.11.). Der Knoten fragt
  deshalb wiederholt, bis jeder batman-Nachbar am LAN geantwortet hat
  (erkannt an seinen MACs in `network.mesh` des nodeinfo), höchstens 60 s.
  Wer bis dahin schweigt, steht nur mit MAC in der Meldung und zählt nicht.
- Die Domain steht in `system.domain_code`. Ältere Single-Domain-Images
  haben das Feld nicht; dann gilt der Teil des `site_code` hinter dem
  Bindestrich (`nef-21_dias`, `bgl-43_bggl`).
- **Umgeschaltet wird**, wenn am Kabel genau eine andere Domain als `25_hvb`
  zu sehen ist und sie im Image steht. Auch eine LVR-Domain ist dann Ziel.
- **Nicht umgeschaltet wird**, wenn die Domain nicht im Image steht (etwa
  Gluon einer Nachbar-Community am Kabel) oder wenn mehrere fremde Domains am
  Kabel hängen. Dann geht es weiter über den Mapserver bzw. von Hand.
  Nachbarn ohne Domainangabe zählen nicht, die eigene `node_id` auch nicht
  (der Knoten antwortet auf jedem Interface selbst).
- **Ablauf:** erst die Meldung an den Locator, mit `lan_mesh` und
  `lan_switch`, damit der Knoten im Mailbericht steht. Dann
  `gluon-switch-domain <domain>`, das ist ein Neustart. Die Meldung ist
  Beiwerk: Kommt sie nicht an, schaltet der Knoten trotzdem um.
- „Wer darf gehen?“ (E12, 4.4) gilt hier nicht. Wer am Kabel in der anderen
  Domain hängt, geht ohnehin über sie ins Netz. HVB-Knoten, die per WLAN an
  ihm hängen, sehen danach die Mesh-ID der neuen Domain und folgen über E11.
- Kein Schutz gegen falsche Antworten: Ein Nachbar am Kabel könnte eine
  falsche Domain melden. Wer schon am Kabel hängt, verbindet die Wolken aber
  ohnehin.
- Am 20.11. am M60 (LAN-Mesh über `br-mesh_other`) erprobt, als Trockenlauf
  mit `-n -a 25_hvb`: Der Nachbar meldet `21_dias`, das Skript würde dorthin
  umschalten.

**Hat der Knoten schon Koordinaten** (`gluon-node-info`), schickt er sie
zusätzlich zum Scan mit. Das gilt auch, wenn sie nicht veröffentlicht sind.

**Scan:**

- `iw dev <if> scan` auf einem der WLAN-Interfaces, 2.4 GHz und 5 GHz.
- Ob der Scan auf einem AP-Interface geht oder `ap-force` braucht, ist an
  den Zielgeräten zu prüfen [prüfen].

**Filter vor dem Senden:**

- Die eigenen Interfaces des Knotens raus.
- Netze, deren SSID auf `_nomap` endet, raus. Das ist die übliche
  Kennzeichnung für „nicht für Ortung verwenden“.
- Höchstens 30 Netze, die stärksten zuerst.
- Freifunk-Netze anderer Knoten bleiben drin: Sie sind der stärkste Hinweis
  auf die Domain (4.4).

**Senden:** HTTP-POST an die erste erreichbare URL aus
`neanderfunk_locate.urls` (siehe 4.2 zu TLS), mit eigenem User-Agent
`neanderfunk-locate/<version>`. Daran kann der Mapserver fremde POSTs schon
am Proxy verwerfen und die Annahme begrenzen.

```json
{ "v": 1,
  "node_id": "0123456789ab",
  "domain": "25_hvb",
  "release": "26111912bro",
  "uptime": 12345,
  "scan": [ { "iface": "mesh0", "ok": true, "count": 17 } ],
  "wifi": [ { "bssid": "aa:bb:cc:dd:ee:ff", "ssid": "Freifunk", "mesh_id": "", "signal": -61, "freq": 2437, "age_ms": 320 } ],
  "uplink": { "vpn": true, "gw_via": "mesh-vpn", "gw_nexthop": "02:ca:ff:ee:21:00",
              "mesh_macs": [ "12:3d:87:ce:a7:bb" ], "neighbours": { "vpn": 1, "wifi": 3, "lan": 0 } },
  "lan_mesh": [ { "iface": "br-mesh_other", "mac": "ce:30:aa:de:09:54", "node_id": "0123456789cd", "domain": "01_vel" } ],
  "lan_switch": "01_vel",
  "coordinates": { "lat": 51.0, "lon": 7.0 },
  "exit_ip": { "ipv4": "192.0.2.10" } }
```

- `ssid` und `mesh_id` gehen mit, damit der Dienst Freifunk-Knoten erkennt.
  Mesh-Punkte (802.11s) zeigen im Scan eine Mesh-ID statt einer SSID.
- `coordinates` nur, wenn der Knoten welche hat.
- `uplink`: ob der Knoten selbst einen VPN-Uplink hat (batman-Nachbar auf
  `mesh-vpn`), über welches Interface und welchen Next Hop sein Gateway
  läuft (`gw_via`, `gw_nexthop`), die MACs seiner batman-Interfaces
  (`mesh_macs`) und wie viele batman-Nachbarn er je Art hat. Wer über ihn ins
  Netz geht, sieht der Knoten selbst nicht; das ergibt sich aus den
  Meldungen der anderen (siehe „Wer darf gehen?“ in 4.4).
- `lan_mesh`: die direkten Nachbarn am LAN-Mesh mit ihrer Domain (siehe
  oben), dazu `mac`, die batman-Nachbar-MAC. Ein Nachbar, der nicht
  geantwortet hat, steht nur mit `iface` und `mac` da. Ohne
  LAN-Mesh-Nachbarn leer.
- `lan_switch`: nur, wenn der Knoten gleich nach der Meldung selbst in diese
  Domain umschaltet.
- `exit_ip`: die öffentlichen Adressen, mit denen der Knoten über seinen
  Uplink ins Internet geht. Er ermittelt sie selbst, so wie es `nodestatus`
  (Paket `neanderfunk-banner`) für IPv4 schon tut: Abfrage bei
  `ipv4.icanhazip.com` und `checkip.amazonaws.com` über das WAN. Ein schwacher
  Hinweis auf den Standort (4.4), aber genug, um nicht im falschen Land zu
  landen. Fehlt eine Adresse, bleibt das Feld weg.
- Die Absenderadresse der Meldung taugt nicht als Ersatz. Gemessen am
  20.11.: Auch ein Knoten mit eigenem WAN schickt die Meldung per IPv6 durch
  das Mesh. Absender ist dann seine Freifunk-Adresse über den Supernode, nicht
  sein Uplink. Die Exit-IPv4 ist damit der einzige Hinweis auf den Anschluss.
  Ein reiner Mesh-Knoten ohne IPv4-Uplink hat keine und lässt das Feld weg.

**Antwort:**

- Der Knoten selbst tut mit der Antwort nichts: keine Koordinaten
  eintragen, nichts veröffentlichen.
- Die Verschiebung kommt über den nodeplacer (4.5). Einzige Ausnahme ist
  das Umschalten wegen LAN-Mesh-Nachbarn (oben).

### 4.4 Ortungsdienst auf dem Mapserver

Der Dienst läuft komplett auf dem Mapserver: Annahme, Auswertung,
HVB-Manifest, Signieren, Berichte.

**1. Annahme:**

- Nur für `node_id`s, die laut Kartendaten (respondd) gerade in `25_hvb`
  sind. Meldungen für andere Knoten werden verworfen.
- Ohne internes Netz ist das die einzige Prüfung, dass die Meldung zu einem
  HVB-Knoten gehört. Eine gefälschte Meldung kann höchstens einen Knoten aus
  `25_hvb` in eine falsche Domain verschieben.

**Zieldomains:**

- **Über Mesh-Partner** (Schritt 1) in jede unserer Domains, auch in eine
  LVR-Domain. Der LVR bietet Wifimesh ausdrücklich an: Unsere Bedingung für
  Freifunk dort ist, dass an jedem Standort mindestens ein Knoten Wifimesh
  anbietet.
- **Über die Position** (Schritte 2 bis 4) nur in Ortsdomains und nach
  `21_dias`, nie in LVR-Domains (11, 31 bis 36). Der Mapserver führt dazu
  eine feste Liste der Domains, die über die Position Ziel sein dürfen.

**2. Domain bestimmen, in dieser Reihenfolge:**

Meldet ein Knoten `lan_switch`, hat er schon selbst entschieden (4.3). Der
Locator führt ihn nur im Bericht; abgeschleppt ist er, sobald er in der
Zieldomain auftaucht.

1. **Bekanntes Wifimesh in Funkreichweite (Mesh-Partner).** Jede unserer
   Domains hat eine eigene 802.11s-Mesh-ID, meist `<kurzname>-mesh` (etwa
   `vel-mesh`, `lvrno-mesh`), aber nicht immer: 43 bis 47 heißen
   `mesh-<kurzname>`. Der Locator liest die Zuordnung deshalb aus den
   Domain-Dateien, statt sie aus dem Namen abzuleiten. Die Mesh-ID im Scan
   zeigt dann direkt die Domain, ohne Abgleich mit Kartendaten. `hvb-mesh`
   zählt nicht.
   - **Es reicht** für eine Domain:
     - ein Mesh-Punkt dieser Domain mit mindestens -75 dBm (E11), oder
     - zwei Mesh-Punkte dieser Domain (verschiedene BSSIDs) mit beliebigem
       Pegel.
   - Erfüllen mehrere Domains die Bedingung, entscheidet der stärkste
     Mesh-Punkt.
   - Das hat Vorrang vor jeder Ortung: Mesh-Partner vor Ort binden stärker
     als eine Position.
   - Es zählen nur Mesh-Punkte (Mesh-ID), keine Client-SSIDs.
   - Knoten von Nachbar-Communities: Ihre Mesh-IDs sind nicht unsere. Sie
     zählen hier nicht, können aber im Bericht stehen.
2. **Eingetragene Koordinaten** des Knotens, wenn er welche mitschickt.
3. **Ortungsanbieter**, gestaffelt (Kosten siehe 4.6):
   - zuerst **beaconDB** (`https://api.beacondb.net/v1/geolocate`,
     MLS-kompatibel, ohne Schlüssel, mit eigenem User-Agent),
   - wenn dort nichts Brauchbares kommt, die **Google Geolocation API**.
   - An beide gehen nur BSSIDs und Signalstärken, keine `node_id`, keine
     SSIDs, keine Freifunk-BSSIDs.
   - Rückfall auf IP-Ortung ausschalten (Google `considerIp: false`,
     beaconDB `fallbacks`). Sonst käme die Position des Mapservers zurück.
   - Google braucht mindestens 2 WLANs.
4. **Exit-IP** (schwacher Hinweis): Land und Netzbetreiber aus einer lokalen
   GeoIP-Datenbank auf dem Mapserver. Die Adresse geht an keinen
   Ortungsanbieter.
   - Wählt nie allein eine Ortsdomain: Mobilfunk, CGNAT, VPN-Anbieter oder
     Satellit verorten oft weit daneben.
   - Dient zur Plausibilität: Liegt die Position aus Schritt 1 bis 3 in
     unserem Gebiet, die Exit-IP aber klar in einem anderen Land, ist der Fall
     widersprüchlich und geht zur Klärung von Hand.
   - Gibt es sonst gar nichts und liegt die Exit-IP klar im Ausland, ist
     `21_dias` der naheliegende Vorschlag. Vorschlag: auch das erst von Hand
     bestätigen.

**3. Position zu Domain:** Der Mapserver berechnet die Domaingrenzen einmal
als statisches Datenmodell: eine Fläche je Ortsdomain aus den Positionen
ihrer Knoten, ähnlich wie man Gebiete von Communities aus Knotenpositionen
berechnet. Das Ergebnis ist zum Beispiel eine GeoJSON-Datei mit einem Polygon
je Domain. Neu berechnet wird nur bei Bedarf und von Hand. Die Vereinigung
aller Flächen ist unser Gebiet.

**4. Sicher genug?** Die Genauigkeit zählt nur an der Außengrenze unseres
Gebiets, also für die Abgrenzung zu `21_dias` (E10):

- **Position in unserem Gebiet:** Zieldomain ist die Fläche, in der die
  Position liegt, an einer Grenze zwischen zwei Domains die nähere. Ein
  Genauigkeitskreis über die Grenze zwischen zwei Domains hält die
  Verschiebung nicht auf.
- **Position außerhalb unseres Gebiets:** nach `21_dias` (Diaspora), wenn
  der ganze Genauigkeitskreis außerhalb liegt. Reicht der Kreis in unser
  Gebiet hinein, Klärung von Hand.
- **Genauigkeitsradius über 5000 m, oder keiner geliefert:** keine
  automatische Verschiebung, Klärung von Hand.
- **Eindeutige Mesh-Partner** (Schritt 1) gehen allem vor; dort spielt die
  Genauigkeit keine Rolle.

Alles, was nicht automatisch verschoben wird, landet im Bericht zur Klärung
von Hand.

- Google liefert `accuracy` als Radius in Metern, ohne Angabe eines
  Konfidenzniveaus. Mit zwei oder mehr WLANs nennt Google typisch etwa
  20 m.
- Die MLS-Schnittstelle, die beaconDB übernimmt, hat dasselbe Feld. Ob
  beaconDB es sinnvoll füllt, ist ungeprüft [prüfen].

**Wer darf gehen?** (adorfer 20.11.) Ein Knoten aus `25_hvb` darf nur
verschoben werden, wenn er dabei niemanden vom Netz abschneidet, auch sich
selbst nicht:

- **Ohne eigenen VPN-Uplink nie.** Ein Knoten, der nur per WLAN-Mesh oder
  LAN-Mesh im Netz hängt, bleibt in `25_hvb`. In einer anderen Domain fände
  er seine Mesh-Partner nicht mehr und hätte gar kein Netz. Das betrifft nur
  den Weg über den Mapserver. Hängt der Knoten am Kabel an einer anderen
  Domain, schaltet er selbst um (4.3).
- **Mit VPN-Uplink nur, wenn niemand an ihm hängt.** Gehen andere Knoten in
  `25_hvb` über ihn ins Netz, bleibt er ebenfalls.
- **Zwei Knoten, die beide VPN haben und zusätzlich zueinander meshen,
  blockieren sich nicht.** Jeder darf einzeln gehen.

**Prüfung nur aus den Meldungen, ohne Kartendaten:** Jeder HVB-Knoten
meldet ohnehin, ob er eigenes VPN hat und über welchen Next Hop sein Gateway
läuft (`uplink.gw_nexthop`, aus `batctl gwl`), dazu die MACs seiner
batman-Interfaces (`uplink.mesh_macs`). Damit ist die Regel eine einfache
Nachschlage-Operation:

- Knoten X darf nicht gehen, wenn X selbst `vpn: false` meldet.
- Knoten X darf nicht gehen, wenn ein HVB-Knoten ohne VPN einen
  `gw_nexthop` meldet, der unter den `mesh_macs` von X steht.
- Ketten erledigen sich von selbst: Hängt C an B und B an A, dann meldet B
  kein VPN (bleibt) und hat A als Next Hop (A bleibt auch).
- Zwei VPN-Knoten, die zueinander meshen, melden beide `mesh-vpn` als
  Gateway-Weg und blockieren sich deshalb nicht.

Das ist vorsichtig: Hat ein Knoten ohne VPN zwei mögliche Uplinks, blockiert
er den, den batman gerade gewählt hat. Mit der täglichen Meldung löst sich
das, sobald sich die Lage ändert. Ein Wolkenabgleich mit den Kartendaten ist
dafür nicht nötig.

Verworfen (20.11.): die Zahl der Originatoren hinter einem Nachbarn
(`batctl o`) als Zeichen für einen zweiten Uplink. Das täuscht in beide
Richtungen:

- Hat der Nachbar eigenes VPN, ist für fast alle Originatoren der eigene
  VPN-Weg besser. Hinter dem Nachbarn stehen dann nur wenige, und zwei
  VPN-Knoten würden sich gegenseitig blockieren.
- Hängt dagegen ein großer Ast ohne VPN am Nachbarn, stehen viele dahinter,
  ohne dass es einen zweiten Uplink gibt.

Was hängen bleibt, kommt in den Bericht. Bei der Klärung von Hand kann man
eine ganze Wolke gemeinsam verschieben, mit einer Zeile je Knoten im selben
Manifest. Automatisch macht der Locator das nicht.

Die Lage kann sich ändern, bevor ein Knoten das Manifest abholt. Deshalb
prüft der Dienst bei jedem neuen Erzeugen des HVB-Manifests erneut und nimmt
Zeilen heraus, die die Regel nicht mehr erfüllen.

**5. Verschieben:** Der Dienst schreibt eine Zeile
`<node_id> domain target=<code>` ins HVB-Manifest. Der Mapserver signiert es
mit dem HVB-Schlüssel und liefert es selbst aus (4.5). Eine Klärung von Hand
endet genauso: Wer den Fall klärt, trägt die Zieldomain auf dem Mapserver
ein.

**6. Berichte per Mail:**

- Welche Knoten wann erfolgreich abgeschleppt wurden. Erfolg heißt: Der
  Knoten taucht in den Kartendaten in der Zieldomain auf.
- Fälle zur Klärung von Hand (unsicher, widersprüchlich, kein Ergebnis).
- Den Rhythmus (je Ereignis oder täglich gesammelt) und die Empfänger legt
  der Mapserver-Betrieb fest.

**7. Speichern:** Gespeichert wird auf dem Mapserver, 14 Tage lang:

- die Position, auf ein 200-m-Raster vergröbert,
- dazu der Genauigkeitsradius, wenn der Anbieter einen liefert,
- die gemeldete Exit-IP.

Danach bleiben nur `node_id`, Zieldomain und Zeit (für die Berichte).

### 4.5 nodeplacer: Umzug aus 25_hvb mit eigenem Schlüssel

**Schlüssel und Schwelle in der Domain-Datei von `25_hvb`:**

```lua
nodeplacer = {
  mirrors = { 'https://locator.ffnef.de/hvb/nodeplacer', 'http://locator.ffnef.de/hvb/nodeplacer' },
  pubkeys = { '<hvb-key>' },
  good_signatures = 1,
},
```

- `510-nodeplacer` liest diese Werte schon heute über `gluon.site`. Bei
  jedem `gluon-reconfigure` schreibt es sie nach `/etc/config/nodeplacer`.
- Zu ändern ist `check_site.lua`: `pubkeys` und `good_signatures` dürfen dann
  auch in der Domain-Datei stehen. Bisher geht das nur in der Site (D-044).
- Zur Laufzeit ersetzt eine Liste aus der Domain-Datei die Liste der Site
  vollständig: `merge_json` in libgluonutil führt nur Objekte zusammen,
  keine Arrays. In `25_hvb` gilt dann nur der HVB-Schlüssel, die
  Release-Schlüssel gelten dort nicht.
- Nach dem Verschieben gilt beim Neustart wieder die Schwelle des
  Autoupdater-Branches. Der HVB-Schlüssel wirkt in keiner anderen Domain.
- Der private HVB-Schlüssel liegt nur auf dem Mapserver.

**Eigenes Manifest auf dem Mapserver:**

- Heute zeigen alle Domains auf denselben Pfad (`.../firmware/nodeplacer`).
  `25_hvb` bekommt eigene Mirrors auf dem Mapserver, mit eigenem Manifest.
- https wie in 4.2: `nodeplacer-fetch` nutzt uclient wie der Autoupdater,
  https geht also nur mit TLS im Image [prüfen].

**Nur Domainwechsel annehmen:**

- Nach D-032 richtet sich auch die Schwelle für eine Zielfirmware
  (Methode `firmware`) nach dem eigenen Vertrauensniveau. Ohne Einschränkung
  könnte der HVB-Schlüssel also auch einen Firmwarewechsel auslösen.
- Deshalb: Sind Schlüssel oder Schwelle über die Domain gesetzt, nimmt der
  nodeplacer nur Zeilen der Methode `domain` an.
- Ziel darf nicht die aktuelle Domain sein.
- Kleine Codeänderung in `nodeplacer` (Lua) plus Test.

**Schwelle als Obergrenze:**

- Der Domain-Wert gilt als Obergrenze: Es gilt der kleinere von Domain-Wert
  und Branch-Wert.
- Mit `good_signatures = 1` ändert das für `broken`-Knoten nichts. Es
  schützt aber vor einem späteren höheren Domain-Wert.

### 4.6 Kosten der Ortungsanbieter (zu E4)

Stand der Recherche 20.11.2026:

- **beaconDB:**
  - Kostenlos, ohne Schlüssel.
  - Die Seite bittet um einen eigenen User-Agent.
  - Eine Nutzungsrichtlinie oder Ratenbegrenzung ist auf der Startseite
    nicht genannt.
  - Die Seite nennt den Dienst selbst „experimentell“.
- **Google Geolocation API:**
  - Was man braucht: ein Google-Cloud-Projekt mit aktivierter Abrechnung
    (Rechnungskonto mit Zahlungsmittel) und einen API-Schlüssel.
  - Preis: SKU „Geolocation“, Kategorie Essentials. 10.000 Abfragen im
    Monat kostenlos, danach 5,00 US-$ je 1.000 Abfragen (bis 100.000), in
    höheren Stufen günstiger.
  - Es gibt keine automatische Ausgabengrenze. Eine harte Grenze geht nur
    über eine Quote (Abfragen je Tag) in der Cloud-Konsole. Die sollte von
    Anfang an gesetzt sein.
  - Abschätzung: Google wird nur gefragt, wenn beaconDB nichts liefert, und
    nur solange ein Knoten noch kein sicheres Ergebnis hat. Selbst 100
    HVB-Knoten mit täglicher Abfrage über 30 Tage wären 3.000 Abfragen im
    Monat, also im kostenlosen Rahmen.
  - Ob die Nutzungsbedingungen von Google erlauben, die Ergebnisse 14 Tage
    zu speichern, ist ungeprüft [prüfen].

## 5. Datenschutz und Sicherheit

- Die BSSIDs der Nachbar-WLANs gehen an einen Dritten (beaconDB, Google), und
  die ermittelte Position ist meist eine Privatwohnung.
- Die Meldung des Knotens geht über das Internet. Bei Knoten ohne TLS geht
  sie im Klartext, mit BSSIDs und SSIDs der Umgebung. Das ist bewusst so
  entschieden, damit das Konzept einfach bleibt.
- Abmilderung:
  - Ankündigung im Wizard (4.1).
  - Nur in `25_hvb`.
  - TLS, wo der Knoten es kann.
  - Ohne `node_id` und ohne SSIDs zum Anbieter.
  - Keine Veröffentlichung.
  - `_nomap` beachten.
  - 14 Tage Speicherung, Position auf 200 m vergröbert, Exit-IP ebenso
    nur 14 Tage.
- **HVB-Schlüssel auf dem Mapserver:** Der Mapserver kann damit Knoten
  verschieben, aber nur Knoten in `25_hvb`, nur per Methode `domain` und nur
  in andere Domains derselben Firmware.
- **Genauigkeit:**
  - Die Daten der Anbieter stammen überwiegend von Handys auf der Straße.
    Für die Wahl einer Ortsdomain sollte das in der Regel reichen.
  - An Domaingrenzen kann es danebenliegen [nicht gemessen].
  - Dagegen helfen die Genauigkeitsprüfung in 4.4 und die Klärung von Hand.

## 6. Entscheidungen

| Nr. | Frage | Entscheidung |
|---|---|---|
| E1 | Weniger Signaturen oder eigener Schlüssel? | **20.11.:** eigener Schlüssel, nur für den Umzug aus `25_hvb` in eine andere Domain derselben Firmware. Einzige Ausnahme: LAN-Mesh-Nachbarn genau einer anderen Domain, dann schaltet der Knoten selbst um (4.3) |
| E2 | Bei gesenkter Schwelle nur Methode `domain` annehmen? | **20.11.:** ja, nur `domain` |
| E3 | Domain-Schwelle als fester Wert oder als Obergrenze? | **20.11.:** Obergrenze |
| E4 | Ortungsanbieter? | **20.11.:** beide gestaffelt, beaconDB zuerst, dann Google (Kosten 4.6) |
| E5 | Wie wird aus der Position eine Domain? | **20.11.:** Mapserver berechnet einmalig Domainflächen, statisches Datenmodell; Mesh-Partner haben Vorrang |
| E6 | Was wird gespeichert, wie lange? | **20.11.:** 14 Tage, 200-m-Raster, mit Genauigkeitsradius. Zu unsicher heißt nicht verschieben, sondern Klärung von Hand. Speicherort ist der Mapserver |
| E7 | Name und Adresse des Dienstes | **20.11.:** `locator.ffnef.de`, Pfade `/hvb/locate` und `/hvb/nodeplacer`, je https und http |
| E8 | Was passiert mit Knoten außerhalb aller Domains? | **19.11.:** nach `21_dias` |
| E9 | Wiederholung? | **20.11.:** täglich, bis zur Verschiebung |
| E10 | Grenze für den Genauigkeitsradius | **20.11.:** 5000 m, gilt nur an der Außengrenze (Abgrenzung zu `21_dias`); zwischen zwei Domains entscheidet die nähere |
| E11 | Wie viele Mesh-Partner einer Domain reichen? | **20.11.:** ein bekanntes Wifimesh ab -75 dBm oder zwei mit beliebigem Pegel; LVR-Domains zählen mit |
| E12 | Welche HVB-Knoten dürfen überhaupt gehen? | **20.11.:** nur mit eigenem VPN-Uplink und nur, wenn kein Knoten ohne VPN dadurch abgeschnitten wird; zwei VPN-Knoten, die zueinander meshen, blockieren sich nicht |

Außerdem am 20.11. entschieden:

- keine Übertragung über ULA oder interne Adressen,
- TLS, wo der Knoten es kann,
- HVB-Manifest auf dem Mapserver,
- Berichte per Mail,
- die Exit-IP des Knotens geht als schwacher Hinweis mit,
- in LVR-Domains verschiebt der Locator nur über Mesh-Partner, nie über
  die Position.

## 7. Arbeitspakete und Reihenfolge

**Zuerst ein Prototyp, der Daten liefert** (adorfer 20.11.). Was wir mit den
Daten tun, entscheiden wir danach.

- **Stufe 1, läuft seit 20.11.:**
  - Der Locator legt jede Meldung roh ab (14 Tage) und wertet sie je Knoten
    aus, mit E11 als Trockenlauf.
  - Das Skript `neanderfunk-locate` (Prototyp, noch nicht im Image) läuft
    von Hand auf Testknoten im Labor.
  - Deren Position ist bekannt, das Ergebnis also vorhersehbar. Es geht erst
    einmal um Format, Scan und Übertragung.
- **Stufe 2:** eine Ansible-Rolle für den Betrieb. Sie führt die
  Datensammlung einmal auf Knoten aus, auf die wir per SSH kommen, auch
  außerhalb von `25_hvb`. Das liefert Testdaten aus vielen Standorten, an
  denen sich Ortung und E11 messen lassen.

Danach, für den echten Betrieb:

1. **Ankündigung im Wizard:** erledigt, kommt mit dem nächsten Multi-Bau.
2. **nodeplacer:**
   - `good_signatures`/`pubkeys` auch in der Domain-Datei zulassen.
   - Einschränkung auf `domain`, Ziel nicht die eigene Domain (E2).
   - Obergrenze (E3).
   - Tests.
3. **Mapserver, erster Teil (Abschleppen von Hand):**
   - HVB-Schlüssel erzeugen, Manifest unter eigenem Pfad ausliefern.
   - Liste zum Eintragen von Hand, Signieren.
   - Bericht per Mail, wer in der Zieldomain angekommen ist.
4. **FirmwareConfigs:** `25_hvb` bekommt die nodeplacer-Mirrors auf dem
   Mapserver, den HVB-Schlüssel mit Schwelle 1 und `neanderfunk_locate.urls`.
5. **Mapserver, zweiter Teil (Ortung):**
   - Annahme der Meldungen, Abgleich mit den Kartendaten.
   - Mesh-Partner über die Mesh-ID erkennen.
   - Domainflächen einmalig berechnen, Liste der Domains, die über die
     Position Ziel sein dürfen (ohne LVR).
   - Anbieterabfrage, Exit-IP-Prüfung, Genauigkeitsprüfung, Speicherung
     14 Tage.
6. **Neues Paket auf dem Knoten:** Scan, Filter, Exit-IP, Meldung, tägliche
   Wiederholung. Dazu die Prüfung der LAN-Mesh-Nachbarn bald nach dem Start,
   sobald batman Nachbarn hat, auch ohne Internet (im Prototyp schon drin).
7. **Test:** Knoten im Labor in `25_hvb`, Meldung, Verschiebung per
   HVB-Manifest, Rückkehr der normalen Schwelle nach dem Neustart, Bericht.
   Dazu ein Knoten in `25_hvb` am Kabel an einem Knoten einer anderen
   Domain: Umschalten ohne Mapserver.

Punkt 2 bis 4 lohnen sich auch ohne Ortung: Das Abschleppen aus `25_hvb` von
Hand geht damit schon ohne drei Unterschriften.

## 8. Quellen

- 4830: https://github.com/ffgtso/4830_packages-v2025.x
- Gluon-PR gluon-geolocator: https://github.com/freifunk-gluon/gluon/pull/1201
- GSoC-Bericht Geolocator: https://blog.freifunk.net/2017/08/29/geolocator-software-defined-gps-final-evaluation/
- Franken, Beispielskript: https://git.freifunk-franken.de/freifunk-franken/monitoring/src/branch/master/contrib/geolocate.py
- Geolocate-Schnittstelle (MLS, von beaconDB übernommen): https://ichnaea.readthedocs.io/en/latest/api/geolocate.html
- beaconDB: https://beacondb.net/
- Google Geolocation API, Anfragen und Antwort: https://developers.google.com/maps/documentation/geolocation/requests-geolocation
- Google Geolocation API, Nutzung und Abrechnung: https://developers.google.com/maps/documentation/geolocation/usage-and-billing
- Google Maps Platform, Preisliste: https://developers.google.com/maps/billing-and-pricing/pricing
- Gluon, Zusammenführen von Site und Domain zur Laufzeit:
  `package/libgluonutil/src/libgluonutil.c` (`merge_json`)
- nodeplacer: `neanderfunk-nodeplacer/docs/DECISIONS.md` (D-031, D-032,
  D-044), `docs/MANIFEST-FORMAT.md`

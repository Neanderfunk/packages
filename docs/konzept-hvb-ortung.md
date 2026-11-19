# Konzept: Ortung und vereinfachtes Verschieben in der Domain 25_hvb

Entwurf zur Diskussion und Entscheidung, Stand 19.11.2026. Nichts davon ist
gebaut, außer der Ankündigung im Wizard (Abschnitt 4.1).

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

- Ein Knoten, der in `25_hvb` läuft, ermittelt grob seinen Standort über
  die WLANs in seiner Umgebung und meldet sie an einen eigenen Dienst.
- Der Dienst schlägt daraus die passende Domain vor.
- Das Verschieben aus `25_hvb` heraus braucht weniger Aufwand als in
  anderen Domains (weniger Signaturen oder ein eigener Schlüssel).

Nicht-Ziele:

- Keine Ortung in anderen Domains. Ausschließlich `25_hvb`.
- Keine automatische Veröffentlichung der ermittelten Position auf der
  Karte.
- Kein Ersatz für die Domainwahl durch den Betreiber im Wizard.

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
      'http://<dienst>.25-hvb.ffnef/locate',
      'http://[<ULA von 25_hvb>::<host>]/locate',
    },
  },
  ```

- `check_site.lua` des neuen Pakets lässt den Schlüssel nur in der
  Domain-Datei zu (`in_domain`).
- Fehlt er in der aktiven Domain, tut das Paket nichts. Im Code steht
  nirgends „25_hvb“.
- Nach einer Verschiebung läuft beim Neustart `gluon-reconfigure`. Die neue
  Domain hat den Schlüssel nicht, die Ortung ist damit aus.
- Nur interne Adressen (`.ffnef`-Name oder ULA), so wie die
  Autoupdater-Mirrors von `25_hvb`: Die Daten gehen durch den Tunnel zum
  eigenen Server, nicht im Klartext über das Internet. `25_hvb` hat eigene
  VPN-Broker.

### 4.3 Knoten: Ortungsskript (neues Paket)

**Auslöser:**

- Einmal nach dem Start, sobald der Mesh-VPN steht.
- Danach einmal am Tag, solange der Knoten in `25_hvb` ist und keine
  Antwort bekommen hat.

**Hat der Knoten schon Koordinaten** (`gluon-node-info`), schickt er die
statt eines Scans. Das gilt auch, wenn sie nicht veröffentlicht sind.

**Scan:**

- `iw dev <if> scan` auf einem der WLAN-Interfaces, 2.4 GHz und 5 GHz.
- Ob der Scan auf einem AP-Interface geht oder `ap-force` braucht, ist an
  den Zielgeräten zu prüfen [prüfen].

**Filter vor dem Senden:**

- Eigene Netze raus: die BSSIDs aller Freifunk-Knoten, mindestens die mit
  unseren SSIDs und der Mesh-ID.
- Netze, deren SSID auf `_nomap` endet, raus. Das ist die übliche
  Kennzeichnung für „nicht für Ortung verwenden“.
- Höchstens 30 Netze, die stärksten zuerst.

**Senden:** HTTP-POST an die erste erreichbare URL aus `neanderfunk_locate.urls`:

```json
{ "node_id": "0123456789ab", "wifi": [ { "bssid": "aa:bb:cc:dd:ee:ff", "signal": -61, "channel": 6 } ] }
```

Die SSIDs werden nicht mitgeschickt; die Ortung braucht nur die BSSIDs.

**Antwort:**

- Der Knoten selbst tut mit der Antwort nichts: keine Koordinaten
  eintragen, nichts veröffentlichen.
- Er merkt sich nur, dass gemeldet wurde (für die tägliche Wiederholung).

### 4.4 Ortungsdienst (Wrapper auf dem Mapserver)

1. Nimmt die Meldung an, nur aus den Netzen von `25_hvb`.
2. Fragt einen Ortungsanbieter. Die `node_id` gibt er dabei nicht weiter;
   der Anbieter sieht nur die Adresse unseres Servers.
   - **beaconDB** (`https://api.beacondb.net/v1/geolocate`): Nachfolger des
     2024 abgeschalteten Mozilla Location Service, gleiche Schnittstelle,
     ohne Schlüssel. Laut Nutzerberichten noch schwache Abdeckung.
   - **Google Geolocation API**: Schlüssel nötig, kostenpflichtig, gute
     Abdeckung.
   - Möglich: erst beaconDB, nur wenn nichts kommt Google.
   - Ein Schlüssel liegt nur auf dem Server, nie im Image.
3. Ordnet die Position einer Domain zu (siehe Entscheidung E5).
4. Schreibt eine Zeile `<node_id> domain target=<code>` in die Liste für
   das nächste HVB-Manifest (siehe 4.5) und legt das Ergebnis zur
   Nachkontrolle ab.

Liegt die Position außerhalb aller Domains, bleibt der Knoten in `25_hvb`.
Er landet dann auf einer Liste für Handarbeit.

### 4.5 nodeplacer: vereinfachtes Verschieben aus 25_hvb

**Ort der Einstellung:**

- In der Domain-Datei von `25_hvb`, im vorhandenen `nodeplacer`-Block.
- `510-nodeplacer` liest `good_signatures` und `pubkeys` schon heute über
  `gluon.site` (Site und aktive Domain zusammengeführt). Bei jedem
  `gluon-reconfigure` schreibt es die Werte nach `/etc/config/nodeplacer`.
- Zu ändern ist nur `check_site.lua`: Beide Schlüssel dürfen dann auch in
  der Domain-Datei stehen. Bisher sind sie nur in der Site erlaubt (D-044).
- Nach dem Verschieben gilt beim Neustart wieder die Schwelle des
  Autoupdater-Branches.

**Varianten:**

- **A: weniger Signaturen.** `good_signatures = 2` mit den Release-Schlüsseln.
  Zwei Menschen unterschreiben die vom Dienst vorbereitete Liste.
- **B: eigener Schlüssel.** `pubkeys = { '<hvb-key>' }, good_signatures = 1`.
  Der Dienst signiert selbst, Verschieben geht ohne Menschen. Die
  Release-Schlüssel bleiben, wo sie sind.
- **A und B kombinieren** geht nur über eine Codeänderung: Heute gilt eine
  Schlüsselliste mit einer Schwelle.

**Eigener Mirror-Pfad für 25_hvb:**

- Heute zeigen alle Domains auf denselben Pfad (`.../firmware/nodeplacer`),
  also auf ein gemeinsames Manifest. Knoten anderer Domains verlangen
  3 Signaturen und würden ein HVB-Manifest mit weniger ablehnen.
- Deshalb braucht `25_hvb` einen eigenen Pfad, etwa
  `.../firmware/nodeplacer-hvb`, mit eigenem Manifest.

**Nur Domainwechsel annehmen:**

- Nach D-032 richtet sich auch die Schwelle für eine Zielfirmware
  (Methode `firmware`) nach dem eigenen Vertrauensniveau. Eine gesenkte
  Schwelle würde also auch einen Firmwarewechsel mit weniger Signaturen
  erlauben.
- Vorschlag: Ist die Schwelle über die Domain gesenkt, nimmt der nodeplacer
  nur Zeilen der Methode `domain` an.
- Kleine Codeänderung in `nodeplacer` (Lua) plus Test.

**broken-Knoten:**

- Ihr Branch verlangt 1 Signatur. Ein fester Domain-Wert 2 würde ihre
  Schwelle anheben.
- Wenn das stört: Der Domain-Wert gilt als Obergrenze, es gilt der kleinere
  Wert.

## 5. Datenschutz und Sicherheit

- Die BSSIDs der Nachbar-WLANs gehen an einen Dritten, und die ermittelte
  Position ist meist eine Privatwohnung.
- Abmilderung:
  - Ankündigung im Wizard (4.1).
  - Nur in `25_hvb`.
  - Nur interne Übertragung bis zum Dienst.
  - Ohne `node_id` zum Anbieter.
  - Keine Veröffentlichung.
  - `_nomap` beachten.
- Gespeichert wird so wenig wie möglich. Vorschlag: Zieldomain und Zeit
  dauerhaft, die Position nur vergröbert (etwa auf 0.01°) und nur bis zur
  Verschiebung (Entscheidung E6).
- **Variante B** (Dienst signiert selbst) macht den Server zu einem Punkt,
  der Knoten verschieben kann. Das ist begrenzt auf Knoten in `25_hvb` und
  auf die Methode `domain`, wenn die Einschränkung aus 4.5 kommt.
- **Genauigkeit:** Die Daten der Anbieter stammen überwiegend von Handys
  auf der Straße. Für die Wahl einer Ortsdomain sollte das in der Regel
  reichen. An Domaingrenzen kann es danebenliegen [nicht gemessen].

## 6. Offene Entscheidungen

| Nr. | Frage | Vorschlag |
|---|---|---|
| E1 | Variante A (2 Signaturen) oder B (eigener Schlüssel, Dienst signiert)? | B für den Normalfall, A als Rückfall von Hand |
| E2 | Bei gesenkter Schwelle nur Methode `domain` annehmen? | ja |
| E3 | Domain-Schwelle als fester Wert oder als Obergrenze (broken)? | Obergrenze |
| E4 | Ortungsanbieter: beaconDB, Google oder beide gestaffelt? | beaconDB zuerst, Google als Rückfall, wenn der Schlüssel bezahlt wird |
| E5 | Wie wird aus der Position eine Domain: nächster Domain-Mittelpunkt, Gemeindegrenzen oder Polygone je Domain? | Polygone je Domain, wo vorhanden, sonst Handarbeit |
| E6 | Was wird gespeichert, wie lange? | Domain und Zeit; Position vergröbert bis zur Verschiebung |
| E7 | Name und Adresse des Dienstes (vhost, ULA) | legt der Mapserver fest |
| E8 | Was passiert mit Knoten außerhalb aller Domains? | bleiben in `25_hvb`, Liste für Handarbeit |
| E9 | Wiederholung: täglich bis zur Verschiebung, oder nach n Versuchen aufhören? | täglich, höchstens 30 Tage |

## 7. Arbeitspakete und Reihenfolge

1. **Ankündigung im Wizard:** erledigt, kommt mit dem nächsten Multi-Bau.
2. **nodeplacer:**
   - `good_signatures`/`pubkeys` auch in der Domain-Datei zulassen.
   - Einschränkung auf `domain` (E2).
   - Obergrenze (E3).
   - Tests.
3. **FirmwareConfigs:** `25_hvb` bekommt den eigenen nodeplacer-Mirror-Pfad,
   die Schwelle oder den Schlüssel und `neanderfunk_locate.urls`.
4. **Ortungsdienst auf dem Mapserver:**
   - Annahme der Meldungen.
   - Anbieterabfrage.
   - Domainzuordnung.
   - Manifest-Liste, bei Variante B auch Signieren.
5. **Neues Paket auf dem Knoten:** Scan, Filter, Meldung, Wiederholung.
6. **Test:** Knoten im Labor in `25_hvb`, Meldung, Verschiebung per
   HVB-Manifest, Rückkehr der normalen Schwelle nach dem Neustart.

Punkt 2 und 3 lohnen sich auch ohne Ortung: Verschieben aus `25_hvb` per
Hand wird damit schon einfacher.

## 8. Quellen

- 4830: https://github.com/ffgtso/4830_packages-v2025.x
- Gluon-PR gluon-geolocator: https://github.com/freifunk-gluon/gluon/pull/1201
- GSoC-Bericht Geolocator: https://blog.freifunk.net/2017/08/29/geolocator-software-defined-gps-final-evaluation/
- Franken, Beispielskript: https://git.freifunk-franken.de/freifunk-franken/monitoring/src/branch/master/contrib/geolocate.py
- Geolocate-Schnittstelle (MLS, von beaconDB übernommen): https://ichnaea.readthedocs.io/en/latest/api/geolocate.html
- nodeplacer: `neanderfunk-nodeplacer/docs/DECISIONS.md` (D-031, D-032,
  D-044), `docs/MANIFEST-FORMAT.md`

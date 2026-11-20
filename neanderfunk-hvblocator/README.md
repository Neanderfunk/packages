neanderfunk-hvblocator
======================

Lokator und Abschleppdienst für Halteverbots-Defaultdomain.

Scannt die WLANs in der Umgebung eines Knotens und meldet sie per POST an den
Locator (`locator.ffnef.de`). Hängt ein Knoten per LAN-Mesh an genau einer
anderen Domain, schaltet er selbst dorthin um. Konzept und Format:
[docs/konzept-hvb-ortung.md](../docs/konzept-hvb-ortung.md), Abschnitte 4.2
und 4.3.

**Stand 0.2 (20.11.2026):** erstes Paket für eine Testfirmware.

Einschalten
-----------

Nur über die Domain-Datei, nicht über die site.conf (`check_site.lua`
erlaubt den Schlüssel nur `in_domain`):

```lua
neanderfunk_hvblocator = {
  urls = {
    'https://locator.ffnef.de/hvb/locate',
    'http://locator.ffnef.de/hvb/locate',
  },
},
```

Bei uns steht das nur in `25_hvb`. In jeder anderen Domain fehlt der
Schlüssel, dann tut das Paket nichts. Nach einer Verschiebung ist die Ortung
damit von selbst aus. Im Code steht keine Domain.

Wann es läuft
-------------

- **Nach dem Start:** `/etc/init.d/neanderfunk-hvblocator` startet
  `run.sh boot` im Hintergrund. Es wartet 60 s, dann bis batman einen
  Nachbarn hat, höchstens bis 600 s Uptime, und meldet dann einmal. Die
  LAN-Mesh-Prüfung braucht kein Internet.
- **Täglich:** micron.d ruft `run.sh cron` stündlich zur Minute 9 auf. Es
  meldet erst, wenn die letzte Meldung 24 h her ist (nach einem
  Fehlschlag 6 h). Gemessen wird in Uptime, Stand in
  `/tmp/neanderfunk-hvblocator.stamp`. Gemeldet wird je Knoten fest 0 bis
  49 min später (letztes Byte der primären MAC). Ohne Schlüssel endet
  `run.sh` nach einem `jsonfilter`, ohne Lua zu starten.
- Nicht im Setup-Mode, nie zwei Läufe gleichzeitig (Sperre in `/tmp`).

Aufruf
------

```sh
neanderfunk-hvblocator        # scannen und melden
neanderfunk-hvblocator -n     # nur scannen, JSON ausgeben, nichts senden
neanderfunk-hvblocator -u URL # an diese URL melden, auch ohne Schlüssel
                              # in der Domain (schaltet dann nie um)
neanderfunk-hvblocator -n -a 25_hvb  # Trockenlauf, als stünde der Knoten mit
                                     # eingeschalteter Ortung in 25_hvb
```

Ergebnis steht im Syslog (`logread | grep neanderfunk-hvblocator`).

Was das Skript tut
------------------

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
  aus dem `site_code` hinter dem Bindestrich. Antworten kommen nicht immer
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
  User-Agent ist `neanderfunk-hvblocator/<version>`. Der Locator antwortet mit
  200. Das Skript nimmt trotzdem jede 2xx-Antwort an: `uclient-fetch` zählt
  nur 200 als Erfolg und meldet etwa 202 als „HTTP error 202“ mit rc 8. Den
  Inhalt der Antwort wertet das Skript nicht aus.

Getestet
--------

20.11.2026 auf einer Gluon-x86-VM (26111816bro, Multi-Key) in `25_hvb`:
ohne Schlüssel kein Lauf und keine Ausgabe; mit Schlüssel in der
Domain-Datei liest `gluon.site` die URLs, der Startlauf meldete nach dem
ersten batman-Nachbarn (VPN) an `https://locator.ffnef.de/hvb/locate`, ein
`run.sh cron` direkt danach tat nichts. Den Paketbau selbst prüft erst der
Testbau.

Lizenz
------

BSD-3-Clause, siehe [LICENSE](LICENSE).

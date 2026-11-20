neanderfunk-locate (Prototyp)
=============================

Scannt die WLANs in der Umgebung eines Knotens und meldet sie per POST an den
Locator (`locator.ffnef.de`). Hängt ein Knoten in `25_hvb` per LAN-Mesh an
genau einer anderen Domain, schaltet er selbst dorthin um. Konzept und Format:
[docs/konzept-hvb-ortung.md](../docs/konzept-hvb-ortung.md), Abschnitt 4.3.

**Stand: Prototyp.** Es gibt noch kein Makefile, das Skript kommt nicht ins
Image. Es wird für Testdaten von Hand auf Testknoten kopiert und dort
aufgerufen. Die Bindung an die Domain (`neanderfunk_locate` in der
Domain-Datei von `25_hvb`) und die tägliche Wiederholung kommen erst mit dem
Paket.

Aufruf
------

```sh
neanderfunk-locate        # scannen und melden
neanderfunk-locate -n     # nur scannen, JSON ausgeben, nichts senden
neanderfunk-locate -u URL # an eine andere URL melden
neanderfunk-locate -n -a 25_hvb  # Trockenlauf, als stünde der Knoten in 25_hvb
```

Ergebnis steht im Syslog (`logread | grep neanderfunk-locate`).

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
- **Umschalten:** Steht der Knoten in `25_hvb` und hängen am Kabel Nachbarn
  genau einer anderen Domain, die im Image steht, meldet das Skript
  `lan_switch` und ruft danach `gluon-switch-domain` auf (Neustart), auch wenn
  die Meldung nicht ankam. Mehrere fremde Domains oder eine, die das Image
  nicht kennt: kein Umschalten. Mit `-n` schaltet das Skript nie um; `-a`
  gibt es nur zusammen mit `-n`.
- **Koordinaten:** aus `gluon-node-info`, falls eingetragen, auch wenn sie
  nicht veröffentlicht sind.
- **Senden:** zuerst `https`, wenn `libustream-ssl` da ist, sonst `http`.
  User-Agent ist `neanderfunk-locate/<version>`. Der Locator antwortet mit
  200. Das Skript nimmt trotzdem jede 2xx-Antwort an: `uclient-fetch` zählt
  nur 200 als Erfolg und meldet etwa 202 als „HTTP error 202“ mit rc 8. Den
  Inhalt der Antwort wertet das Skript nicht aus.

Lizenz
------

BSD-3-Clause, siehe [LICENSE](LICENSE).

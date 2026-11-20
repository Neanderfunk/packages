neanderfunk-locate (Prototyp)
=============================

Scannt die WLANs in der Umgebung eines Knotens und meldet sie per POST an den
Locator (`locator.ffnef.de`). Konzept und Format:
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
- **Koordinaten:** aus `gluon-node-info`, falls eingetragen, auch wenn sie
  nicht veröffentlicht sind.
- **Senden:** zuerst `https`, wenn `libustream-ssl` da ist, sonst `http`.
  User-Agent ist `neanderfunk-locate/<version>`. Jede 2xx-Antwort gilt als
  angekommen: `uclient-fetch` nimmt nur 200 als Erfolg und meldet den 202
  des Locators als „HTTP error 202“ mit rc 8. Den Inhalt der Antwort wertet
  das Skript nicht aus.

Lizenz
------

BSD-3-Clause, siehe [LICENSE](LICENSE).

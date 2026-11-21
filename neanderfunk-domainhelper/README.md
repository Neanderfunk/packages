neanderfunk-domainhelper
========================

Hilfen rund um die Domain eines Knotens. Das Paket ist als Sammelstelle
gedacht, weitere Teile können dazukommen. Bisher gibt es einen:

**locate: Lokator und Abschleppdienst für die Halteverbots-Defaultdomain.**
Scannt die WLANs in der Umgebung eines Knotens und meldet sie per POST an den
Locator (`locator.ffnef.de`). Hängt ein Knoten per LAN-Mesh an genau einer
anderen Domain, schaltet er selbst dorthin um. Konzept und Format:
[docs/konzept-hvb-ortung.md](../docs/konzept-hvb-ortung.md), Abschnitte 4.2
und 4.3.

**Stand 0.3 (20.11.2026):** erstes Paket für eine Testfirmware. Bis 0.2
hieß es `neanderfunk-hvblocator`, davor als Prototyp `neanderfunk-locate`.

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
  endet `locate.sh` nach einem `jsonfilter`, ohne Lua zu starten.
- Nicht im Setup-Mode, nie zwei Läufe gleichzeitig (Sperre in `/tmp`).

Aufruf
------

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
  User-Agent ist `neanderfunk-domainhelper/<version>`. Der Locator antwortet mit
  200. Das Skript nimmt trotzdem jede 2xx-Antwort an: `uclient-fetch` zählt
  nur 200 als Erfolg und meldet etwa 202 als „HTTP error 202“ mit rc 8. Den
  Inhalt der Antwort wertet das Skript nicht aus.

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

Lizenz
------

BSD-3-Clause, siehe [LICENSE](LICENSE).

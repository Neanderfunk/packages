Domainwechsel: Testmatrix
=========================

Übersicht, wann ein Knoten mit der Multidomain-Firmware von selbst Domain
oder Kanal wechselt, wer das auslöst und was davon getestet ist. Stand
neanderfunk-domainhelper 0.9, nodeplacer 0.1-r2, 21.11.2026.
Hintergrund: [entwurf-automesh.md](entwurf-automesh.md) (Abschnitt 0 und
Feature-Tabelle 17), [konzept-hvb-ortung.md](konzept-hvb-ortung.md).

Achsen
------

- **Ausgang:** A = Knoten steht in `25_hvb` (Domain mit Ortung,
  „Halteverbot“), B = Knoten steht in einer anderen Domain (Orts-, LVR-
  oder `21_dias`).
- **Attraktor:** wohin es ihn zieht. LAN-Mesh = Nachbar am Kabel
  (batman über `mesh_other`/`gluon_wired`), WLAN-Mesh = 802.11s-Mesh-Punkt
  einer Domain dieser Firmware (Mesh-ID aus `/lib/gluon/domains/*.json`).
- **Uplink:** VPN = eigener VPN-Uplink, sieht ein Gateway. Insel = weder
  VPN noch ein Gateway über Nachbarn (`batctl gwl` leer).

Matrix
------

| # | Ausgang | Attraktor | mit VPN | Insel |
|---|---|---|---|---|
| A1 | 25_hvb | LAN-Mesh einer anderen Domain | `bridge` erkennt den Nachbarn und startet `locate`, das meldet und schaltet per `lan_switch` sofort um (Neustart). Beim Boot meldet `locate` ohnehin. **getestet** (M60, 85 s nach Boot) | Ohne VXLAN verschmelzen die Wolken am Kabel, der Knoten sieht das Gateway der anderen Domain, ist also keine Insel. `lan_switch` wie links, auch wenn die Meldung nicht ankommt. **getestet** (NWA50AX Pro am Kabel von 18_nefuk, zurück bei 90 s Laufzeit) |
| A2 | 25_hvb | WLAN-Mesh einer anderen Domain | `locate` meldet (Boot, dann täglich), Mapserver entscheidet über E11 (ein Mesh-Punkt ab -75 dBm oder zwei) und E12 (nur mit eigenem VPN, keinen Knoten ohne VPN abschneiden), Manifest, nodeplacer schaltet zur vollen Stunde (Minute je Knoten). **getestet** (M60, etwa 50 min) | Keine Meldung möglich. `island` Fall b nach 600 min (+0 bis 15 min Versatz): Domain und Kanal, Neustart. *nur Trockenlauf aus 25_hvb* |
| A3 | 25_hvb | WLAN-Mesh von 25_hvb, anderer Kanal | nichts (braucht kein Mesh) | `island` Fall a nach 60 min: Kanal. Danach hängt er am HVB-Knoten mit VPN; zieht der um, folgt er über A2-Insel. *wie B3* |
| A4 | 25_hvb | keiner | `locate` meldet, Mapserver ortet über die WLAN-Umgebung (E10) oder per Handeintrag, sonst bleibt er | nichts; linkcheck startet einmal neu, danach Offline-SSID |
| B1 | andere | LAN-Mesh einer anderen Domain | `bridge` trennt nach 80 s Frist per ebtables, bis zum Neustart, aber nur wenn die Gegenseite selbst einen Uplink hat; sonst nur Meldung (Banner, Syslog). Kein Domainwechsel. **getestet** mit vorgetäuschter Domain (`test_domain`), keine echte Zwei-Domain-Brücke | Wolken verschmelzen, der Knoten nutzt die Gateways der anderen Domain und bleibt in seiner (Mischbetrieb, Domainbrücke auf der Karte). `bridge` meldet und lässt die Brücke stehen. **getestet** (NWA50AX Pro in 21_dias am Kabel von 18_nefuk: Gateway und öffentliches Präfix von 18_nefuk). **offen:** Domainwechsel am Kabel ohne VPN (#9) |
| B1h | andere | LAN-Mesh zu einem Knoten in 25_hvb | `bridge` trennt nicht (0.9), der HVB-Knoten kommt per `lan_switch` herüber (A1). *nicht getestet* | wie links, der HVB-Knoten kommt herüber |
| B2 | andere | WLAN-Mesh einer anderen Domain | nichts: verschiedene Mesh-IDs verbinden sich nie, gewollt | `island` Fall b nach 600 min (+Versatz): Laufzeit-Deltas verwerfen, `gluon-switch-domain --no-reboot`, Kanal, Neustart. Kanal fest nur, wenn nicht Standard der neuen Domain. **getestet** (WS-AP3825i, 21_dias nach 10_wlf, Wartezeiten auf dem Gerät auf 5/10 min verkürzt: nach 11 min Neustart, danach je Band 2 Mesh-Nachbarn in 10_wlf; keine Offline-SSID im Flash) |
| B3 | andere | WLAN-Mesh der eigenen Domain, anderer Kanal (auch `auto`) | nichts: getrennte Kanäle sind gewollt | `island` Fall a nach 60 min (+Versatz): nur der Kanal, fest nur, wenn nicht Standard. **getestet** (M60, nach 63 min Kanal 1 auf 9, Gateway 1 min später) |
| B4 | andere | keiner | nichts | nichts; linkcheck startet einmal neu, danach Offline-SSID |
| X | beide | Attraktor sendet selbst die Offline-SSID | – | kein Wechsel: Fällt das Internet für eine ganze Wolke aus, bleibt jeder, wo er ist. *Trockenlauf mit nachgestellter Scanliste* |

Regeln, die für alle Fälle gelten
---------------------------------

- **Nur Domains dieser Firmware.** Nachbar-Communities sind kein Ziel
  (Sperrliste vertagt, #16/#17).
- **Nie nach 25_hvb.** Weder `island` noch `bridge` ziehen einen Knoten in
  eine Domain mit Ortung.
- **Vorrang bei `island`:** eigene Domain vor fremder, dann das stärkste
  Signal; unter -80 dBm nie. Nur Bänder mit Mesh-Rolle, 5 GHz nicht im
  Outdoor-Modus.
- **Takt und Versatz:** `bridge` und `island` laufen alle 91 s; `island`
  scannt höchstens alle 5 min; 0 bis 15 min Versatz je Knoten aus der MAC.
  Nach einem Wechsel frühestens 6 h später der nächste.
- **Kein Hindernis:** aktives LAN-Mesh oder weitere Knoten in der Wolke
  verhindern `island` nicht; maßgeblich ist nur „kein Gateway“.
- **Zusammen mit linkcheck:** Verliert ein Knoten den Uplink zur Laufzeit,
  startet linkcheck ihn einmal neu (etwa 20 bis 30 min). Die Wartezeit von
  `island` zählt ab dem Boot.
- **Flash:** Domainwechsel schreiben in den Flash (Ausnahme vom
  Grundsatz). Kanalwechsel über `channel` ebenfalls, aber nur die
  Kanaleinträge.

Zum Überdenken
--------------

- **B1-Insel (#9):** Soll ein Knoten ohne VPN, der am Kabel einer anderen
  Domain hängt, selbst wechseln? Heute bleibt er im Mischbetrieb. Vorschlag
  im Entwurf: ja, höchstens ein Wechsel je Tag.
- **B1 mit VPN, Gegenseite ohne Uplink:** Die Brücke bleibt stehen. Mit
  #9 würde die Gegenseite herüberwechseln und das Problem löste sich von
  ihrer Seite.
- **WAN-Sperre (#39):** „VPN-Knoten mit WAN-Link nie wechseln“ ist
  vertagt; Gegenfall ist der gekündigte Anschluss mit weiterlaufendem
  Router.
- **Wartezeiten 60/600 min:** A2-Insel und B2 wechseln erst nach 10 h;
  bis dahin läuft der Knoten mit Offline-SSID.
- **Kanäle beim Domainwechsel:** Jeder Wechsel (`lan_switch`, nodeplacer,
  `island` b) setzt die Kanäle auf den Standard der neuen Domain, auch bei
  `preserve_channels=1`; nur `island` b schreibt danach den gefundenen
  Kanal. Ein Knoten mit geplantem Kanal verliert ihn so bei A1 (gesehen:
  8/auto wurde 9/48).
- **Nach Rückkehr des Uplinks** bleibt ein festgeschriebener Kanal stehen;
  zurückstellen nur von Hand.

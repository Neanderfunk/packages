Multi-Domain-Umstellung: was sich für die Feed-Pakete ändert
============================================================

Checkliste für die Abnahme der Umstellung von je einer Firmware pro Domain
(Single-Domain) auf ein Image für alle Domains (Multi-Domain, Gluon 2025.1,
Feed-Zweig `v2025.1.x-next`). Sie sammelt alles, was beim Umbau an den Paketen
dieses Feeds und an den Gluon-Patches aus `gluon-patches-packages` aufgefallen
ist, und was bei der finalen Abnahme am Gerät zu prüfen ist. Was den Bau
selbst betrifft (Site-Generator, Domain-Dateien, Autoupdater, Signaturen),
steht nur dort, wo es ein Paket berührt.

Angelegt am 18.11.2026 auf Wunsch adorfer. Beim Abhaken Datum und Image
dazuschreiben.

Die verbindliche Gesamtabnahme ist Test G (G1 bis G10) in der
Release-Abnahme des Bausystems (`docs/release-abnahme.md` im internen
Buildsystem-Repo). Diese Liste ist die paketseitige Detailliste dazu: Abschnitt
1 gehört zu G1, 2 zu G2/G3, 3 zu G7, 4 zu G4/G6/G10 (Domainwechsel im Betrieb), 5 zu G9, 6 zu G5. Ein
Haken hier ersetzt keinen in Test G.

Grundregeln, die überall gelten
-------------------------------

- **Wo ein Wert steht.** Im Multi-Image liegt die Site in `/lib/gluon/site.json`
  und jede Domain in `/lib/gluon/domains/<code>.json`. Domain-Werte stehen
  nicht in `site.json`. Wer Site-Werte liest, muss das über `gluon.site` tun
  (Lua; führt Site und aktive Domain zusammen) oder beide Dateien selbst
  zusammenführen, die Domain zuerst.
- **check_site.** `in_site(...)` verbietet einen Schlüssel in den Domains,
  `in_domain(...)` verbietet ihn im Multi-Image in der site.conf. Ohne beides
  darf er an beiden Stellen stehen, aber Gluon führt Listen elementweise
  zusammen: eine Liste gehört ganz an eine Stelle.
- **Domainwechsel.** `gluon-switch-domain` setzt `gluon.core.switch_domain`;
  beim nächsten `gluon-reconfigure` übernimmt `005-set-domain` den Wert. Alles,
  was Upgrade-Skripte aus der Domain ableiten, folgt dem Wechsel nur, wenn das
  Skript bei jedem Lauf neu schreibt.
- **Domain-Code.** Im Multi-Image heißen die Domains `<nr>_<kürzel>`
  (`21_dias`), nicht `nef-21_dias` wie der frühere `site_code`. `site_code` ist
  für alle Domains `ffnef`.

Prüfliste
---------

### 1. Upgrade von Single-Domain: Domain erkennen

Paket `neanderfunk-domain-from-legacy` (`004`, vor Gluons `005-set-domain`).

- Erkennung: Mesh-ID aus `wireless_gluon-old`, sonst `next_node`-IPv4 aus
  `network_gluon-old`, feste Altadressen (`next_node_ip4_fest`) vor
  mehrdeutigen; nichts erkannt: `default_domain` (`25_hvb`).
- Ergebnis dauerhaft in `uci show gluon.domain_from_legacy` (`source`,
  `domain`, `log`), Logzeilen über `/dev/kmsg` bis zum nächsten Neustart in
  `logread | grep neanderfunk-domain` (logger ging vor logd verloren).
- [x] Testfälle auf einer VM bestanden (12 Fälle, 18.10.2026); Offline-Test 12
      Fälle (16.11.2026).
- [x] Ganzer Ablauf `001` -> `004` -> `005` in einem echten Multi-Image:
      Labor-VM x86-64, sysupgrade von `26101610sta` (Single, 21_dias) auf
      `26111803bro` (Multi), 18.11.2026: erkannt über `next_node` 10.51.64.1,
      Domain `21_dias`, Logzeile vorhanden; danach next_node 10.21.0.1/16,
      hostname und mesh_vpn übernommen, LAN-Rolle client, nodeinfo
      `site_code` ffnef, `domain_code` 21_dias.
- [x] Je ein Knoten mit WLAN-Mesh und einer ohne WLAN (x86/ERX). Testknoten
      von `26101610sta` auf `26111822bro`, 19.11.2026: M60 b483, Xiaomi 4A
      33f1, 1043v2 4402 und MR90X e2a9 über `mesh_id:dias-mesh`, ERX über
      `next_node:10.51.64.1`, alle `21_dias`.
- [ ] Ein Knoten mit einer der festen Altadressen (`10.31.0.1`, `10.40.0.1`).
      Kein Testknoten in diesen Altdomains; offen, bis ein Feldknoten von
      dort updatet (`uci show gluon.domain_from_legacy`).
- [x] Neuinstallation: Domain `25_hvb`. Frisch geflashte Labor-VM
      (26111810bro, 18.11.2026): Wizard mit `25_hvb` vorbelegt, Vorgabename
      `HVB-x86-1101` (siehe 2.).

### 2. Config-Mode: Domain-Auswahl

Gluon-Feature `config-mode-domain-select`, dazu Patch
`config-mode/domain-select-current` (gluon-patches-packages `e3b12e6`).

- Gluon ließ die aktuelle Domain weg, wenn sie versteckt ist und der Knoten
  noch nicht konfiguriert war. Ein frischer Knoten in `25_hvb` bekam keine
  Vorbelegung, Speichern verschob ihn in den ersten Eintrag nach Namen (Fehler
  aus 2023.2.6). Jetzt immer gelistet und vorbelegt.
- [x] Offline-Test 5 Fälle bestanden (18.11.2026).
- [x] Im Browser: frisch geflasht steht „Halteverbot ...“ vorbelegt; der lange
      Name ist im Dropdown lesbar; andere versteckte Domains fehlen.
      26111810bro, 18.11.2026: 48 Domains, vorbelegt `25_hvb`; versteckt ist
      im Image nur `25_hvb`. Im geschlossenen Feld ist der Name nach „bitte
      eine andere Domain wählen, sonst“ abgeschnitten, der Kern bleibt lesbar.
      Mit `configured=1` ist die aktuelle Domain (`21_dias`) vorbelegt.
- [x] Knoten mit erkannter Altdomain: diese ist vorbelegt.
- [x] Speichern ohne Änderung lässt die Domain, wie sie ist.
- Beide 26111810bro, 18.11.2026 (Buildsystem): t1.sh Single 21_dias auf
  Multi, dann `configured=0`, Setup-Modus. Vorbelegt 21_dias; hin und
  zurück umgeschaltet und gespeichert: 21_dias, Name, Position, Mesh-VPN und
  next_node 10.21.0.1 unverändert.
- [x] Bei `configured=0` tauscht der Präfix-Schritt auch bei einem eigenen
  Namen mit Domain-Präfix (`dias-mt-labor` wird beim Umschalten auf 06_han
  `HAN-mt-labor`). Gewollt (adorfer 18.11.2026): solange das Setup nicht
  einmal durchgelaufen ist, wandert das Domain-Präfix mit.

Beschriftung der Auswahl, Patch `config-mode/domain-select-code`
(gluon-patches-packages `99e35d7`, Wunsch adorfer 19.11.2026): Code vor dem
Namen („01_vel: Velbert“), sortiert nach Code. Anlass: Im Wizard heißen
sieben Domains „LVR-HPH“ (M60 bb31, 26111822bro).

- [x] Offline-Test (Beschriftung, Reihenfolge), Kette mit
      `domain-select-current` auf Gluon `0ad3ad5` zweimal angewendet.
- [ ] Im Browser mit dem nächsten Multi-Image.
- [x] Eindeutige Namen für die LVR-Domains, gesetzt in FirmwareConfigs
      `edd3276` (19.11.2026): `31_lvrno` „LVR-HPH NordOst“, `32_lvrnw`
      „LVR-HPH NordWest“, `33_lvrmo` „LVR-HPH MitteOst“, `34_lvrmw`
      „LVR-HPH MitteWest“, `35_lvrso` „LVR-HPH SüdOst“, `36_lvrsw`
      „LVR-HPH SüdWest“; `11_lvr` bleibt „LVR-HPH“.
  - [ ] adorfer bestätigt `36_lvrsw` = SüdWest (der Langname in den
        Stammdaten sagt noch SüdOst).

Karte im Wizard, Patch `config-mode/geo-location-domain-map`
(gluon-patches-packages `5d52c40`), Domain-Schlüssel `neanderfunk_map`
(`in_domain`; ohne Eintrag gilt der Site-Ausschnitt):

- [x] Offline-Test der Domainwerte (10 Prüfungen), check_site mit Gluons
      check-site, JS-Logik simuliert (18.11.2026).
- [x] Im Browser: Karte startet auf der aktuellen Domain; Umschalten der
      Domain-Auswahl verschiebt den Ausschnitt. 26111810bro, 18.11.2026:
      frisch Site-Ausschnitt (`25_hvb` ohne Eintrag), `06_han` z13, `40_sim`
      z12, `21_dias` z5; mit `configured=1` Start auf `21_dias`.
- [x] Nach Klick in die Karte oder eingetippten Koordinaten, und bei einem
      Knoten mit Position: Umschalten verschiebt nichts, Koordinaten bleiben.
      Klick und Tippen bestanden (26111810bro, 18.11.2026); Knoten mit
      gespeicherter Position: Start dort mit Zoom 18, Umschalten verschiebt
      nichts (Buildsystem, 18.11.2026).

Vorgabe-Hostname (`neanderfunk-default-hostname`, Präfix je Domain):

- [x] a) frischer Knoten: Vorgabename mit dem Präfix von `25_hvb`, Domain
      umschalten, Präfix im Namensfeld tauscht, gespeicherter Name trägt das
      neue Präfix.
- [x] b) dasselbe ohne JavaScript, Tausch beim Speichern.
- [x] c) selbst gewählter Name ohne bekanntes Präfix bleibt.
- [x] d) Setup-Modus später erneut (`configured=1`), Domain wechseln, Name
      bleibt.
- [x] e) Knoten aus der Single-Firmware (erkannte Altdomain) behält seinen
      Namen.
- a bis d: Labor-VM x86-64, 26111810bro, 18.11.2026, je frisch geflasht
  außer d. a) `HVB-x86-1101`, im Browser `HAN-`/`SIM-`/`dias-`, auch mit
  bearbeiteter Mitte (`SIM-x86-Kirchstr-1101`), gespeichert `dias-x86-1101`.
  b) Formular ohne Handler der Seite abgeschickt, gespeichert
  `dias-x86-1101`. c) `Testknoten-Kirchstrasse` bleibt im Browser und
  gespeichert. d) nach a erneut in den Setup-Modus, auf `06_han` (Mesh-VPN
  aus) gespeichert: Name `dias-x86-1101` bleibt. e) mit t1.sh (Single
  `26101610sta` auf Multi `26111803bro`): hostname übernommen.

Realer Test im Config-Mode (echte Geräte, nicht Labor-VM; adorfer):

- [ ] Bestandsknoten: ein Knoten aus dem Feld bzw. mit Single-Firmware, auf
      das Multi-Image gebracht, dann in den Config-Mode (Reset-Knopf etwa
      10 s). Vorbelegt sind die erkannte Domain, Name, Position und Mesh-VPN.
      Speichern ändert nichts davon.
- [ ] Neuer Knoten: frisch mit dem Multi-Image geflasht. Wizard mit `25_hvb`
      vorbelegt; Domain wählen, Karte, Vorgabename mit Präfix, speichern;
      danach in der gewählten Domain online.
      Erster Teil bestanden: D-Link M60 bb31, frisch mit 26111822bro,
      19.11.2026 (Screenshot adorfer). Vorgabename `HVB-M60-bb31`, Domain
      „Halteverbot ...“ vorbelegt, Kontakt leer. Offen: Domain wählen,
      speichern, online in der gewählten Domain.

### 3. Anzeige der Domain

- Statusseite: Zeile „Domain“ zeigt `Anzeigename (Code)`, Patch
  `status-page/statuspage-domaincode` (gluon-patches-packages `e2dc413`). Ohne
  Domains fehlt die Zeile wie bisher.
- Login (`nodestatus`, Paket `neanderfunk-banner`, Feed `f4ea5b5`): Zeile
  `Domain  ffnef / 21_dias  NP:1   <Name>`. `site_name` ist im Multi-Image für
  alle Domains „Freifunk im Neanderland“, deshalb jetzt der Name aus
  `domain_names`.
- Login zusätzlich mit DHCP-Zeile unter Gateway/Clients (ddhcpd läuft oder
  Lernphase, Blöcke, Leases), `nodeinfo` ausführlicher (Feed `80b1d4e`).
- [x] Statusseite und Login auf einem Testknoten mit dem neuen Image.
      26111822bro, 19.11.2026, b483/33f1/4402/ERX/e2a9: Login
      `Domain  ffnef / 21_dias  NP:1   Neanderfunk Diaspora`, Statusseite
      „Neanderfunk Diaspora (21_dias)“.
- [x] Weitere Stellen mit `site_name` (26111822bro, 19.11.2026, im Image
      gesucht): Kopf des Config-Mode (`layout.html`), Zeile „Site“ der
      Statusseite und `gluon-info` („Site“, daneben „Domain: 21_dias“). Alle
      zeigen ihn als Namen der Site, nicht als Domain; das ist richtig so.

### 4. Werte, die je Domain verschieden sind

| Schlüssel | Paket | check_site | Liest über | Stand |
| --- | --- | --- | --- | --- |
| `ddhcpd.*` | neanderfunk-ddhcpd | `in_domain` | `gluon.site`, bei jedem reconfigure | in allen 48 Domains an |
| `next_node.ip4` | neanderfunk-ddhcpd, Statusseite | `in_domain` | `gluon.site` | |
| `neanderfunk_hostname_prefix` | neanderfunk-default-hostname | `in_domain` | site.json + Domain-Datei selbst zusammengeführt | in allen 48 Domains |
| `neanderfunk_map` | Patch geo-location-domain-map | `in_domain` | Domain-Dateien direkt (Auswahl), `gluon.site` (Start) | |
| `nodeplacer.mirrors` | neanderfunk-nodeplacer | `in_domain` seit Feed `b32a1b4` | `gluon.site` in `510-nodeplacer` | in allen 48 Domains mit ULA-Mirror |
| `neanderfunk_legacy.*` | neanderfunk-domain-from-legacy | keins | Domain-Dateien direkt | |
| `prefix6` | neanderfunk-hotfix (`br_client_ipv6`) | Gluon: `in_domain` | `nf_site_get` (bis 18.11.2026 `site.json`, lief im Multi-Image nie) | behoben, siehe 5. |
| ddhcpd-Bereich | neanderfunk-respondd (`clients_ipv4`) | - | site.json + Domain-Datei, Domain zuerst | |

- [x] ddhcpd (`range` 10.NN.128.0/19, `client_prefix4` 10.NN.0.0/16, `router`
      .0.2, `dns` .0.1 und zwei externe, `block_size` 4, ohne
      `foreign_prefix4`, also Vorgabe `client_prefix4`): auf einem Testknoten
      läuft der Daemon, Statusseite „läuft“, `ddhcpdctl -m` mit Blöcken.
      Labor-VM `26111803bro` 18.11.2026: Daemon läuft, `block_size_pow` 4,
      `block_network` 10.21.128.0/19, `foreign_network` 10.21.0.0/16; offen
      noch Statusseite und `ddhcpdctl -m` am WLAN-Testknoten 33f1.
      Im Feld 18.11.2026: Statusseite 4402 (26111810bro) „läuft“, Blöcke
      eigen 1, fremd 1, frei 510. Client-Test auf kollektor6 (Namespace
      `ffclient` an ovh-kollektor-839d, 26111816bro): vorher Kea
      (`10.21.1.0` von 10.21.0.5), nach dem Update ab 21:23 in 38 von 40
      Läufen ddhcpd-Lease `10.21.148.80` von 10.21.0.1, Router 10.21.0.2,
      Ping v4/v6 und HTTPS v4/v6 in Ordnung (die zwei Ausfälle: Neustart).
      WLAN-Testknoten 33f1 (26111822bro, 19.11.2026): `ddhcpdctl -m` mit
      512 Blöcken, eigen 1, fremd 14; Login-Zeile „ddhcpd laeuft“ auf allen
      neun erreichbaren Testknoten.
- Nebenbefund Client-Test (18./19.11.2026): Router-Ping alle 5 bis 7 Minuten
  mit Spitzen um 270 ms. Ursache war das DAT von batman-adv auf den
  Supernodes (abgelaufener Eintrag, danach ARP-Broadcast). DAT ist seit
  19.11.2026 auf allen Supernodes aus; seitdem keine Spitzen mehr, auch in
  den anderen Domänen (ARP-Mitschnitt auf dem Supernode). Kein Thema der
  Firmware.
- [ ] Beim Booten meldet ddhcpd in den ersten Minuten 1 bis 3 Fehler
      (`send_packet_mcast(...): Operation not permitted`, `Error in epoll`),
      auf dem Xiaomi 4A einmal mit Neustart des Daemons (26111822bro,
      19.11.2026: NWA55AXE, COVR-X1860, Xiaomi 4A). Danach ruhig. Vermutlich
      Start vor dem Mesh-Interface; klein, ansehen.
- [ ] Kea vergibt in keiner Domain aus 10.NN.128.0/19 (laut adorfer 17.11.2026
      auf allen Supernodes umgesetzt); Clients mit Kea-Adresse bekommen kein
      NAK von ddhcpd. Prüfung auf Seite der Supernodes.
- Domainwechsel von Hand: Befehl `domainswitch` (neanderfunk-banner, Feed
  `355d1b6`, FirmwareConfigs `58ef58a`). Ohne Argument alle Domains mit Code
  und Name, sonst Wechsel per Code, Nummer, Kürzel oder Name mit Rückfrage
  (`-f` ohne, `-n` nur zeigen), dann `gluon-switch-domain` (Neustart,
  `gluon-reconfigure` beim Booten). Auf b483 mit Attrappe getestet
  (19.11.2026), im Image ab dem nächsten Multi-Bau.
  - [ ] Im Image: `domainswitch` und `domainswitch 06 -n` am Testknoten.
- [ ] Nach einem Domainwechsel auf dem Testknoten: ddhcpd-Bereich,
      next_node-Adresse und nodeplacer-Mirrors (`uci show nodeplacer`) sind die
      der neuen Domain. Nur im Labor oder mit Mesh-VPN aus, Testknoten
      gehören sonst in `21_dias`.
- [ ] nodeplacer im Multi-Image: Wechsel per Manifest (`method domain`,
      `gluon-switch-domain`) an einem Testknoten (adorfer).
- [x] Vorgabe-Hostname neuer Knoten mit dem Präfix der gewählten Domain:
      siehe 2., Fall a (gespeichert `dias-x86-1101` nach Wahl von `21_dias`).

### 5. Pakete, die site.json direkt lesen

Im Multi-Image sehen sie nur Site-Werte. Bestandsaufnahme 18.11.2026:

- **neanderfunk-hotfix `healthcheck.sh`, Check `br_client_ipv6`:** las
  `prefix6` aus `site.json`. Im Multi-Domain-Image legt Gluon `prefix6`
  (`in_domain`) nur in die Domain-Datei: der Check lief dort still nicht
  (gesehen an zwei Testknoten mit Multi-Domain-Testimages; eines hiess wegen
  eines festen Namens im Bausystem `26101610sta` wie das Produktiv-stable).
  Single-Domain-Images haben `prefix6` in `site.json`, dort lief er. **Behoben 18.11.2026** (Feed `afe4112`/`18465ad`): neue
  Funktion `nf_site_get` in neanderfunk-common (`/lib/gluon/neanderfunk/site.sh`),
  Domain vor Site.
  - [x] Mit dem neuen Image: `br_client_ipv6` läuft wieder (kein Fehlneustart,
        `/tmp/hotfix.brclient-noaddr` bleibt leer, solange br-client seine
        ULA hat). 26111822bro, 19.11.2026, b483 und 4402 (Check nicht von
        Hand gestartet, nur seine Eingaben gelesen): `nf_site_get` liefert
        `fd66:666e:6566:6415::/64`, br-client hat eine Adresse daraus, kein
        Marker `noprefix` oder `noaddr`, healthcheck im Cron alle 7 Minuten.
- neanderfunk-hotfix `500`, neanderfunk-linkcheck `500`, neanderfunk-common
  `490`: lasen `hotfix.*`, `linkcheck.*`, `neanderfunk.*` aus `site.json`;
  seit 18.11.2026 ebenfalls über `nf_site_get`, ein Wert in der Domain
  würde also auch wirken.
  - [x] Im Multi-Image stehen sie nicht in Domain-Dateien. 26111822bro,
    19.11.2026, fünf Testknoten: in keiner der 48 Domain-Dateien `hotfix`,
    `linkcheck` oder `neanderfunk`; `neanderfunk` in der Site, `hotfix` und
    `linkcheck` gar nicht gesetzt (Vorgaben greifen).
- neanderfunk-respondd: führt Site und Domain selbst zusammen, passt.
- neanderfunk-default-hostname: liest Site und alle Domain-Dateien, passt.
- Daueraufgabe: bei jedem neuen Paket oder Skript `grep site.json` und diese
  Liste nachziehen. Zuletzt `domainswitch` (19.11.2026): liest nur die
  Domain-Dateien.

### 6. Was nur Single-Domain betrifft

- neanderfunk-node-whisperer `patches/0001`: fehlende Domain ist kein Fehler.
  Im Multi-Image gibt es immer eine Domain; die Information `domain` meldet
  der Daemon dort wieder (FirmwareConfigs `ae07154`).
  - Knotenseite geprüft (33f1, 26111822bro, 19.11.2026): Daemon läuft,
    `information` enthält `domain`, Interfaces `client0`/`client1`.
  - [ ] NodeMonitor-App zeigt am Testknoten die Domain (vom Handy aus,
        adorfer).
- Statusseite ohne Domain-Zeile, `nodestatus` mit `site_name`: unverändert.

### 7. Site-weite Werte, die für alle Domains gleich bleiben müssen

Mit `in_site` abgesichert: `setup_mode.*` (setup-mode, setup-wifi),
`wifi_blackout.*`, `nodeplacer.good_signatures`, `pubkeys`, `disable`,
`config_mode`. Ohne Absicherung, aber nur in der Site gelesen: `hotfix.*`,
`linkcheck.*`, `neanderfunk.*` (siehe 5.). `ssid_changer.*` über
`gluon.site`, steht in der Site.

- [x] Gluons check_site läuft im Multi-Bau ohne Fehler (sonst bricht der Bau
      ab). Die Multi-Bauten `26111803bro` bis `26111822bro` sind durchgelaufen.

### 8. Zweige und Rückführung

- Alles oben liegt im Feed auf `v2025.1.x-next`. Auf `v2025.1.x` sind
  nodeplacer (`d2c00a2`) und node-whisperer (`c10217b`) gleich, aber
  `neanderfunk-domain-from-legacy` steht dort noch auf dem alten Stand (ohne
  `next_node_ip4_fest`, ohne kmsg/uci-Protokoll).
- [ ] Vor dem Wechsel der Produktion auf Multi-Domain: entscheiden, ob
      `v2025.1.x-next` nach `v2025.1.x` zurückgeführt wird oder next zur
      Produktionslinie wird; dann die Patch-Repos (`gluon-patches-packages`
      `v2025.1.x-next`) genauso. Stand 18.11.2026 (adorfer): eine
      Single-Domain-Firmware ist nicht mehr geplant, `v2025.1.x` nur noch
      Rückfall für den Notfall; die formale Entscheidung über die Zweige
      steht noch aus.

Stand der Punkte
----------------

Offen bei Anlage: 1 (echtes Image), 2 (Browser: Auswahl, Karte, Hostname), 3, 4 (Gerät), 5
(`br_client_ipv6` am Gerät, Code behoben), 6 (App), 8. Bestanden: Offline-Tests zu 1 und 2,
check_site-Probe zu `nodeplacer.mirrors` mit Gluons check-site.

Stand 19.11.2026 (Image `26111822bro` auf 17 Knoten, 15 in `21_dias`):

- Erledigt: 1 bis auf die festen Altadressen, 2 in Labor-VM und Browser, 3
  ganz, 5 ganz, 7. Aus 4: ddhcpd im Feld, Vorgabe-Hostname.
- Offen bei adorfer: realer Config-Mode-Test mit Bestandsknoten und neuem
  Knoten (2), nodeplacer-Wechsel per Manifest im Multi-Image (4),
  NodeMonitor-App am Handy (6), Entscheidung über die Zweige (8).
- Offen in diesem Feed: Domainwechsel am Testknoten mit Kontrolle von
  ddhcpd, next_node und Mirrors (4); `domainswitch` im Image (4); Fehler von
  ddhcpd beim Booten ansehen (4).
- Offen auf Seite der Supernodes: Kea außerhalb 10.NN.128.0/19 (4).
- Wartet auf einen Feldknoten: feste Altadressen (1).

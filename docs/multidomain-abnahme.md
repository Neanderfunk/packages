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

Die verbindliche Gesamtabnahme ist Test G (G1 bis G9) in der
Release-Abnahme des Bausystems (`docs/release-abnahme.md` im internen
Buildsystem-Repo). Diese Liste ist die paketseitige Detailliste dazu: Abschnitt
1 gehört zu G1, 2 zu G2/G3, 3 zu G7, 4 zu G4/G6, 5 zu G9, 6 zu G5. Ein
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
- [ ] Ganzer Ablauf `001` -> `004` -> `005` in einem echten Multi-Image:
      Single-Domain-Knoten per sysupgrade umstellen, danach `uci show
      gluon.domain_from_legacy` und `logread`. Offen seit 16.11.2026, erwartet
      etwa `source='next_node:10.51.64.1'`, `domain='21_dias'`.
- [ ] Je ein Knoten mit WLAN-Mesh, einer ohne WLAN (x86/ERX) und einer mit
      einer der festen Altadressen (`10.31.0.1`, `10.40.0.1`).
- [ ] Neuinstallation: kein Eintrag, Domain `25_hvb`.

### 2. Config-Mode: Domain-Auswahl

Gluon-Feature `config-mode-domain-select`, dazu Patch
`config-mode/domain-select-current` (gluon-patches-packages `e3b12e6`).

- Gluon ließ die aktuelle Domain weg, wenn sie versteckt ist und der Knoten
  noch nicht konfiguriert war. Ein frischer Knoten in `25_hvb` bekam keine
  Vorbelegung, Speichern verschob ihn in den ersten Eintrag nach Namen (Fehler
  aus 2023.2.6). Jetzt immer gelistet und vorbelegt.
- [x] Offline-Test 5 Fälle bestanden (18.11.2026).
- [ ] Im Browser: frisch geflasht steht „Halteverbot ...“ vorbelegt; der lange
      Name ist im Dropdown lesbar; andere versteckte Domains fehlen.
- [ ] Knoten mit erkannter Altdomain: diese ist vorbelegt.
- [ ] Speichern ohne Änderung lässt die Domain, wie sie ist.

Karte im Wizard, Patch `config-mode/geo-location-domain-map`
(gluon-patches-packages `5d52c40`), Domain-Schlüssel `neanderfunk_map`
(`in_domain`; ohne Eintrag gilt der Site-Ausschnitt):

- [x] Offline-Test der Domainwerte (10 Prüfungen), check_site mit Gluons
      check-site, JS-Logik simuliert (18.11.2026).
- [ ] Im Browser: Karte startet auf der aktuellen Domain; Umschalten der
      Domain-Auswahl verschiebt den Ausschnitt.
- [ ] Nach Klick in die Karte oder eingetippten Koordinaten, und bei einem
      Knoten mit Position: Umschalten verschiebt nichts, Koordinaten bleiben.

Vorgabe-Hostname (`neanderfunk-default-hostname`, Präfix je Domain):

- [ ] a) frischer Knoten: Vorgabename mit dem Präfix von `25_hvb`, Domain
      umschalten, Präfix im Namensfeld tauscht, gespeicherter Name trägt das
      neue Präfix.
- [ ] b) dasselbe ohne JavaScript, Tausch beim Speichern.
- [ ] c) selbst gewählter Name ohne bekanntes Präfix bleibt.
- [ ] d) Setup-Modus später erneut (`configured=1`), Domain wechseln, Name
      bleibt.
- [ ] e) Knoten aus der Single-Firmware (erkannte Altdomain) behält seinen
      Namen.

### 3. Anzeige der Domain

- Statusseite: Zeile „Domain“ zeigt `Anzeigename (Code)`, Patch
  `status-page/statuspage-domaincode` (gluon-patches-packages `e2dc413`). Ohne
  Domains fehlt die Zeile wie bisher.
- Login (`nodestatus`, Paket `neanderfunk-banner`, Feed `f4ea5b5`): Zeile
  `Domain  ffnef / 21_dias  NP:1   <Name>`. `site_name` ist im Multi-Image für
  alle Domains „Freifunk im Neanderland“, deshalb jetzt der Name aus
  `domain_names`.
- [ ] Statusseite und Login auf einem Testknoten mit dem neuen Image.
- [ ] Weitere Stellen, die `site_name` als Domainnamen zeigen (Config-Mode-
      Texte, Setup-Mode-Seiten): noch nicht durchgesehen.

### 4. Werte, die je Domain verschieden sind

| Schlüssel | Paket | check_site | Liest über | Stand |
| --- | --- | --- | --- | --- |
| `ddhcpd.*` | neanderfunk-ddhcpd | `in_domain` | `gluon.site`, bei jedem reconfigure | in allen 48 Domains an |
| `next_node.ip4` | neanderfunk-ddhcpd, Statusseite | `in_domain` | `gluon.site` | |
| `neanderfunk_hostname_prefix` | neanderfunk-default-hostname | `in_domain` | site.json + Domain-Datei selbst zusammengeführt | in allen 48 Domains |
| `neanderfunk_map` | Patch geo-location-domain-map | `in_domain` | Domain-Dateien direkt (Auswahl), `gluon.site` (Start) | |
| `nodeplacer.mirrors` | neanderfunk-nodeplacer | `in_domain` seit Feed `b32a1b4` | `gluon.site` in `510-nodeplacer` | in allen 48 Domains mit ULA-Mirror |
| `neanderfunk_legacy.*` | neanderfunk-domain-from-legacy | keins | Domain-Dateien direkt | |
| `prefix6` | neanderfunk-hotfix (`br_client_ipv6`) | Gluon: `in_domain` | `nf_site_get` (bis 18.11.2026 `site.json`, lief nie) | behoben, siehe 5. |
| ddhcpd-Bereich | neanderfunk-respondd (`clients_ipv4`) | - | site.json + Domain-Datei, Domain zuerst | |

- [ ] ddhcpd (`range` 10.NN.128.0/19, `client_prefix4` 10.NN.0.0/16, `router`
      .0.2, `dns` .0.1 und zwei externe, `block_size` 4, ohne
      `foreign_prefix4`, also Vorgabe `client_prefix4`): auf einem Testknoten
      läuft der Daemon, Statusseite „läuft“, `ddhcpdctl -m` mit Blöcken.
- [ ] Kea vergibt in keiner Domain aus 10.NN.128.0/19 (laut adorfer 17.11.2026
      auf allen Supernodes umgesetzt); Clients mit Kea-Adresse bekommen kein NAK von ddhcpd.
- [ ] Nach einem Domainwechsel auf dem Testknoten: ddhcpd-Bereich,
      next_node-Adresse und nodeplacer-Mirrors (`uci show nodeplacer`) sind die
      der neuen Domain.
- [ ] Vorgabe-Hostname neuer Knoten mit dem Präfix der gewählten Domain.

### 5. Pakete, die site.json direkt lesen

Im Multi-Image sehen sie nur Site-Werte. Bestandsaufnahme 18.11.2026:

- **neanderfunk-hotfix `healthcheck.sh`, Check `br_client_ipv6`:** las
  `prefix6` aus `site.json`. Gluon 2025.1 legt `prefix6` (`in_domain`) nur in
  die Domain-Datei, auch bei Images mit einer Domain: der Check lief auf allen
  2025.1-Knoten still nicht (gesehen an einem Multi- und einem
  2025.1-Testknoten). **Behoben 18.11.2026** (Feed `afe4112`/`18465ad`): neue
  Funktion `nf_site_get` in neanderfunk-common (`/lib/gluon/neanderfunk/site.sh`),
  Domain vor Site.
  - [ ] Mit dem neuen Image: `br_client_ipv6` läuft wieder (kein Fehlneustart,
        `/tmp/hotfix.brclient-noaddr` bleibt leer, solange br-client seine
        ULA hat).
- neanderfunk-hotfix `500`, neanderfunk-linkcheck `500`, neanderfunk-common
  `490`: lasen `hotfix.*`, `linkcheck.*`, `neanderfunk.*` aus `site.json`;
  seit 18.11.2026 ebenfalls über `nf_site_get`, ein Wert in der Domain
  würde also auch wirken.
  - [ ] Im Multi-Image stehen sie nicht in Domain-Dateien (sonst wirkungslos).
    Am Testknoten 21_dias: `neanderfunk` in der Site, `hotfix` und `linkcheck`
    gar nicht gesetzt (Vorgaben greifen).
- neanderfunk-respondd: führt Site und Domain selbst zusammen, passt.
- neanderfunk-default-hostname: liest Site und alle Domain-Dateien, passt.
- [ ] Bei jedem neuen Paket oder Skript: `grep site.json` und diese Liste
      nachziehen.

### 6. Was nur Single-Domain betrifft

- neanderfunk-node-whisperer `patches/0001`: fehlende Domain ist kein Fehler.
  Im Multi-Image gibt es immer eine Domain; die Information `domain` meldet
  der Daemon dort wieder (FirmwareConfigs `ae07154`).
  - [ ] NodeMonitor-App zeigt am Testknoten die Domain.
- Statusseite ohne Domain-Zeile, `nodestatus` mit `site_name`: unverändert.

### 7. Site-weite Werte, die für alle Domains gleich bleiben müssen

Mit `in_site` abgesichert: `setup_mode.*` (setup-mode, setup-wifi),
`wifi_blackout.*`, `nodeplacer.good_signatures`, `pubkeys`, `disable`,
`config_mode`. Ohne Absicherung, aber nur in der Site gelesen: `hotfix.*`,
`linkcheck.*`, `neanderfunk.*` (siehe 5.). `ssid_changer.*` über
`gluon.site`, steht in der Site.

- [ ] Gluons check_site läuft im Multi-Bau ohne Fehler (sonst bricht der Bau
      ab).

### 8. Zweige und Rückführung

- Alles oben liegt im Feed auf `v2025.1.x-next`. Auf `v2025.1.x` sind
  nodeplacer (`d2c00a2`) und node-whisperer (`c10217b`) gleich, aber
  `neanderfunk-domain-from-legacy` steht dort noch auf dem alten Stand (ohne
  `next_node_ip4_fest`, ohne kmsg/uci-Protokoll).
- [ ] Vor dem Wechsel der Produktion auf Multi-Domain: entscheiden, ob
      `v2025.1.x-next` nach `v2025.1.x` zurückgeführt wird oder next zur
      Produktionslinie wird; dann die Patch-Repos (`gluon-patches-packages`
      `v2025.1.x-next`) genauso.

Stand der Punkte
----------------

Offen bei Anlage: 1 (echtes Image), 2 (Browser: Auswahl, Karte, Hostname), 3, 4 (Gerät), 5
(`br_client_ipv6` am Gerät, Code behoben), 6 (App), 8. Bestanden: Offline-Tests zu 1 und 2,
check_site-Probe zu `nodeplacer.mirrors` mit Gluons check-site.

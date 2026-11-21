# Entwurf: neanderfunk-automesh

Stand 21.11.2026, Fassung 3 (Zuschnitt in Abschnitt 0, sonst Fassung 2
vom 02.10.2026). Noch kein Code, Testtermin offen. Die
Entstehung mit beiden Reviews steht in der
Git-Historie dieser Datei (Fassung 1 bis 9bfdd64). Hier steht nur noch der
bereinigte Stand. Herkunft einzelner Regeln in Klammern: (A) = Entscheidung
adorfer, (R1-x) / (R2-x) = erstes bzw. zweites Review.

## 0. Zuschnitt 21.11.2026 (A)

Fassung 3 engt den Entwurf ein. Wo die Abschnitte 1 bis 16 mehr vorsehen,
gilt dieser Abschnitt.

- **Handelnde Knoten:** nur Knoten mit der aktuellen Firmware, also
  Multi-Domain 2025.1. Jeder Knoten hat alle Domains an Bord und meldet
  seinen `domain_code`; die Normalisierung von Altcodes (Abschnitt 2)
  braucht es für eigene Knoten nicht mehr, nur noch für Gegenüber mit alter
  Firmware.
- **VXLAN ausgeklammert:** keine Suche nach VXLAN am LAN, kein Beitritt
  über eine zweite VNI. Der Sniffer aus 6.2 entfällt damit vorerst.
- **Trennen von Domain-Brücken (Fall A, Abschnitt 7) ist das wichtige
  Feature** und der erste Eingriff.
- **Beitritt nur per WLAN-Mesh (802.11s, Abschnitt 6.3), nur für Knoten
  ohne VPN-Uplink**, also Inseln. Die Regeln aus 6.1, 6.4, 8, 9 und 10
  gelten weiter.
- **Beitritt nur zu Meshes unserer eigenen Domains** (A, 21.11.): Die
  Mesh-IDs kommen aus `/lib/gluon/domains/*.json` der eigenen Firmware.
  Nachbar-Communities sind vorerst draußen, und mit ihnen die Sperrliste
  `deny` (Entscheidung 2 vom 02.10., Abschnitte 12 und 13): Sie war für den
  Beitritt zu Nachbar-Communities gedacht und kommt erst mit diesem
  Feature wieder.
- **Knoten ohne eigenes VPN wechseln die Domain selbst, auch außerhalb von
  `25_hvb`** (A, 21.11.), wie `lan_switch` im domainhelper. Das ist ein
  dauerhafter Wechsel (`gluon-switch-domain`, schreibt in den Flash) und
  damit eine bewusste Ausnahme von „kein uci commit im Betrieb“, ebenso wie
  nodeplacer. Bedingungen (Vorschlag):
  - kein eigenes VPN (kein Nachbar auf `mesh-vpn`);
  - die LAN-Mesh-Nachbarn aus fremder Domain gehören alle zu genau einer
    Domain unserer Firmware;
  - das Gateway in `gwl` kommt über diese Nachbarn;
  - keine WLAN-Mesh-Nachbarn der eigenen Domain, damit kein Knoten hinter
    ihm das Netz verliert;
  - gegen Pendeln und Flash-Verschleiß höchstens ein automatischer Wechsel
    je Tag, Zeitpunkt im Flash vermerkt, sonst nur melden.
  Ein Knoten mit eigenem VPN wechselt nie selbst, er trennt (Fall A).
- **Erkennen** der LAN-Nachbarn und ihrer Domain gibt es schon in
  `neanderfunk-domainhelper` (`batctl n` und `gluon-neighbour-info` je
  Mesh-Interface, Stand 0.3). automesh baut darauf auf.

Offen:

- **Paket:** automesh als Teil von `neanderfunk-domainhelper` (ein
  Quellpaket, gemeinsame Shell-Bibliothek), der Teil mit Beitritt und WLAN
  als eigenes Binärpaket, das nicht auf 64-MB-Geräte kommt.

Reihenfolge:

1. Erkennen und melden in allen Domains (Syslog, respondd, Banner), ohne
   Eingriff.
2. linkcheck-Marker nur bei Heimat-Gateway (Abschnitt 9), auf allen
   Geräten. Muss vor dem Beitritt im Feld sein.
3. Trennen (Fall A) und Domainwechsel ohne VPN am Kabel.
4. WLAN-Beitritt für Inseln.

Was aus Fassung 2 umgesetzt, geplant, aufgeschoben oder verworfen ist,
führt Abschnitt 17. Dort steht auch, auf welche Entscheidung sich der Stand
stützt, damit wir sie später gezielt wieder aufgreifen können.

## 1. Worum es geht

**Hauptfall: falsche Firmware oder falsche Domain am LAN-Mesh.** Wir fahren
`mesh.vxlan = false`. Steckt ein Knoten einer anderen Domain im LAN-Mesh,
verschmelzen beide Domains sofort über rohes batman (Domain-Brücke). Echter
Feldfall: Holzmichel-a36a (UniFi AC Mesh Pro, Firmware dus-13_dusfl) hängt
seit 09.12.2025 über Holzmichel-c501 im Mesh von 21_dias. Laut adorfer war es
eine falsche Firmware und wurde nie bemerkt, weil beide Domains dieselben
IPv4- und öffentlichen IPv6-Präfixe haben. Abgleich Domain gegen
Gateway-Domain über alle 1590 Online-Knoten (02.10. 18:31): kein weiterer
Fall.

**Nebenfall: Insel.** Eine eigene Wolke ohne Gateway tritt einem fremden
batman-Mesh bei, am LAN (VXLAN oder rohes batman) oder per 802.11s. Ein
fremdes Gateway ist besser als keins (A).

## 2. Begriffe

- **Wolke**: alle Originatoren in bat0, die ohne automesh-Schnittstelle
  erreichbar sind. Ein Einzelknoten ist eine Wolke der Größe 1. (R1-3)
- **Insel**: Wolke ohne Gateway.
- **Randknoten**: der eine Knoten, der eine fremde Verbindung hält.
  Entweder ist er per automesh beigetreten (`joined`), oder er hat einen
  fremden batman-Nachbarn direkt auf `mesh_other` (`merged`).
- **Domainnummer eines Codes** (R2-1): `site_code` bzw. `domain_code`
  normalisieren. Präfix bis einschließlich `-` abschneiden
  (`nef-`, `dus-`, `bgl-`, `lvrsw-`), Suffix `_EOL` abschneiden, dann
  `^([0-9][0-9])_` oder `^ffnefd([0-9][0-9])$`. Beispiele: `nef-21_dias`,
  `nef-21_dias_EOL`, `21_dias` und `ffnefd21` ergeben alle 21.
- **Eigene Domainnummer**: aus dem eigenen `site_code` zur Laufzeit, gleiche
  Normalisierung. Es braucht keine Liste aus dem Bau.
- **Heimat**: Code mit eigener Domainnummer, oder Code aus
  `automesh.home_extra` (Altcodes, einmalig gegen die Kartencodes
  geprüft).
- **Fremd** (positiver Beleg): Ein Code ist vorhanden und hat eine **andere**
  Domainnummer, oder er ist nicht normalisierbar und steht nicht in
  `home_extra` (z. B. `ffw`, `wup`). Eine andere Domain der eigenen Familie
  ist fremd (A).
- **Unbekannt**: keine Antwort, Antwort ohne `site_code` und `domain_code`,
  oder Antwort, die die Prüfkette nicht besteht. Unbekannt ist **nie**
  fremd.
- **Heimat-Gateway**: Gateway, dessen Antwort die Prüfkette (Abschnitt 4)
  besteht und Heimat ist.
- **Heimat-Hinweis**: Die Gateway-MAC zeigt die eigene Domainnummer
  (`02:ca:ff:ee:<NN>:<SS>`, Abschnitt 4). Das ist ein Hinweis, kein Urteil.
  Er zählt nur dort, wo ausdrücklich erlaubt.
- **Familie**: Das RA-Präfix des fremden Netzes liegt in unseren Filtern
  (`extra_prefixes6` der site.conf: `2a03:2260::/29` FFRL und
  `2a13:fcc0::/29` FNSH, seit 04.10.2026; vorher `2a03:2260::/32`). IPv4 ist
  ohnehin `10.0.0.0/8`. Erkennbar nur am RA,
  denn ein Gluon-Knoten hat auf br-client keine eigene IPv4-Lease. (R2-17)

## 3. Grundsätze

1. **Nur zur Laufzeit.** Kein `uci commit`. Interfaces über
   `ubus call network add_dynamic`, WLAN über uci-Delta plus
   `flock … wifi reconf`, Filter per `ebtables-tiny`. Ein Reboot stellt den
   Normalzustand her. Ausnahme: Ein Kabel, das eine Brücke bildet, ist nach
   dem Reboot wieder da. Deshalb prüft Fall A sofort nach dem Boot (R1-13).
2. **Eingriffe nur auf positiven Beleg.** Trennen und `merged` nur bei
   "fremd". "Unbekannt" löst nie einen Eingriff aus. Ein hängender respondd
   am Supernode trifft alle Knoten dahinter gleichzeitig und darf flottenweit
   nichts auslösen (Frage A). Die einzige Ausnahme ist die harmlose
   Richtung: Ein Randknoten in `joined` löst lieber einmal zu viel auf.
3. **Nie zwei Netze mit Gateways verbinden.** Eine Insel darf über einen
   Randknoten an ein fremdes Netz. Taucht auf der eigenen Seite ein
   Heimat-Gateway auf, löst der Randknoten **sofort** auf (R2-3).
4. **Wer anbindet, löst auch auf.** Knoten auf halbem Weg greifen nicht ein,
   solange ein Randknoten der eigenen Domain sich meldet (Abschnitt 7).
5. **Pendeln wird durch Sperren gebremst, nicht durch Abwarten vor dem
   Auflösen.** Hysterese gibt es nur in der Richtung "Heimat ist weg"
   (2 min). Sperren wachsen exponentiell (Abschnitt 8).
6. **Ein Werkzeug, ein Lock:** automesh, ap-timer, ssid-changer, scan-guard
   und die hotfix-Checks greifen über `flock /var/lock/neanderfunk-wifi.lock`
   ins WLAN (R1-16, R1-18).
7. Shell und ein kleines C-Paket fürs Mitlesen, kein Lua-Daemon. Nicht auf
   64-MB-Geräten (A).

## 4. Prüfkette: Wer ist dieses Gateway?

Am WDR3600 durchgespielt (02.10.). Nur batman-adv und respondd:

1. `batctl gwl`, Spalte Router: Originator, z. B. `02:ca:ff:ee:21:03`. Das
   ist die MAC des Hard-Interfaces br<NN> des Supernodes.
2. `batctl tg`: Unicast-Einträge dieses Originators (ohne `33:33:…` und
   `01:00:5e:…`). Darunter ist die MAC seiner bat-Schnittstelle
   (`f2:be:ef:00:21:03`, zugleich seine node_id).
3. EUI-64-Link-Local daraus: `fe80::f0be:efff:fe00:2103`. Das ist auch der
   Router im RA.
4. `gluon-neighbour-info -i br-client -d <ll> -p 1001 -t 3 -r nodeinfo`.
   kallisto antwortet mit `domain_code: ffnefd21`, `hostname:
   kallisto_ffnefd21`, `vpn: true` und
   `network.mesh.bat21.interfaces.tunnel: ["02:ca:ff:ee:21:03"]`.
5. **Gültig nur**, wenn der Originator aus Schritt 1 in den
   Mesh-Interfaces der Antwort steht. Sonst unbekannt.
6. Code normalisieren (Abschnitt 2), dann Heimat, fremd oder unbekannt.

Versuche: 3 mal je 3 s. Abgefragt wird bei jedem neuen Originator in `gwl`
und im 60-s-Takt für Gateways, die noch unbekannt sind (R1-8).

**MAC-Schema** (Gateway-Ansible des Maintainers, Rolle gateways_batman;
Felddaten bestätigen es): `02:ca:ff:ee:<NN>:<SS>`,
NN = Domainnummer in Dezimalziffern, SS = Supernode (01 pasophae bis
06 ganymed). Grenzen: Domain ≥ 100 und Supernode ≥ 10 sprengen es, und das
Präfix ist kein Alleinstellungsmerkmal (`02:ca:ff:ee:ba:be`). Deshalb nur
Auslöser und Heimat-Hinweis, nie Urteil (R1-7). Auf der Karte erscheint
statt der MAC die node_id `f2beef00NNSS`, weil yanic auflöst.

## 5. Zustände

`/tmp/automesh.state` enthält Zustand, Netz (normalisierter Code), seit wann
und Sperren. Das ist die Quelle für respondd, Statusseite, Banner, Syslog
und für die Ausnahmen in linkcheck und den hotfix-Checks.

| Zustand | Bedeutung |
|---|---|
| `idle` | normal: Heimat-Gateway da, oder noch keine Bedingung erfüllt |
| `island` | Insel-Bedingungen erfüllt, Suche läuft |
| `probing` | Beitritt läuft (max. 60 s Wartezeit auf Nachbarn) |
| `joined <netz>` | Randknoten per automesh beigetreten |
| `merged <netz>` | Randknoten ohne VPN mit fremdem Nachbarn am Kabel (Fall B) |
| `lan_cut <netz>` | `mesh_other` getrennt (Fall A) |
| `gw_unverified` | Gateway in `gwl`, aber unbekannt; nur Anzeige |

| von | Ereignis / Bedingung | Aktion | nach |
|---|---|---|---|
| `idle` | Uptime ≥ `delay`, kein Heimat-Marker, `gwl` leer, keine globale Sperre | Zufallsfrist 0-120 s, dann `gwl` erneut prüfen | `island` |
| `island` | `gwl` nicht mehr leer | - | `idle` |
| `island` | Kandidat gefunden (LAN/WLAN), nicht in `deny`, keine Netz-Sperre | Beitritt (Abschnitt 6) | `probing` |
| `probing` | Nachbar auf automesh-Schnittstelle, Gateway in `gwl` | Signalisierung; außerhalb der Familie Filter (Abschnitt 6.4) | `joined` |
| `probing` | 60 s ohne Nachbarn und ohne wifi-Neustart dazwischen | Austritt, Netz-Sperre | `island` |
| `joined` | Heimat-Gateway (Prüfkette) **oder** unbekanntes Gateway über eigene Schnittstelle **oder** Heimat-Hinweis | sofort auflösen, globale Sperre | `idle` |
| `joined` | Gateway eines **anderen** fremden Netzes über eigene Schnittstellen | höhere MAC löst auf, Netz-Sperre | `island` (höhere MAC) |
| `joined` | `gwl` 60 s leer (R1-14) | auflösen, globale Sperre (R2-7) | `island` |
| `idle`/`gw_unverified` | fremder Nachbar direkt auf `mesh_other`, kein VPN, Gateway in `gwl` fremd (positiv) | Signalisierung; außerhalb der Familie Filter | `merged` |
| `merged` | keine Antwort mehr vom fremden Gateway | **nichts**, bleibt `merged` (R2-5) | `merged` |
| `merged` | Heimat-Gateway oder `gwl` leer | Filter zurück | `idle` |
| `merged` | eigenes VPN kommt hoch | weiter wie Fall A | `idle` (Fall A läuft) |
| beliebig, VPN oben | fremd (positiv) hinter `mesh_other`, Frist und Notbremse (Abschnitt 7) abgelaufen | `ifdown mesh_other` | `lan_cut` |
| `lan_cut` | 10 min seit Trennen **und** (hotplug Link-up oder Sperre abgelaufen) | `ifup mesh_other`, neu prüfen | `idle` |
| `idle` | Gateway in `gwl`, keines Heimat, keines fremd | nur Anzeige | `gw_unverified` |
| `gw_unverified` | Heimat-Gateway | - | `idle` |

## 6. Beitreten (Nebenfall Insel)

### 6.1 Wann

Alle Bedingungen müssen erfüllt sein:
1. Uptime ≥ `delay` (Vorgabe 900 s).
2. **Kein Heimat-Marker** `/tmp/automesh.home-gw-seen`. Gesetzt wird er durch
   ein Heimat-Gateway (A) und durch einen Heimat-Hinweis. Ein unbekanntes
   Gateway ohne Hinweis setzt ihn nicht, ein fremdes nie (R2-4, siehe
   Abschnitt 10). Der Marker bremst Massenauslösung: Bei einem
   Supernode-Ausfall haben alle Knoten vorher ein Heimat-Gateway gesehen.
   Der Marker ist getrennt von `/tmp/linkcheck.gw-seen` (A).
3. `gwl` gerade leer, auch kein fremdes Gateway. Sonst hat schon ein
   anderer Knoten der Wolke angebunden.
4. Keine globale Sperre aktiv (Abschnitt 8).

### 6.2 Suche am LAN-Mesh

Nur auf Ports mit Mesh-Rolle. Das C-Paket (`neanderfunk-automesh-sniff`,
`AF_PACKET` + BPF, eigenes Paket wegen Größenmessung, R1-17) liest passiv:
- **VXLAN**: UDP 4789 an `ff02::15c`. Die VNI steht im Klartext, Gluon
  leitet sie aus dem `domain_seed` ab.
- **Rohes batman**: Ethertype 0x4305.

Im inneren batman-Frame stehen `version` (nur 15) und `packet_type`: 0x00 ist
BATMAN_IV, 0x03/0x04 ist BATMAN_V. Wir fahren BATMAN_IV, ein BATMAN_V-Netz
wird übersprungen.

Beitritt bei VXLAN: zweites vxlan6-Gerät mit fremder VNI (`add_dynamic`,
proto `vxlan6`, Peer `ff02::15c`), darüber `batadv_hardif` an bat0.
Rohes batman braucht keinen Beitritt, das ist Fall B (Abschnitt 6.5).

### 6.3 Suche im WLAN (802.11s)

- Mesh-ID im Scan (`MESH ID`), jede außer der eigenen und außer `deny`.
  Kein Muster wie `.*-mesh`: Die bgl-Domains heißen `mesh-bgl`, `mesh-lln`
  usw.
- Scan nur über scan-guard (Stand 29.09.; scan-guard ist in v2025.1.x seit 04.10.2026 entfallen, unter 2025.1 trat der Scan-Fehler nicht mehr auf). Auf MT7915 legte unter 2023.2 jeder Scan das Radio lahm,
  dort keine WLAN-Suche auf diesem Radio.
- Nicht, solange autoupdater-wifi-fallback aktiv ist (R1-15).
- Beitritt: wifi-iface `mode mesh` mit fremder `mesh_id` als uci-Delta, Netz
  `automesh_wN` (`batadv_hardif`, master bat0), `flock … wifi reconf`.
  Kanalwechsel ist erlaubt (A). Der AP wechselt mit, beim Auflösen wird das
  Delta verworfen.
- Fremde Meshes mit SAE fallen weg.
- Ob Algorithmus und Compat passen, zeigt sich erst nach dem Beitritt.
  Gescheitert ist der Beitritt erst nach 60 s ohne Nachbarn und ohne
  zwischenzeitlichen wifi-Neustart (R1-16).

### 6.4 Lokale Dienste im fremden Netz

| Was | Familie | außerhalb der Familie |
|---|---|---|
| `LOCAL_FORWARD` (Quellfilter) | nichts, 10/8 und `extra_prefixes6` (2a03:2260::/29, 2a13:fcc0::/29) decken alles (R1-6) | fremde Präfixe aus dem RA zusätzlich erlauben, nicht Filter ganz auf |
| uradvd (gluon-radvd) | läuft weiter: ULA bleibt lokal, Gateway-RA bringt kein ULA und kein RDNSS (gemessen WDR3600) | läuft weiter |
| DNS | Gateways nennen ihre eigene Adresse (Gateway-Ansible, nicht gemessen); dnsmasq fällt auf die öffentlichen `dns.servers` zurück | dito |
| filter-ra-dhcp, next-node | bleiben | bleiben |
| ssid-changer | unverändert, gleiche TQ-Kriterien wie daheim (A) | dito |
| eigene Mesh-Schnittstellen | bleiben in bat0, die Wolke soll das Gateway mitbenutzen | dito |

### 6.5 Fall B: Knoten ohne VPN, fremder Nachbar am Kabel

Bei `vxlan = false` ist der Knoten schon im fremden Mesh, sobald das Kabel
steckt. Auslöser (R1-5): Gateway in `gwl`, keines Heimat, mindestens eines
positiv fremd, kein VPN, und ein fremder batman-Nachbar direkt auf
`mesh_other`. Dann gilt `merged` mit Signalisierung und, außerhalb der
Familie, Abschnitt 6.4. Randknoten können beide Kabelenden sein.

## 7. Trennen (Hauptfall, Fall A)

Ein Knoten mit VPN sieht über `mesh_other` (bzw. mesh on WAN) Knoten eines
fremden Netzes.

**Erkennung:**
- Auslöser (billig): ein Gateway, das nur über `mesh_other` erreichbar ist
  und nicht über mesh-vpn, oder eine fremde Domainnummer im MAC-Schema,
  oder mehr als 12 Originatoren, die nur über `mesh_other` bekannt sind.
- Urteil: Prüfkette (Abschnitt 4) für dieses Gateway oder respondd per
  Link-Local an die direkten Nachbarn auf `mesh_other`. Getrennt wird nur
  bei positiv **fremd**.

**Frist und Notbremse** (wer anbindet, löst auf):
1. Erkannt, dann 120 s warten und neu prüfen. In der Zeit hat ein Randknoten
   in `joined` längst aufgelöst.
2. Vor dem Trennen nachsehen, ob ein Randknoten der **eigenen** Domain
   `joined` oder `merged` meldet (R1-14). Wie, ohne die ganze Wolke per
   Multicast zu fragen (R2-9):
   - bevorzugt: Ein Randknoten meldet sich mit einer festen,
     lokal verwalteten MAC in der batman-Translation-Table (z. B. ein
     Dummy-Port in br-client, der alle 60 s einen Frame sendet). Jeder Knoten
     sieht sie in `batctl tg` samt Originator, ohne Abfrage. Zu prüfen.
   - Ersatz: respondd per Link-Local nur an die direkten Nachbarn auf
     `mesh_other`.
3. Meldet sich ein eigener Randknoten, warten, höchstens 10 min, dann doch
   trennen.
4. `ifdown mesh_other`: netifd nimmt nur den batman-hardif heraus, Port und
   Uplink bleiben.

**Merged an beiden Kabelenden** (R2-8): Liegen beide Seiten in der Familie
und haben beide automesh, meldet jedes Ende `merged` mit dem anderen als
fremd. Ein Knoten auf halbem Weg der Seite X sieht den eigenen Randknoten
in `merged` und wartet bis 10 min statt 120 s. Bekommt das Ende auf Seite X
danach VPN, verlässt es `merged`, läuft in Fall A und trennt nach 120 s
selbst. Seite X ist sauber.

**Fall A und Fall B in einer Wolke** (R1-12): Trennt ein Knoten mit VPN sein
`mesh_other` und zerfällt die Wolke dadurch, ist das gewollt. Der Teil ohne
VPN bleibt mit fremdem Gateway in `merged`. Dort wird niemand zusätzlich
Randknoten, denn es steht ein Gateway in `gwl`.

**Kette eigen -> fremd1 -> fremd2** (R1-14): Unser Randknoten hängt an
fremd1, dessen Randknoten an fremd2. Löst der von fremd1 auf, wird unser
`gwl` leer, ohne dass ein Ereignis kommt. Nach 60 s leerem `gwl` lösen wir
auf, mit globaler Sperre.

## 8. Sperren gegen Pendeln

- **Global** (gegen jeden Beitritt): nach Auflösen wegen Heimat und nach
  Auflösen wegen leerem `gwl`. Exponentiell 5, 10, 20, 40, 80 min, Obergrenze
  2 h. Zurück auf 5 min nach 24 h ohne Auflösen. (R1-10, R2-6, R2-7)
- **Je Netz**: nach gescheitertem Beitritt und nach Austritt wegen
  Doppel-Randknoten (R1-11). Ebenfalls exponentiell.
- **Heimat ist weg** gilt erst nach 2 min ohne Heimat-Gateway. Das bremst
  nur den Wiederbeitritt, nie das Auflösen (R2-3).
- **Fall A**: Neuprüfung frühestens 10 min nach dem Trennen, auch bei
  hotplug Link-up (R1-9). Danach exponentiell wie global.

## 9. Wechselwirkungen

| Paket | Problem | Festlegung |
|---|---|---|
| neanderfunk-linkcheck `no_gateway` | setzt `/tmp/linkcheck.gw-seen` bei **jedem** Gateway und rebootet nach 4 leeren Prüfungen. Löst ein Randknoten auf, würde die ganze Wolke rebooten. Das gilt auch für 64-MB-Knoten **ohne** automesh (R2-2) | Änderung in linkcheck auf **allen** Geräten, unabhängig von automesh: Marker nur bei Heimat-Hinweis (MAC-Schema mit eigener Domainnummer) oder Gateway über mesh-vpn. Für einen Reboot-Schutz reicht ein Hinweis. Zusätzlich keine Strikes, solange `/tmp/automesh.state` `joined`/`merged`/Sperre zeigt |
| tunneldigger-watchdog | startet mesh-vpn alle 5 min neu | gewollt, so kommt VPN zurück |
| ssid-changer | sieht das fremde Gateway | unverändert, gleiche TQ-Kriterien (A); nur gemeinsames Lock |
| autoupdater-wifi-fallback | tauscht ohne Verbindung das WLAN gegen einen Client | kein WLAN-Beitritt, solange aktiv; umgekehrt soll der Fallback `joined` respektieren. Ob das ohne Gluon-Patch geht, wird bei der Umsetzung geprüft (R1-15) |
| hotfix IfNoWificlient, watchdog, check_wifi_firmware | können wifi neu starten, während `probing` wartet | gemeinsames Lock, Ruhe in `probing` (R1-16) |
| ap-timer, scan-guard | greifen per `wifi reconf` ins WLAN | gemeinsames Lock |
| Weekly Reboot | setzt alles zurück | gewollt; Fall A prüft nach dem Boot sofort |

## 10. Marker: Entscheidung und Review

adorfer hat entschieden: Nur ein Heimat-Gateway setzt den Marker (A). Das
zweite Review (R2-4) wollte ihn auch bei unbekanntem Gateway setzen, damit
nicht beigetreten wird. Die Lösung oben erfüllt beides:
- Ein Heimat-Hinweis (MAC-Schema mit eigener Domainnummer) setzt ihn auch.
  Ein Supernode mit hängendem respondd setzt ihn also trotzdem, und die
  Massenauslösung bleibt gebremst.
- Ein fremdes Gateway ohne respondd und ohne Hinweis setzt ihn nicht. Nach
  dem Auflösen kann die Wolke deshalb wieder anbinden und bleibt nicht bis
  zum Weekly Reboot dunkel.
- Ein Beitritt bei unbekanntem Gateway ist unabhängig vom Marker
  ausgeschlossen, durch Bedingung 3 (`gwl` leer).

## 11. Signalisierung (A)

Mit der Umsetzung sofort, nicht später:
- neanderfunk-respondd: Feld in statistics, z. B. `automesh: {state, net,
  iface, since}`;
- Statusseite: Zeile über gluon-patches-packages, eigene i18n;
- Login-Banner: neanderfunk-banner, profile.gluon/nodestatus;
- Syslog-Zeile bei jedem Zustandswechsel (Kollektor).

## 12. Konfiguration

    automesh = {
      enabled = false,
      delay = 900,             -- Sekunden nach Boot, nur für Beitritt (nicht Fall A)
      lan = true,
      wifi = true,
      home_extra = { },        -- Altcodes, die als Heimat gelten (Abgleich gegen Kartencodes)
      deny = { },              -- Netze, die automatisches Beitreten ablehnen (PPA §3/§4):
                               -- normalisierte Codes, Mesh-IDs, VNIs
    },

uci-Werte tolerant lesen (1/true/yes/on). Paket nicht in den lowmem-Gruppen
von image-customization (A).

## 13. PPA v1.0

Gedeckt durch das Pico Peering Agreement (Leitlinie für alle
Freifunk-Communities, nachgelesen 02.10.): Die Präambel nennt das Verbinden
von Netzwerkinseln als Ziel, der Praxisteil die automatische Vernetzung.
§1 Freier Transit ("in ein Netzwerk hinein, heraus oder hindurch") braucht
keine Einzelabsprache. §2 Offene Kommunikation macht Kontaktdaten auf der
fremden Karte gewollt; der Kontakt-Dialog im Config-Mode sagt ohnehin, dass
sie öffentlich sind. §3/§4 erlauben Einschränkung und Nutzungsrichtlinie,
DHCP ist "zusätzlicher Dienst". Daraus folgen die Sperrliste statt einer
Erlaubnisliste (A) und kein Ausblenden von Knotendaten.

## 14. Test

- LAN in QEMU: unser Image plus ein fremdes x86-Gluon an einer Bridge,
  einmal VXLAN, einmal rohes batman, mit Gateway auf der fremden Seite.
- WLAN: zwei echte Geräte am Testplatz.
- Pflichtfälle: jede Zeile der Zustandstabelle, BATMAN_V übersprungen,
  MT7915 scannt nicht, Reboot mitten in jedem Zustand, Supernode-respondd
  angehalten (darf nichts auslösen), linkcheck rebootet nach Auflösen
  nicht, auch auf einem 64-MB-Knoten in der Wolke.
- Feldfall Holzmichel als Referenz für Fall A (nur lesend).

## 15. Nebenbefunde

- `mesh.vxlan = false`: Jedes fremde Netz mit ebenfalls rohem batman am
  selben Kabel verschmilzt schon heute mit unserem.
- `roguenets_filter` stand in templates/common/site.conf und wurde von
  keinem Paket gelesen. Erledigt 04.10.2026 (Entscheidung adorfer): aus allen
  drei site.conf entfernt (FirmwareConfigs v2021.x 86dbf5e, v2023.2.x
  f3abd49, v2025.1.x 011b548).
- Unsere Knoten melden keinen `domain_code` (Single-Domain-Firmware je
  Template), nur `site_code`. Das `domain` der Karte setzt yanic zusammen
  (R1-1). Auf der Karte gibt es dazu viele Schreibweisen: mit und ohne
  Präfix, mit `_EOL`, Multidomain-Firmwares mit `domain_code`, Altcodes wie
  `ffw`, und 10 Knoten ohne jeden Code (R2-1, Stand 02.10.).

## 16. Entscheidungen (alle getroffen)

1. Wolken dürfen anbinden; aufgelöst wird nur über den Randknoten.
2. Alle fremden Netze außer `deny`; Netzliste nur als technische Hilfe.
3. Andere eigene Domain gilt als fremd.
4. Kein automesh auf 64-MB-Geräten (die linkcheck-Änderung gilt trotzdem
   dort).
5. Kanalwechsel für fremde 11s-Meshes erlaubt.
6. Signalisierung sofort an vier Stellen (Abschnitt 11).
7. Eigener Heimat-Marker, getrennt von linkcheck (Abschnitt 10).
8. ssid-changer mit gleichen TQ-Kriterien wie daheim.

## 17. Feature-Stand

Stand 21.11.2026. Bezug ist der Funktionsumfang von Fassung 2. Pflegen bei
jeder Entscheidung und jedem Bau: Status, Datum, Grund.

Status:
- **umgesetzt**: im Paket und getestet;
- **geplant**: im Zuschnitt von Fassung 3, noch nicht gebaut (Schritt 1 bis 4
  aus Abschnitt 0);
- **aufgeschoben**: bewusst später, Entscheidung kann wieder aufgegriffen
  werden;
- **verworfen**: entfällt, mit Grund.

Gebaut ist von automesh selbst noch nichts. Vorarbeit liegt in
`neanderfunk-domainhelper` 0.3 (Test 21.11.2026 mit 26112017sta).

| # | Feature | Fassung 2 | Status | Seit | Grund, Anmerkung |
|---|---|---|---|---|---|
| 1 | LAN-Mesh-Nachbarn und ihre Domain erkennen (`batctl n`, respondd per Link-Local) | 4, 7 | teilweise umgesetzt | 21.11. | im domainhelper, aber nur in `25_hvb` aktiv; für alle Domains Schritt 1 |
| 2 | Signalisierung: Syslog, respondd, Statusseite, Banner | 11 | geplant | 21.11. | Schritt 1; Syslog-Zeilen gibt es im domainhelper schon |
| 3 | Prüfkette „Wer ist dieses Gateway?“ | 4 | geplant | 21.11. | einfacher, weil Multi-Knoten `domain_code` melden |
| 4 | MAC-Schema `02:ca:ff:ee:<NN>:<SS>` als Heimat-Hinweis | 4, 10 | geplant | 02.10. | nur Hinweis, nie Urteil |
| 5 | Normalisierung von Altcodes, `home_extra` | 2, 12 | aufgeschoben | 21.11. | handeln dürfen nur Multi-Knoten (A); nötig höchstens für Nachbarn mit alter Firmware |
| 6 | linkcheck: Gateway-Marker nur bei Heimat-Gateway, alle Geräte | 9, 10 | geplant | 21.11. | Schritt 2, Voraussetzung für Beitritt |
| 7 | Fall A: `mesh_other` trennen bei fremdem Nachbarn, Knoten mit VPN, nur Laufzeit | 7 | geplant | 21.11. | Schritt 3; „das wichtige Feature“ (A) |
| 8 | Frist 120 s und Notbremse „eigener Randknoten meldet sich“ | 7 | geplant | 02.10. | Weg über Translation-Table-MAC noch zu prüfen |
| 9 | Domainwechsel ohne eigenes VPN am Kabel, alle Domains | neu | geplant | 21.11. | Schritt 3 (A); Flash-Ausnahme, höchstens 1 je Tag (Vorschlag) |
| 10 | Fall B `merged`: ohne VPN im fremden Mesh bleiben, Filter für fremde Präfixe | 6.4, 6.5 | aufgeschoben | 21.11. | für eigene Domains ersetzt durch #9; bleibt Thema für Nachbar-Communities |
| 11 | Beitritt am LAN per VXLAN (zweite VNI) | 6.2 | aufgeschoben | 21.11. | VXLAN ausgeklammert (A) |
| 12 | Sniffer `neanderfunk-automesh-sniff` (AF_PACKET, BPF) | 6.2 | aufgeschoben | 21.11. | hing an VXLAN; rohes batman zeigt schon `batctl n` |
| 13 | BATMAN_V-Netze überspringen | 6.2 | aufgeschoben | 21.11. | nur mit Sniffer; unsere Domains fahren alle BATMAN_IV |
| 14 | WLAN-Beitritt (802.11s) für Inseln ohne VPN | 6.3 | geplant | 21.11. | Schritt 4 (A) |
| 15 | Beitritt nur zu Meshes eigener Domains, Mesh-IDs aus `/lib/gluon/domains/*.json` | neu | geplant | 21.11. | (A); ersetzt für jetzt Entscheidung 2 |
| 16 | Beitritt zu Nachbar-Communities | 6.3, 16.2 | aufgeschoben | 21.11. | (A); kommt mit #17 zurück |
| 17 | Sperrliste `deny`, PPA-Begründung | 12, 13 | aufgeschoben | 21.11. | war für Nachbar-Communities gedacht (A) |
| 18 | Kanalwechsel für den Beitritt, AP wechselt mit | 6.3, 16.5 | geplant | 02.10. | gilt weiter, nur Laufzeit-Delta |
| 19 | Zustände in `/tmp/automesh.state` | 5 | geplant | 21.11. | ohne `merged` und VXLAN-Zustände kleiner |
| 20 | Sperren gegen Pendeln, exponentiell, global und je Netz | 8 | geplant | 02.10. | |
| 21 | Gemeinsames WLAN-Lock `/var/lock/neanderfunk-wifi.lock` | 3, 9 | geplant | 02.10. | Schritt 4 |
| 22 | Rücksicht auf autoupdater-wifi-fallback | 9 | geplant | 02.10. | ob ohne Gluon-Patch möglich, offen |
| 23 | Doppel-Randknoten: höhere MAC löst auf | 5 | geplant | 02.10. | Schritt 4 |
| 24 | Kein automesh auf 64-MB-Geräten | 3, 16.4 | geplant | 02.10. | linkcheck-Änderung (#6) trotzdem dort |
| 25 | Scan nur über scan-guard | 6.3 | verworfen | 04.10. | scan-guard in v2025.1.x entfallen |
| 26 | Kein WLAN-Scan auf MT7915 | 6.3 | verworfen | 04.10. | Scan-Fehler nur unter 2023.2, nicht unter 2025.1 |
| 27 | Mesh-IDs per Muster `.*-mesh` erkennen | 6.3 | verworfen | 02.10. | Domains 43 bis 47 heißen `mesh-<kurz>`; Liste statt Muster |
| 28 | Erlaubnisliste statt Sperrliste | 13 | verworfen | 02.10. | PPA (A); für eigene Domains ist #15 faktisch eine Liste aus der Firmware |
| 29 | Paket: automesh in `neanderfunk-domainhelper`, Beitritt als eigenes Binärpaket | neu | offen | 21.11. | Vorschlag, noch nicht entschieden |


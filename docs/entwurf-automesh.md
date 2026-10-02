# Entwurf: neanderfunk-automesh

Stand 02.10.2026. Vorüberlegung, noch kein Code. Wann es getestet werden
kann, ist offen.

Idee: Ein Knoten, der auf einer Insel steht (kein Gateway, kein eigener
Nachbar), sucht auf dem LAN-Mesh und im WLAN nach batman-Meshes anderer
Communities. Findet er eins, tritt er bei, damit seine Clients wieder ins
Internet kommen. Taucht das eigene Netz wieder auf, verlässt er das fremde.

## 0. Hauptfall: falsche Firmware oder falsche Domain am LAN-Mesh (adorfer, 02.10.)

Der eigentliche Anlass ist nicht die fremde Community in der Luft, sondern
ein Knoten mit falscher Firmware oder falsch gewählter Domain, der in ein
LAN-Mesh gesteckt wird. Weil wir `mesh.vxlan = false` fahren, verschmelzen
die beiden Domains dann sofort über rohes batman: eine Domain-Brücke. Sie zu
verhindern ist ein gewollter Nebeneffekt. Daraus ergeben sich zwei Fälle.

### Fall A: Knoten mit VPN sieht ein fremdes Netz hinter dem LAN-Mesh: trennen

Der Knoten hat seine eigenen Gateways über mesh-vpn. Kommen über die
LAN-Mesh-Schnittstelle (`mesh_other`, ggf. mesh on WAN) Knoten eines fremden
Netzes, wird diese LAN-Mesh-Verbindung zur Laufzeit getrennt:
`ifdown mesh_other`. Damit nimmt netifd den batman-hardif sauber heraus,
der Port selbst und ein eventueller Uplink bleiben. Ein Reboot stellt den
Normalzustand her.

Erkennung "fremd hinter LAN", vom billigsten Merkmal zum teuersten:

1. **Gateway-MAC der Familie:** In `batctl gwl` (Spalte Router) und in
   respondd `statistics.gateway` steht der Supernode als
   `02:ca:ff:ee:<NN>:<SS>`. Das ist die MAC seines Hard-Interfaces br<NN>
   und damit der batman-Originator (gemessen 02.10. an WDR3600 und MR90X in
   21_dias: `02:ca:ff:ee:21:03`). Die Soft-Interface-MAC
   `f2:be:ef:00:<NN>:<SS>` ist die node_id des Supernodes. Die Karte zeigt
   sie, weil yanic die Gateway-MAC auf die node_id auflöst. Schema laut
   Gateway-Ansible (Neanderfunk/Ansible-Freifunk-Gateway, Rolle
   gateways_batman), bestätigt durch Supernode-Session und Felddaten:
   - Byte 5 = Domainnummer in **Dezimalziffern** (21 -> `:21:`), Byte 6 =
     Supernode (01 pasophae ... 06 ganymed). Mehrere Gateways je Domain
     sind normal, Byte 6 ignorieren.
   - Domain >= 100 sprengt das Schema. Ist Byte 5 keine gültige
     Familiennummer (01-48), Merkmal nicht verwenden.
   - `02:ca:ff:ee` ist kein Alleinstellungsmerkmal (vgl. die klassische
     Ad-hoc-BSSID `02:ca:ff:ee:ba:be`). Es zählt nur das Muster
     `02:ca:ff:ee:<gültige fremde Domainnummer>:<01-06>`.
   - Befund: Ein solches Gateway mit fremder Nummer ist über `mesh_other`
     erreichbar (nicht über mesh-vpn).
   - **Echter Feldfall** (Kartenstand 29.09., Supernode-Session):
     Holzmichel-a36a (UniFi AC Mesh Pro, dus-13_dusfl) hat Gateway
     21_dias, Nexthop Holzmichel-c501 (nef-21_dias) am selben Standort.
     Das ist eine 13/21-Brücke. Ob gewollt, entscheidet adorfer; als
     Testfall taugt sie.
2. **Gateway nur über LAN erreichbar:** Alle eigenen Gateways sieht ein
   VPN-Knoten über mesh-vpn (die Supernodes einer Domain hängen untereinander
   im Backbone). Ein Gateway, für das `batctl o` keinen Weg über mesh-vpn
   kennt, sondern nur über `mesh_other`, gehört nicht zu uns. Das klappt
   auch bei Netzen außerhalb der Familie.
3. **Mengenschwelle:** mehr als N Originatoren (Vorschlag N = 12), deren
   bester Weg über `mesh_other` geht und die über mesh-vpn nicht bekannt
   sind. Das ist das Merkmal für fremde Netze ohne Gateway in Sicht. Die
   Schwelle verhindert Fehlalarme durch einen einzelnen falsch geflashten
   Nachbarn, der dann selbst trennt (Fall A gilt beidseitig, es reicht,
   wenn eine Seite trennt).
4. Zur Bestätigung respondd über Link-Local auf `mesh_other`
   (`domain_code`, siehe Abschnitt 5).

Erneut prüfen: nach Ablauf einer Sperrzeit (z. B. 6 h) oder wenn der Link
neu hochkommt (Kabel umgesteckt, hotplug), `ifup mesh_other` und von vorn.

Signalisierung (Ausgestaltung später): Zustand in `/tmp`, Feld im
neanderfunk-respondd (z. B. `automesh: {state: "lan_cut", domain:
"10_wlf"}`), Zeile auf der Statusseite, nodestatus im Banner, eine
Syslog-Zeile an den Kollektor.

### Fall B: Knoten ohne VPN sieht ein fremdes Netz am LAN-Mesh: beitreten

Ohne VXLAN ist der Knoten dem fremden Mesh schon beigetreten, sobald das
Kabel steckt: bat0 nimmt jeden batman-Nachbarn. Zu tun bleibt, die lokalen
Dienste an das fremde Netz anzupassen.

- **"Lokaler dhcpd":** Einen DHCPv4-Server gibt es auf unseren Knoten nicht
  (`dhcp.local_client.ignore=1`, nachgesehen am WDR3600). DHCPv4 kommt
  schon heute vom Gateway. Lokal läuft nur **uradvd** (gluon-radvd) auf
  `local-node`: ULA-`prefix6` plus RDNSS = next-node-ULA.
- **ULA bleibt lokal, Filter beißt nicht** (adorfer; nachgesehen am WDR3600,
  21_dias, 02.10.):
  - Die ULA-Adresse auf br-client hat die Lebensdauern des lokalen uradvd
    (preferred ~900 s, valid ~6840 s). Das öffentliche Präfix vom Gateway
    hat 14400/86400 s. Das Gateway-RA bringt also nur das öffentliche
    Präfix, kein ULA und kein RDNSS (`dns-server` leer).
  - ULA ist damit nur der Notnagel für die Statusseite bzw. next-node, wenn
    kein Supernode in Sicht ist. Verkehr Client -> next-node ist für die
    Bridge INPUT, nicht FORWARD, und läuft an `LOCAL_FORWARD` vorbei.
  - IPv4 `10.0.0.0/8` und öffentlich `2a03:2260::/32` decken alle Domains
    der Familie. Am Filter ist nichts zu tun.
  - uradvd kann sogar weiterlaufen: Die Clients fragen den lokalen
    next-node-DNS. Der dnsmasq fragt zuerst `V6PREFIX::5` (der eigene
    Supernode ist im fremden Mesh nicht da) und dann die öffentlichen
    Server aus `dns.servers` über das fremde Gateway.
- **DNS vom Gateway:** DHCPv4 Option 6 und RDNSS nennen die eigene Adresse
  des Supernodes in der Domain (`V4PREFIX.<server_id>`,
  `V6PREFIX::<server_id>`), nicht next-node (Konfigurationsabsicht laut
  Gateway-Ansible, nicht gemessen). Die ist im fremden Mesh erreichbar,
  also auch hier nichts zu tun.
- Austritt wie in Abschnitt 5: Kommt das eigene VPN hoch, wird aus Fall B
  Fall A. Dann trennen und die Dienste wieder herstellen.

**Nebenbefund zur Mesh-ID:** Die Domains der bgl-Familie heißen
`mesh-bgl`, `mesh-bcd`, `mesh-lln`, `mesh-ode`, `mesh-rrh`, also mit
Präfix, nicht mit Suffix. Ein Muster `.*-mesh` fände sie nicht. Für den
WLAN-Pfad also die Liste nehmen, nicht ein Muster.

## Grundsätze

- **Nur zur Laufzeit.** Kein `uci commit`, keine Flash-Schreibzugriffe.
  Neue Interfaces über `ubus call network add_dynamic` (so baut auch
  `gluon_wired.sh` seine VXLAN-Geräte), WLAN über uci-Delta plus
  `flock … wifi reconf` wie beim ap-timer, Filter über `ebtables`-Aufrufe.
  Ein Reboot stellt immer den Normalzustand her.
- **Nie zwei Netze verbinden.** Solange der Knoten im fremden Mesh ist,
  hängt keine eigene Mesh-Schnittstelle in bat0. Sonst würde der Knoten zur
  Brücke zwischen zwei Communities: fremde Gateways in unserem Mesh, fremde
  DHCP-Leases bei unseren Clients, gemischte Translation Tables. Selbst
  wenige Sekunden reichen dafür, die Leases halten Minuten.
- Shell und ein kleiner C-Helfer, kein Lua-Daemon (64-MB-Geräte).

## 1. Insel-Erkennung (Auslöser)

Alle Bedingungen müssen erfüllt sein:

1. Uptime ≥ `delay` (Vorgabe 900 s, einstellbar).
2. Seit dem Boot nie ein Gateway in `batctl gwl`. Eine Markerdatei in
   /tmp wird gesetzt, sobald einmal eines da war. Damit bleiben Knoten
   ruhig, die bei einem Supernode-Ausfall ihr Gateway verlieren. Sonst würde
   ein netzweiter Ausfall alle Randknoten gleichzeitig in fremde Netze
   schicken.
3. Kein batman-Nachbar auf eigenen Schnittstellen (`batctl n` leer).

Zu Punkt 3: Eine Wolke aus mehreren eigenen Knoten ohne Gateway fällt damit
in v1 heraus. Träten dort alle Knoten einzeln bei, sähen sie sich gegenseitig
als "eigenes Netz" und würden pendeln. Für Wolken bräuchte es eine Wahl
(z. B. kleinste MAC tritt bei, die anderen bleiben im eigenen Mesh hinter
ihr). Das wäre allerdings genau die Brücke, die oben ausgeschlossen ist.
Deshalb: v1 nur Einzelknoten.

## 2. Suche auf dem LAN-Mesh

Nur auf Ports, die Mesh-Rolle haben (mesh on LAN/WAN).

Passiv mitlesen statt durchprobieren. Ein kleiner C-Helfer mit `AF_PACKET`
und BPF-Filter liest zwei Sorten Frames:

- **VXLAN**: UDP 4789 an `ff02::15c` (Gluon-Vorgabe). Die VNI steht im
  Klartext im VXLAN-Header (Bytes 4-6). Gluon leitet sie aus dem
  `domain_seed` ab, sie ist also je Domain fest. Durchprobieren ist unnötig
  und mit 2^24 Werten auch unmöglich.
- **Rohes batman** (Ethertype 0x4305), von Netzen mit `mesh.vxlan = false`.

Im inneren batman-Frame stehen `packet_type` und `version`. Daran sieht man
schon vor dem Beitritt:

- die Compat-Version (15 seit vielen Jahren, sonst nicht beitreten);
- den Routing-Algorithmus: `0x00` IV-OGM heißt BATMAN_IV, `0x03` ELP oder
  `0x04` OGM2 heißt BATMAN_V. Ein bat0 kann nur einen Algorithmus. Wir
  fahren BATMAN_IV. Bei einem fremden BATMAN_V-Netz ist ohne zweites bat
  kein Beitritt möglich, v1 überspringt es.

Beitritt bei VXLAN: ein zweites vxlan6-Gerät mit der fremden VNI auf
demselben Port (`add_dynamic`, proto `vxlan6`, `vid` = fremde VNI, Peer
`ff02::15c`), darüber `batadv_hardif` mit master bat0. Der Kernel verteilt
eingehende Pakete nach VNI, beide Geräte können parallel existieren.

**Nebenbefund:** Unser site.conf hat `mesh.vxlan = false`. Unser LAN-Mesh
ist also rohes batman. Ein fremdes Netz mit ebenfalls `vxlan = false` am
selben Kabel verschmilzt mit unserem schon heute, ohne automesh. Den
Ethertype 0x4305 kann man nicht nach Community trennen. Dafür braucht es
Abschnitt 5.

## 3. Suche im WLAN (802.11s)

- 11s-Meshes erkennt man im Scan am Feld `MESH ID`, nicht an der BSSID. Die
  BSSID eines Mesh-Knotens ist seine MAC.
- Muster: jede Mesh-ID außer der eigenen. Auf Wunsch nur `.*-mesh` oder
  eine Liste aus site.conf, siehe Entscheidungen.
- **Scan nur über scan-guard.** Auf MT7915 legt jeder Scan das Radio lahm,
  siehe neanderfunk-banner/scan-guard. Dort ist die Suche über das WLAN aus,
  oder nur das andere Radio scannt.
- Beitritt: zusätzliche wifi-iface `mode mesh` mit fremder `mesh_id` als
  uci-Delta, Netz `automesh_wN` (proto `batadv_hardif`, master bat0), dann
  `flock … wifi reconf`.
- **Kanal:** 11s geht nur auf demselben Kanal. Liegt das fremde Mesh auf
  einem anderen, müsste das Radio wechseln, und der AP wechselt mit. Bei
  einer Insel ist das vertretbar, beim Verlassen kommt der alte Kanal
  zurück (Delta verwerfen).
- Fremde Meshes mit SAE-Verschlüsselung fallen weg. Gluon-Meshes sind
  standardmäßig offen.
- Algorithmus und Compat-Version sieht man erst nach dem Beitritt. Kommt
  nach 60 s kein Nachbar in `batctl n` auf `automesh_wN`, wieder austreten
  und die Mesh-ID bis zum Reboot sperren.

## 4. Umschalten im fremden Netz

| Was | Warum | Maßnahme |
|---|---|---|
| eigene Mesh-Schnittstellen | keine Brücke zwischen den Netzen | `batctl if del` (mesh-vpn, mesh_radioN, LAN-Mesh); Interfaces bleiben oben, für die Erkennung in Abschnitt 5 |
| `LOCAL_FORWARD` (gluon-ebtables-source-filter) | lässt von lokalen Clients nur Quelladressen aus `prefix4`/`prefix6` durch. Mit fremden Leases wäre alles verworfen | `ebtables -I LOCAL_FORWARD -j RETURN`, beim Verlassen wieder `-D`. Feiner: die fremden Präfixe aus RA/DHCP lernen und nur diese erlauben |
| gluon-radvd | verteilt lokal unseren `prefix6` und als RDNSS die next-node-Adresse. Clients hätten dann eine zweite Adresse ohne Route und einen DNS, der unsere (unerreichbaren) Server fragt | Dienst stoppen, beim Verlassen starten |
| filter-ra-dhcp | DHCP/RA nur aus dem Mesh, passt auch im fremden Netz | bleibt |
| next-node (local-node) | nur lokal, ebtables halten die MAC aus dem Mesh | bleibt |
| ssid-changer | sieht das fremde Gateway und schaltet auf die normale SSID zurück | gewollt, nichts tun |
| tunneldigger-watchdog | startet mesh-vpn alle 5 min neu | gewollt, siehe Abschnitt 5 |

**Nebenbefund:** `roguenets_filter` steht in templates/common/site.conf,
aber kein Paket im Image liest den Schlüssel. Er hat derzeit keine Wirkung
(wie früher preserve_channels).

## 5. Eigenes Netz wieder in Sicht: verlassen

Fremde Gateways im `gwl` sagen nichts. Manche Netze haben mehrere, und
Gateways nach Community zu sortieren bräuchte gepflegte MAC-Listen. Besser
sind Merkmale, die ohne bat0 funktionieren:

1. **respondd über Link-Local:** `gluon-neighbour-info -i <if> -d
   ff02::2:1001 -r nodeinfo` auf jeder eigenen Mesh-Schnittstelle, wie es
   die Statusseite für ihre Nachbarliste tut. Antwortet ein Knoten mit
   einem `domain_code` aus unserer Liste, ist das eigene Netz da (Feld und
   Grund siehe unten). Das funktioniert auch auf
   rohem batman am LAN, wo der Ethertype allein nichts verrät. Zu prüfen:
   antwortet respondd auf einer Schnittstelle, die nicht in bat0 hängt?
2. **11s-Peering auf dem eigenen Mesh-vif:** `iw dev meshN station dump`
   zeigt Peers im Zustand ESTAB, auch ohne batman.
3. **Eigene VXLAN-VNI:** steigender rx-Zähler am eigenen vx-Gerät (nur
   relevant, falls eine Domain `vxlan = true` fährt).
4. **mesh-vpn:** tunneldigger bekommt eine Session (Hook session.up).

Ein Treffer genügt: fremde Schnittstellen aus bat0, Deltas verwerfen,
Filter und radvd zurück, eigene Schnittstellen wieder in bat0, danach eine
Sperrzeit gegen Pendeln (z. B. 30 min kein neuer Beitritt).

Dasselbe respondd-Merkmal prüft nach dem Beitritt auch die Gegenrichtung:
Steht der `domain_code` des "fremden" Netzes in unserer Liste, ist es eine
andere eigene Domain (siehe Entscheidungen).

**Welches Feld: `domain_code`, nicht `site_code`** (Rückfrage adorfer,
02.10.). Bei uns ist der `site_code` je Domain und Firmware-Zweig
verschieden (`METAPREFIX-DOMAINNR_SITESMALL`). Die Sackgassen-Firmware hängt
noch `_EOL` an. Laut Karte vom 02.10. stehen z. B. `dus-13_dusfl` (35
Knoten) und `dus-13_dusfl_EOL` (30 Knoten) im selben Mesh, `domain` ist bei
beiden `13_dusfl`. Ein Vergleich auf den eigenen `site_code` hielte einen
EOL-Knoten im eigenen Mesh für fremd, und der Knoten bliebe im fremden Netz,
obwohl das eigene in Reichweite ist. Deshalb:

- eigen = `nodeinfo.system.domain_code` steht in der Liste aller Domains
  der Firmware-Familie (nef-, dus-, bgl-, Domainnummern 01-48, beim Bau aus
  FirmwareConfigs erzeugt);
- `site_code` nur zur Anzeige und fürs Log;
- die Supernodes melden `site_code` = `domain_code` = `ffnefdNN`
  (mesh-announce, z. B. `amalthea_ffnefd01`), gehören also mit
  `^ffnefd[0-9]+$` in die Liste. Sie sind nur über mesh-vpn Nachbarn;
- Altlasten wie `bgl`/`bgl` (ein Offline-Knoten auf der Karte) zeigen, dass
  es auch Uralt-Domaincodes gibt. Was nicht in der Liste steht, ist
  "unbekannt": kein Austritt, kein Beitritt.

## 6. Risiken

- **Massenauslösung** bei netzweitem Ausfall: abgefangen durch "seit dem
  Boot nie ein Gateway". Bleibt der Fall Stromausfall plus Supernode-Ausfall
  zugleich, dazu Zufallsverzögerung und Abschnitt 5.
- **RAM:** Ein großes fremdes Mesh bringt viele Originatoren und TT-Einträge
  mit. Auf 64-MB-Geräten vermutlich aus.
- **Sichtbarkeit:** Unser Knoten erscheint mit Hostname, Kontakt und
  Position auf der fremden Karte. Eventuell nodeinfo-Felder zur Laufzeit
  ausblenden.
- **Absprache:** Unsere Clients gehen über fremde Gateways ins Netz. Mit den
  Nachbar-Communities sollte das abgesprochen sein. Eine Erlaubnisliste in
  site.conf macht das steuerbar.

## 7. Konfiguration (Vorschlag)

    automesh = {
      enabled = false,
      delay = 900,          -- Sekunden nach Boot
      lan = true,
      wifi = true,
      allow = { },          -- leer = alle; sonst Mesh-IDs und VNIs
    },

uci-Werte tolerant lesen (1/true/yes/on), wie in allen eigenen Paketen.

## 8. Test

- LAN-Pfad in QEMU: unser Image plus das x86-Image einer fremden Community
  an einer gemeinsamen Bridge, einmal mit VXLAN, einmal mit rohem batman,
  dazu ein Gateway auf der fremden Seite.
- WLAN-Pfad: zwei echte Geräte am Testplatz, eines mit fremder Mesh-ID und
  Gateway über Kabel.
- Pflichtfälle: Beitritt, Rückkehr des eigenen Netzes (jedes Merkmal aus
  Abschnitt 5 einzeln), BATMAN_V-Netz wird übersprungen, MT7915 scannt
  nicht, Reboot stellt den Normalzustand her.

## 9. Variante: nur bekannte Netze (adorfer, 02.10.)

Statt "jedes fremde Mesh" nur Netze aus einer Liste: die eigenen Domains
der Multidomain-Firmware und/oder die Nachbarnetze des Neanderfunks. Das
nimmt das meiste Raten heraus.

Was je Netz in die Liste muss (zur Bauzeit erzeugt, z. B.
`/lib/neanderfunk/automesh/networks.json`, wenige hundert Byte je Netz):

| Feld | Wofür | Herkunft |
|---|---|---|
| `domain_code` (alle Domains des Netzes) | Abschnitt 5, eigen/fremd sicher unterscheiden; nicht `site_code`, der variiert z. B. mit `_EOL` | site.conf/domains des Netzes |
| `vni` | VXLAN-Beitritt | aus `domain_seed` vorberechnet: `md5(… "gluon-mesh-vxlan" … seed …)`, erste 3 Byte (`gluon.util.domain_seed_bytes`). Ins Image kommt nur die VNI, nicht der Seed |
| `mesh_id` je Band, Kanal | 11s-Beitritt ohne Scan-Raten, Kanalwechsel nur auf bekannten Kanal | site.conf/domains |
| `routing_algo` | BATMAN_IV/V vorab bekannt | site.conf |
| `prefix4`, `prefix6` | gezielte `LOCAL_FORWARD`-Regeln statt Filter ganz auf | site.conf |
| `vxlan` true/false | ob am LAN VXLAN oder rohes batman kommt | site.conf |

Schlüssel braucht es keine: VXLAN und Gluon-11s sind unverschlüsselt. Nur
ein Nachbar mit SAE-Mesh bräuchte dessen Passphrase, den würde man weglassen.

Folgen:

- Die Suche wird ein Abgleich: Mitlesen am LAN liefert VNI, Scan liefert
  Mesh-ID. Nur Treffer aus der Liste zählen.
- Filter präzise: Die Präfixe des Zielnetzes werden zusätzlich erlaubt, der
  Rest bleibt gesperrt.
- Die Liste muss gepflegt werden. Ändert ein Nachbar Seed, Mesh-ID oder
  Präfix, passt erst die nächste Firmware wieder.
- **Eigene Domains am LAN:** Wir fahren `vxlan = false`. Zwei eigene
  Domains am selben Kabel verschmelzen dort also ohnehin, eine VNI gibt es
  nicht. Für die Variante "eigene Multidomain" bleibt praktisch der
  WLAN-Pfad (Mesh-ID je Domain). Am LAN wird es erst nützlich, wenn eine
  Domain auf VXLAN umstellt.

## Entscheidungen (offen)

1. v1 nur Einzelknoten-Inseln, oder auch Wolken ohne Gateway?
2. Alle fremden Netze, nur die eigenen Domains oder auch Nachbarnetze aus
   einer Liste (Abschnitt 9)? Wenn Nachbarn: welche?
3. Gilt eine andere eigene Domain als "fremd" (Beitritt erlaubt) oder als
   "eigen" (Verlassen)?
4. 64-MB-Geräte ausschließen?
5. Darf der Knoten für ein fremdes 11s-Mesh den Kanal wechseln?
6. Signalisierung des Zustands: später (Punkt 5 der Ausgangsidee).

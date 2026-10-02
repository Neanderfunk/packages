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
   - **Nach Review (R7): nur Auslöser, nie Urteil.** Das Urteil fällt die
     respondd-Kette aus Abschnitt 1a. Das Schema hängt an 01-48 und
     Supernode 01-06; ein siebter Supernode fiele heraus.
   - **Echter Feldfall** (Kartenstand 29.09., Supernode-Session):
     Holzmichel-a36a (UniFi AC Mesh Pro, dus-13_dusfl) hat Gateway
     21_dias, Nexthop Holzmichel-c501 (nef-21_dias) am selben Standort.
     Das ist eine 13/21-Brücke: falsche Firmware, laut adorfer nie
     bemerkt. Die Karte kennt den Knoten seit 09.12.2025, also lief das rund
     zehn Monate unauffällig, weil beide Domains dieselben IPv4- und
     öffentlichen IPv6-Präfixe haben. Genau dafür braucht es Fall A mit
     Signalisierung. Abgleich Domain gegen Gateway-Byte über alle 1590
     Online-Knoten (meshviewer.json, 02.10. 18:31): keine weitere
     Abweichung.
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
- **Nur eine gatewaylose Wolke anbinden, nie zwei Netze mit Gateways
  verbinden.** Eine eigene Wolke ohne Gateway darf über den Randknoten
  am fremden Netz hängen ("ein Gateway ist besser als keins", adorfer
  02.10., Abschnitt 1a). Sobald auf der eigenen Seite wieder ein eigenes
  Gateway auftaucht, wäre das eine Brücke zwischen zwei Netzen mit
  Gateways: fremde DHCP-Leases bei unseren Clients, gemischte Translation
  Tables. Dann löst der Randknoten sofort auf.
- Shell und ein kleiner C-Helfer, kein Lua-Daemon (64-MB-Geräte).

## 1. Insel-Erkennung (Auslöser)

Alle Bedingungen müssen erfüllt sein:

1. Uptime ≥ `delay` (Vorgabe 900 s, einstellbar).
2. Seit dem Boot nie ein Gateway in `batctl gwl`. Eine Markerdatei in
   /tmp wird gesetzt, sobald einmal eines da war. Damit bleiben Knoten
   ruhig, die bei einem Supernode-Ausfall ihr Gateway verlieren. Sonst würde
   ein netzweiter Ausfall alle Randknoten gleichzeitig in fremde Netze
   schicken.
3. Gerade jetzt kein Gateway in `batctl gwl`, auch kein fremdes (dann hat
   schon ein anderer Knoten der Wolke angebunden).

Eigene batman-Nachbarn sind erlaubt: Auch eine Wolke ohne Gateway ist eine
Insel (Abschnitt 1a).

## 1a. Wolken ohne Gateway (adorfer, 02.10.)

Grundsatz: Wenn eine Wolke kein Gateway hat, ist ein fremdes besser als
keins. Die spannende Frage ist der Rückweg: Sieht irgendwer in der Wolke
nachträglich doch wieder ein eigenes Gateway, muss **der Randknoten**
auflösen, der angebunden hat, nicht irgendwer auf halbem Weg.

**Anbinden: genau ein Randknoten je Wolke.**
- Der Randknoten tritt bei und lässt seine eigenen Mesh-Schnittstellen in
  bat0. Dadurch bekommt die ganze Wolke das fremde Gateway.
- Alle anderen Knoten der Wolke sehen danach ein Gateway in `gwl`.
  Bedingung 3 aus Abschnitt 1 ist für sie nicht mehr erfüllt, also treten
  sie nicht zusätzlich bei.
- Gegen zwei gleichzeitige Beitritte: Zufallsverzögerung (0-120 s), direkt
  vor dem Beitritt `gwl` erneut prüfen. Sieht ein beigetretener Knoten
  hinterher ein fremdes Gateway, das **über eigene Schnittstellen** kommt
  (ein zweiter Randknoten, womöglich zu einem dritten Netz), tritt der mit
  der höheren primären MAC aus.

**Auflösen: nur der Randknoten, ereignisgesteuert.**
- Der Randknoten sieht in der zusammengelegten Wolke alle Gateways. Ob
  eines davon ein **Heimat-Gateway** ist, fragt er das Gateway selbst, statt
  es aus der MAC zu raten (MAC-Schema ist dünnes Eis, adorfer 02.10.).
  Kette, nur Standardmittel von batman-adv und respondd (am WDR3600
  durchgespielt, 02.10.):
  1. `batctl gwl`: Originator des Gateways, z. B. `02:ca:ff:ee:21:03`.
  2. `batctl tg`: die Translation-Table-Einträge dieses Originators, ohne
     Multicast (33:33:…, 01:00:5e:…). Darunter ist die MAC seiner eigenen
     bat-Schnittstelle (`f2:be:ef:00:21:03`).
  3. Daraus die EUI-64-Link-Local bilden (`fe80::f0be:efff:fe00:2103`, das
     ist auch der Router im RA).
  4. `gluon-neighbour-info -i br-client -d <ll> -p 1001 -t 3 -r nodeinfo`.
     Antwort von kallisto: `domain_code: ffnefd21`, `hostname:
     kallisto_ffnefd21`, `vpn: true`, und unter
     `network.mesh.bat21.interfaces.tunnel` genau der Originator
     `02:ca:ff:ee:21:03`.
  5. Gültig nur, wenn der Originator aus Schritt 1 in den Mesh-Interfaces
     der Antwort steht. Damit ist bewiesen, dass die Antwort von genau
     diesem Gateway kommt und nicht von irgendeinem Client dahinter.
  6. Heimat, wenn `domain_code` in einer **beim Bau gesetzten Liste** steht
     (site.conf, z. B. `automesh.home = { 'ffnefd21' }`, aus den
     Domaindaten erzeugt). Das ist eine ausdrückliche Angabe, keine
     Namensregel.
- Was nicht antwortet (fremdes Gateway ohne respondd, Link-Local nicht
  nach EUI-64), gilt als "nicht Heimat". Ein Heimat-Gateway antwortet
  immer, denn wir betreiben es.
- Fehlerrichtung: Der Weg zum Gateway (`batctl o`: über eigene oder fremde
  Schnittstelle) dient nur noch als billiger Auslöser für die Abfrage,
  nicht als Urteil. Kommt das Heimat-Gateway sogar über das fremde Netz
  (dort steckt irgendwo eine Brücke wie bei Holzmichel), löst der
  Randknoten trotzdem auf, denn sein Beitritt ist dann überflüssig.
- Abgefragt wird nur bei einem neuen Originator in `gwl` (Differenz zur
  letzten Liste), nicht jedes Gateway alle 10 s. Das sind wenige kleine
  UDP-Pakete.
- Auslöser nicht im Minuten-Takt: Der batman-adv-uevent (BATTYPE=gw,
  add/change/del) kommt nur, wenn sich das **gewählte** Gateway ändert. Ein
  neu auftauchendes eigenes Gateway ändert die Wahl wegen der Trägheit von
  `gw_sel_class 1` oft nicht. Deshalb zusätzlich, solange der Knoten
  beigetreten ist, `batctl gwl` alle ~10 s prüfen. Die Reaktion kommt also
  nach Sekunden, etwa ein OGM-Intervall plus Prüfzeit.
- Danach fremde Schnittstelle aus bat0, Laufzeitänderungen zurücknehmen,
  Sperrzeit gegen Pendeln.
- Restrisiko: Für diese Sekunden sind beide Seiten verbunden. Ein Client
  der eigenen Seite, der genau dann per DHCP anfragt, könnte eine fremde
  Lease bekommen. batman-adv schickt DHCP aber nur an das gewählte Gateway,
  und das bleibt bei `gw_sel_class 1` erst einmal das bisherige. Klein,
  aber nicht null.

**Die Knoten auf halbem Weg halten still.**
- Ein Knoten der Wolke, dessen VPN zurückkommt, sieht das fremde Netz in
  seinem Mesh. Ohne Sonderregel würde er nach Fall A sein LAN-Mesh trennen
  und damit die eigene Wolke zerschneiden.
- Regel: Fall A wartet nach dem Erkennen eine Frist (Vorschlag 120 s) und
  prüft dann neu. In der Zeit hat der Randknoten längst aufgelöst, das
  fremde Netz ist weg, Fall A entfällt.
- Zusätzlich fragt der Knoten vor dem Trennen über respondd auf bat0, ob
  ein Knoten der eigenen Domain `automesh: joined` meldet. Wenn ja, wartet
  er weiter auf ihn, als Notbremse mit Obergrenze (z. B. 10 min), dann
  trennt er doch.
- Ergebnis: Wer beigetreten ist, löst auch auf. Fall A trifft nur echte
  Fehlsteckungen, bei denen niemand `joined` meldet.

**Massenauslösung** bleibt durch Bedingung 2 aus Abschnitt 1 gebremst ("seit
dem Boot nie ein Gateway"): Bei einem Supernode-Ausfall haben die Knoten
vorher Gateways gesehen und bleiben ruhig.

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
| eigene Mesh-Schnittstellen | die gatewaylose Wolke soll das fremde Gateway mitbenutzen (Abschnitt 1a) | bleiben in bat0; aufgelöst wird, sobald ein eigenes Gateway auftaucht |
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

**Hauptmerkmal seit Abschnitt 1a:** ein Gateway in `gwl`, das sich per
respondd als Heimat-Gateway ausweist (Kette in Abschnitt 1a). Die folgenden Merkmale ergänzen
es, vor allem für den Fall, dass das eigene Netz ohne Gateway in Sicht kommt
(dann ist Zusammenlegen ohnehin harmlos) oder zur Bestätigung.

Fremde Gateways im `gwl` sagen nichts. Manche Netze haben mehrere, und
Gateways nach Community zu sortieren bräuchte gepflegte MAC-Listen. Besser
sind Merkmale, die ohne bat0 funktionieren:

1. **respondd über Link-Local:** `gluon-neighbour-info -i <if> -d
   ff02::2:1001 -r nodeinfo` auf jeder eigenen Mesh-Schnittstelle, wie es
   die Statusseite für ihre Nachbarliste tut. Antwortet ein Knoten mit
   `site_code`/`domain_code` aus `automesh.home`, ist das eigene Netz da
   (siehe unten). Das funktioniert auch auf
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

**Eine andere Domain der eigenen Familie gilt als fremd** (Entscheidung
adorfer, 02.10.): Beitritt erlaubt (Fall B), mit VPN wird getrennt (Fall A).
Das passt zum Hauptfall, denn die Domain-Brücke zwischen zwei eigenen
Domains ist genau das, was verhindert werden soll.

**Welches Feld: `domain_code`, nicht `site_code`** (Rückfrage adorfer,
02.10.). Bei uns ist der `site_code` je Domain und Firmware-Zweig
verschieden (`METAPREFIX-DOMAINNR_SITESMALL`). Die Sackgassen-Firmware hängt
noch `_EOL` an. Laut Karte vom 02.10. stehen z. B. `dus-13_dusfl` (35
Knoten) und `dus-13_dusfl_EOL` (30 Knoten) im selben Mesh, `domain` ist bei
beiden `13_dusfl`. Ein Vergleich auf den eigenen `site_code` hielte einen
EOL-Knoten im eigenen Mesh für fremd, und der Knoten bliebe im fremden Netz,
obwohl das eigene in Reichweite ist. Deshalb:

- **Korrektur nach Review (R1/R2):** Unsere Knoten melden gar keinen
  `domain_code`. Wir bauen Single-Domain-Firmware je Template, Gluon setzt
  `domain_code` nur bei Multidomain. Am WDR3600 steht in `nodeinfo.system`
  nur `site_code: nef-21_dias`; das `domain` der Karte setzt yanic selbst
  zusammen. Deshalb gilt **eine** Definition: eigen = `site_code` oder
  `domain_code` der Antwort steht in der beim Bau erzeugten Liste
  `automesh.home`, z. B. `{ 'nef-21_dias', 'nef-21_dias_EOL', 'ffnefd21' }`.
  Normale Knoten, Sackgasse und Supernodes stehen damit ausdrücklich drin;
  jede andere Domain, auch aus der eigenen Familie, ist fremd;
- die Supernodes melden `site_code` = `domain_code` = `ffnefdNN`
  (mesh-announce, z. B. `amalthea_ffnefd01`). Eigen ist also auch
  `ffnefd<eigene Nummer>`, z. B. `ffnefd21`. Sie sind nur über mesh-vpn
  Nachbarn;
- Altlasten wie `bgl`/`bgl` (ein Offline-Knoten auf der Karte) zeigen, dass
  es auch Uralt-Domaincodes gibt. Sie sind fremd wie alles andere, das
  nicht die eigene Domain ist (Sperrliste beachten).

## 6. Risiken

- **Massenauslösung** bei netzweitem Ausfall: abgefangen durch "seit dem
  Boot nie ein Gateway". Bleibt der Fall Stromausfall plus Supernode-Ausfall
  zugleich, dazu Zufallsverzögerung und Abschnitt 5.
- **RAM:** Ein großes fremdes Mesh bringt viele Originatoren und TT-Einträge
  mit. Auf 64-MB-Geräten vermutlich aus.
- **Sichtbarkeit und Absprache: durch das Pico Peering Agreement gedeckt**
  (PPA v1.0, picopeer.net, Leitlinie für alle Freifunk-Communities;
  nachgelesen 02.10. auf Hinweis von adorfer):
  - Die Präambel nennt als Ziel ausdrücklich, "diese Netzwerkinseln
    miteinander zu verbinden". Der Abschnitt "PPA in der Praxis" sieht
    "automatische Vernetzung" vor. automesh ist genau dieser Fall.
  - §1 Freier Transit: Der Eigentümer bietet freien Transit an. Transit ist
    laut Begriffserklärung der Datenaustausch "in ein Netzwerk hinein,
    heraus oder durch ein Netzwerk hindurch". Der Weg über fremde Gateways
    braucht also keine Einzelabsprache.
  - §2 Offene Kommunikation: Der Eigentümer veröffentlicht alles, was für
    die Verbindung nötig ist (Mesh-ID, Kanal, Seed bzw. VNI, site.conf),
    und ist mindestens per E-Mail erreichbar. Dass unser Knoten mit
    Hostname und Kontakt auf der fremden Karte erscheint, ist gewollt: So
    kann die andere Community den Betreiber erreichen. Neu ist das ohnehin
    nicht, Sammelkarten zeigen unsere Knoten schon heute, und der
    Kontakt-Dialog im Config-Mode sagt, dass der Hinweis öffentlich im
    Internet einsehbar ist (Koordinaten nur mit `share_location`). Nichts
    ausblenden.
  - Grenzen: §3 erlaubt, den Dienst jederzeit ohne Erklärung einzuschränken
    oder einzustellen. §4 erlaubt eine eigene Nutzungsrichtlinie. DHCP gilt
    laut Begriffserklärung als "zusätzlicher Dienst", nicht als Transit.
    Daraus folgt: keine Erlaubnisliste, sondern eine **Sperrliste** für
    Netze, die automatisches Beitreten ablehnen. Und wenn das fremde Netz
    keinen Dienst liefert (kein DHCP, kein Gateway), ist das sein Recht.
    Der Knoten tritt dann nach Frist wieder aus.

## 7. Konfiguration (Vorschlag)

    automesh = {
      enabled = false,
      delay = 900,          -- Sekunden nach Boot
      lan = true,
      wifi = true,
      deny = { },           -- Netze, die automatisches Beitreten ablehnen (PPA §3/§4):
                            -- domain_code, Mesh-IDs, VNIs
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

## 10. Review Buildsystem-Session (02.10., Stand 6fa200f) und Auflösungen

Nummern wie im Review. "Festgelegt" heißt: so in den Entwurf übernommen.
"Entscheidung offen" heißt: adorfer entscheidet.

**Begriffe (R3), festgelegt:**
- **Wolke** = alle Originatoren in bat0, die ohne automesh-Schnittstelle
  erreichbar sind.
- **Insel** = Wolke ohne Gateway. Ein Einzelknoten ist eine Wolke der
  Größe 1. Die Einleitung ("kein eigener Nachbar") ist damit überholt.
- **Heimat-Gateway** = Gateway, dessen respondd-Antwort die Kette aus 1a
  besteht und dessen `site_code`/`domain_code` in `automesh.home` steht.
- **Familie** = Netze, deren Präfixe in unseren Filtern schon enthalten sind
  (10.0.0.0/8, 2a03:2260::/32). Erkennbar am RA-Präfix und an der
  DHCP-Lease des fremden Netzes.

1. **Kein domain_code auf eigenen Knoten:** festgelegt, siehe Abschnitt 5
   (Liste `automesh.home`, Vergleich auf `site_code` oder `domain_code`).
2. **Zwei Heimat-Definitionen:** festgelegt, nur noch die Liste.
3. Siehe Begriffe.
4. **Marker "seit Boot ein Gateway gesehen":** Vorschlag: Der Marker wird
   nur von einem **Heimat**-Gateway gesetzt. Die Heimat-Prüfung läuft dafür
   auch im Ruhezustand, aber nur bei Änderungen in `gwl` (neuer
   Originator), das kostet fast nichts. Damit kann nach einem Auflösen
   wieder ein Randknoten entstehen, und die Wolke bleibt nicht bis zum
   Weekly Reboot dunkel. *Entscheidung offen.*
5. **Fall B ohne Auslöser:** festgelegt, eigener Zustand `merged`:
   "Gateway in `gwl`, keines ist Heimat-Gateway, kein VPN". Er setzt die
   Signalisierung und, außerhalb der Familie, §4. Randknoten am Kabel ist
   jeder Knoten, der den fremden batman-Nachbarn direkt auf `mesh_other`
   hat (beide Enden möglich). Beide melden `merged`, damit greift die
   Notbremse von 1a auch hier.
6. **Filter-Widerspruch:** festgelegt: Familie = nichts am Filter, außerhalb
   der Familie = §4 (fremde Präfixe aus RA/DHCP zusätzlich erlauben).
7. Festgelegt, siehe Fall A Kriterium 1.
8. **"Antwortet nicht = nicht Heimat" ist die gefährliche Richtung:**
   festgelegt: 3 Versuche mit je 3 s. Gateways, die nicht antworten, werden
   im festen Takt (60 s) erneut gefragt, solange der Knoten `joined` oder
   `merged` ist, nicht nur bei neuem Originator.
9. **Wackelkontakt bei Fall A:** festgelegt: Neuprüfung nach hotplug
   frühestens 10 min nach dem letzten Trennen.
10. **Heimat-Gateway kommt und geht:** festgelegt: Heimat-Gateway gilt erst
    nach 2 min Stabilität als "da" (Hysterese). Sperrzeit nach Auflösen
    exponentiell: 5, 10, 20, 40 min, Obergrenze 2 h, zurück auf 5 min nach
    24 h ohne Auflösen.
11. **Zwei Randknoten an verschiedenen fremden Netzen:** festgelegt: Jeder
    beigetretene Knoten prüft zusätzlich, ob über eigene Schnittstellen ein
    Gateway kommt, das sich als **anderes** fremdes Netz ausweist (anderer
    `site_code`). Dann tritt der mit der höheren MAC aus, ohne Zufallsfrist.
    Fällt der verbleibende Randknoten aus, darf der ausgetretene wieder
    beitreten: Seine Sperre gilt nur gegen dasselbe Netz, und der Marker
    stört nach Punkt 4 nicht.
12. **Fall A und Fall B in einer Wolke:** Das Zerfallen ist gewollt. Der
    Teil um X ist danach eine Wolke mit fremdem Gateway und ohne Heimat, X
    meldet `merged`. Niemand wird zusätzlich Randknoten, weil dort schon ein
    Gateway in `gwl` steht.
13. **Reboot mitten in Fall A:** festgelegt: Fall A hängt nicht an `delay`.
    Er prüft ab dem ersten Gateway sofort, denn er ist Schutz, kein
    Beitritt.
14. **Kette eigen -> fremd1 -> fremd2:** festgelegt: Ist ein Knoten
    `joined` und `gwl` 60 s lang leer, tritt er aus und geht zurück auf
    `island`.
15. **autoupdater-wifi-fallback:** festgelegt: automesh startet keinen
    WLAN-Beitritt, solange der Fallback aktiv ist. Umgekehrt muss der
    Fallback `joined` respektieren (Zustandsdatei in /tmp prüfen; ob das
    ohne Patch am Gluon-Paket geht, wird bei der Umsetzung geprüft).
16. **hotfix-Checks (IfNoWificlient, watchdog, check_wifi_firmware):**
    festgelegt: gemeinsames `flock` auf `/var/lock/neanderfunk-wifi.lock`
    (wie ap-timer) und eine Zustandsdatei `/tmp/automesh.state`. Die
    Checks lassen das WLAN in Ruhe, solange der Zustand `probing` ist.
    Ein Beitritt gilt erst nach 60 s **ohne** zwischenzeitlichen wifi-Neustart
    als gescheitert.
17. **C-Helfer:** festgelegt: eigenes kleines Paket (z. B.
    `neanderfunk-automesh-sniff`), damit die Größe in Flash und Overlay
    messbar ist. Kleinster Overlay derzeit C6 v2 mit 576 KB.
18. **ssid-changer im Zustand `joined`/`merged`:** Vorschlag: Er pausiert
    das Umschalten auf die Offline-SSID, solange ein Gateway in `gwl` steht,
    weil Internet über das fremde Netz geht, auch bei schlechter TQ.
    *Entscheidung offen.* Gemeinsames `flock` wie in Punkt 16 gilt auch
    für ssid-changer, scan-guard und ap-timer.

## Entscheidungen

1. ~~Einzelknoten oder auch Wolken?~~ Entschieden 02.10.: auch Wolken, ein
   Gateway ist besser als keins. Rückweg nur über den Randknoten
   (Abschnitt 1a).
2. ~~Welche Netze?~~ Entschieden 02.10.: alle, außer denen auf der
   Sperrliste (`deny`, Abschnitt 7). Die Liste bekannter Netze aus
   Abschnitt 9 ist nur noch technische Hilfe (Kanal, Algorithmus, Präfixe
   vorab bekannt), keine Voraussetzung für den Beitritt.
3. ~~Andere eigene Domain fremd oder eigen?~~ Entschieden 02.10.: fremd.
4. ~~64-MB-Geräte ausschließen?~~ Entschieden 02.10.: ja, sonst wird es mit
   dem nötigen Tooling zu eng. Umsetzung wie bei usteer und whisperer:
   Paket in image-customization für die lowmem-Gruppen nicht ins Image.
   Folge: Ein 64-MB-Knoten erkennt selbst keine Domain-Brücke. Die Trennung
   übernimmt dann ein Nachbar mit mehr RAM und VPN (Fall A wirkt von beiden
   Seiten, eine Seite genügt).
5. ~~Kanalwechsel für ein fremdes 11s-Mesh?~~ Entschieden 02.10.: ja. Nur
   zur Laufzeit (uci-Delta plus `wifi reconf`), der AP wechselt mit. Beim
   Verlassen wird das Delta verworfen und der alte Kanal kehrt zurück, ein
   Reboot tut dasselbe. preserve_channels und channel-Befehl bleiben
   unberührt, weil nichts committet wird.
6. Signalisierung: Entschieden 02.10.: mit der Umsetzung sofort an drei
   Stellen, nicht später:
   - neanderfunk-respondd: Feld in statistics (z. B. `automesh: {state,
     domain, iface, since}`), damit Karte und Kollektor es sehen;
   - Statusseite: Zeile über gluon-patches-packages (eigene i18n);
   - Login-Banner (neanderfunk-banner, profile.gluon/nodestatus): Hinweis
     beim SSH-Login.
   Zustände mindestens: `idle`, `island`, `probing`, `joined <netz>`,
   `merged <netz>` (Fall B, R5), `lan_cut <netz>`.
7. Marker nur durch Heimat-Gateway? (R4) *offen*
8. ssid-changer pausiert in `joined`/`merged`? (R18) *offen*

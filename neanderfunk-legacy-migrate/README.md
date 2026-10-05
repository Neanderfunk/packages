neanderfunk-legacy-migrate
==========================

Upgrade-Skripte für große Sprünge auf Gluon 2025.1, etwa wenn wir die Knoten
einer Community übernehmen, die noch auf 2014.4, 2015.1, 2016.2 oder 2017.1
steht.
Gluon hat die alten Konfigurationsmigrationen über die Jahre entfernt. Ohne
sie kommt so ein Knoten zwar hoch, aber ohne WLAN (kein `band`), ohne Mesh auf
WAN/LAN, mit falschem VPN-Schalter und am fremden Autoupdater.

Dazu kommt auf x86 eine dauerhafte Bindung von LAN/WAN an die Netzwerkkarte
statt an `ethN`.

Hintergrund und Pfade: router-werkstatt `docs/gluon-migrationspfade.md`
(Abschnitt „Noch älter“) und `docs/gluon-historie.md`.

Das Paket landet in jedem 2025.1-Image. Bei Herkunft ab 2022.1 (unsere Flotte)
ändert es nichts außer der x86-Bindung (siehe Tests).

Ablauf beim Upgrade
-------------------

Gluon führt beim ersten Start nach einem Update (und bei jedem
`gluon-reconfigure`) alle Dateien in `/lib/gluon/upgrade/` in alphabetischer
Reihenfolge aus. Die Nummer vorne im Namen legt also fest, wann ein Skript
läuft: `020z-...` kommt nach Gluons `020-interfaces` und vor
`021-interface-roles`. So hängen sich die Skripte dieses Pakets zwischen
Gluons eigene:

| Skript | wann | was |
|---|---|---|
| `009-neanderfunk-legacy-primary-mac` | x86, einmal | fehlende `primary_mac` aus der alten Konfiguration, vor Gluons `010-primary-mac` |
| `010-primary-mac` | Gluon | setzt `primary_mac` (node_id), wenn sie fehlt |
| `015-neanderfunk-legacy-version` | einmal, nur Herkunft 2014.x | `gluon_version` aus `/lib/gluon/version/core`, sonst gilt der Knoten als neu (Hostname, WAN-proto) |
| `018z-neanderfunk-ifbind-anchor` | x86, einmal | alte Aufzählung nachbauen, WAN, LAN und weitere Karten an die Karte binden, nur bei Herkunft vor 2022.1 |
| `019-migrate-interface-order` | Gluon | tauscht LAN/WAN nach alter Treiber-Ladereihenfolge (ab 2022.1) |
| `020-interfaces` | Gluon | setzt `lan_ifname`/`wan_ifname` neu (x86: eth0/eth1) |
| `020a-neanderfunk-ifbind` | x86, **jedes Mal** | `lan_ifname`/`wan_ifname` und `gluon.iface_extra_*` auf die gebundenen Karten |
| `020z-neanderfunk-legacy-migrate` | einmal, nur alte Herkunft | Konfiguration migrieren (unten) |
| `021-interface-roles` | Gluon | legt fehlende `gluon.iface_*` mit Site-Vorgaben an |
| `030-system` | Gluon | Hostname nur bei Neuinstallation (deshalb `015`) |
| `990-neanderfunk-orphan-configs` | **jedes Mal** | verwaiste Konfigurationen löschen (unten) |

### Altkonfiguration (020z)

Läuft nur, wenn `gluon_version` noch eine Version vor 2022 nennt oder die
Konfiguration alte Merkmale hat (`hwmode` ohne `band`, `firewall.client`,
`fastd.mesh_vpn` ohne `gluon.mesh_vpn`). Danach steht der Vermerk
`/lib/gluon/core/sysconfig/neanderfunk_legacy_migrated` (alte Version), und das
Skript läuft nicht noch einmal.

0. `gluon-simple-tc` heißt seit 2016.2 `simple-tc`: umbenennen. Das läuft vor
   der Herkunftsprüfung, also auf jedem Knoten; ab 2016.2 fehlt die Datei, dann
   passiert nichts.
1. WLAN: `hwmode` → `band`. IBSS-Mesh (`ibss_radioX` bis 2019.1, bei 2015.1
   `mesh_radioX` mit `mode adhoc`) wird zu `mesh_radioX` an, damit der Knoten
   die Rolle mesh bekommt.
2. Rollen aus `mesh_wan`/`mesh_lan` (`auto`/`disabled`), ausgehend von den
   Site-Vorgaben. Gluon 2014.x kennt noch kein `network.mesh_lan`; steht dann
   ein Ethernet-Port in der alten Client-Bridge (`client.ifname` als String
   `'eth0.1 bat0'`), ist LAN `client`. `mesh_lan` aus heißt bis 2021.1 immer: LAN steckt in der
   Client-Bridge, also Rolle `client`. Die alte Client-Bridge liest das
   Skript aus `network_gluon-old`: `11_network-migrate-bridges` (OpenWrt
   uci-defaults, läuft vor `zzz-gluon-upgrade`) hat `client.ifname` dort nach
   `device br-client`/`ports` verschoben. Bei 2014.4 bleiben die Ports dabei
   lesbar; bei 2015.1 stand danach nur `br-client` selbst als Port, dann
   entscheidet allein `mesh_lan`.
3. VPN: `gluon.mesh_vpn` aus `fastd`/`tunneldigger` `enabled` und dem
   Bandbreitenlimit aus `simple-tc` bzw. `limit_bw_down`.
4. `gluon-core` `preserve_channels` → `gluon.wireless`.
5. Koordinaten mit Leerzeichen trimmen.
6. Alte Zonen `firewall.client`, `firewall.local_node`, `dhcp.client` löschen,
   `sysctl.conf` mit `ip_forward=1` auf Vorgabe zurück.
7. Autoupdater: einen fremden `settings.branch` löschen (dann gilt der
   Site-Default) und alle Branch-Sektionen löschen, die unsere Site nicht kennt.
   Sektionen mit Namen aus unserer Site schreibt Gluons `500-autoupdater`
   ohnehin komplett neu, auch wenn der fremde Branch gleich heißt (etwa
   „stable“). Fremde Mirrors und Schlüssel bleiben also nicht hängen.
8. Fremde SSH-Schlüssel bleiben (`100-authorized-keys` hängt nur an). Das
   Skript meldet nur die Anzahl; entfernen ist eine Entscheidung der Betreiber.

### x86: LAN/WAN an die Karte gebunden

Gluon setzt auf x86 bei jedem Reconfigure `lan=eth0`, `wan=eth1`, also nach
der Reihenfolge, in der die Treiber laden. Die ändert sich zwischen
Kernel-Versionen; im Feld sind LAN und WAN bei größeren Sprüngen mehrfach
getauscht worden.

Gebunden wird je Rolle an zwei Merkmale, gespeichert als `"<mac> <pci>"` in
`/lib/gluon/core/sysconfig/neanderfunk_bind_lan` und `neanderfunk_bind_wan`:

- die Hardware-MAC, nur lesbar, solange Gluon sie nicht überschrieben hat
  (`addr_assign_type` 0; beim Reconfigure nach einem Update ist sie noch echt),
- den PCI-Pfad, immer lesbar, aber nach Umstecken der Karte veraltet.

Gesucht wird erst nach MAC, dann nach PCI-Pfad. Sind die Karten nicht
eindeutig zu finden, bleibt es bei Gluons Zuordnung (Meldung „bound cards not
found, keeping“).

- **Herkunft vor 2022.1:** `018z` baut nach, welche Karte bei der alten
  Firmware eth0, eth1 ... hieß. OpenWrt 14.07 bis 19.07 (Gluon 2014.4 bis
  2021.1) zählen auf x86 so: erst fest eingebaute Treiber (virtio_net,
  vmxnet3, xen-netfront; auf geode zusätzlich 8139cp/8139too, natsemi,
  via-rhine), dann `/etc/modules-boot.d` (tg3), dann `/etc/modules.d`, nach
  Dateinamen sortiert (`20-natsemi` < `35-e1000` < `35-igb` < `35-ixgbe` <
  `3c59x` < `8139too` < ... < `pcnet32` < `r8169`), innerhalb eines Treibers
  nach PCI-Adresse. Quelle: `netdevices.mk` und `target/linux/x86/*/config-*`
  der fünf Versionen, die Regeln sind dort gleich. Aus der alten
  network-Konfiguration (`network_gluon-old`) kommt, wofür jede ethN benutzt
  wurde: WAN-Bridge, Mesh (`batadv`/`gluon_mesh`, nur wenn an), Client-Bridge.
  Gebunden werden:
  - WAN: `wan_ifname`, gegengeprüft mit der alten WAN-Bridge,
  - LAN: `lan_ifname`, sonst die Mesh-Karte, sonst die Client-Karte, sonst die
    erste übrige,
  - jede weitere benutzte Karte als `gluon.iface_extra_<alter Name>` mit ihrer
    alten Rolle (client bzw. mesh) und `neanderfunk_bind`; `020a` führt deren
    Namen genauso nach wie LAN/WAN. Gluons `019` tauscht nur eth0/eth1.

  `019` wird dann übersprungen, damit nicht doppelt getauscht wird.

  **Widerspruch, dann nichts binden** (Vermerk
  `/lib/gluon/core/sysconfig/neanderfunk_bind_conflict` mit Grund, Meldung bei
  jedem Reconfigure): unbekannter Treiber; die alte Konfiguration nennt eine
  ethN, die es nicht mehr gibt (eine Karte fehlt, dann stimmt die alte
  Nummerierung nicht mehr); `wan_ifname` und alte WAN-Bridge passen nicht
  zusammen; `primary_mac` zeigt bei einer zweikartigen Erstinstallation auf
  die Karte, die wir für die alte eth1 halten. `020a` schreibt dann auch nicht
  den Stand nach board.json fest.
- **`primary_mac` fehlt** (Sicherungen aus 2014.4 haben sie nicht): Gluons
  `010` nähme die MAC des neuen eth0, die node_id wechselte. `009` nimmt
  vorher `network.client.macaddr` der alten Konfiguration, dort hat die alte
  Firmware bei jedem Upgrade `primary_mac` eingetragen (2014.4:
  `310-gluon-mesh-batman-adv-core-mesh`); sonst die MAC der alten eth0.
- **Herkunft ab 2022.1:** `019` entscheidet (es kennt die echte alte
  Ladereihenfolge), `020a` bindet danach den Stand.
- **Ohne Bindung** (Neuinstallation, mehr als zwei Karten) bindet `020a` den
  aktuellen Stand. Ab dann bleiben die Rollen bei ihrer Karte, auch wenn sich
  `ethN` später ändert.

`020a` läuft dauerhaft bei jedem Reconfigure auf jedem x86-Knoten.

**Falsche Bindung korrigieren** (am Knoten, danach `gluon-reconfigure` und
Neustart). Rollen tauschen:

```sh
cd /lib/gluon/core/sysconfig
t=$(cat neanderfunk_bind_lan); cat neanderfunk_bind_wan > neanderfunk_bind_lan; echo "$t" > neanderfunk_bind_wan
```

Oder beide Dateien löschen. Dann bindet `020a` beim nächsten Reconfigure die
Zuordnung, die Gluon gerade gewählt hat. Nach einem Widerspruch
(`neanderfunk_bind_conflict`) erst LAN/WAN prüfen, dann die Datei löschen;
beim nächsten Reconfigure wird der dann gültige Stand gebunden.

Grenzen
-------

- CPE210/510 v1 und EdgeRouter X scheitern schon vorher am alten sysupgrade
  bzw. am Flash-Layout. Das gehört in die Manifest-Auswahl, nicht in dieses
  Paket.
- IBSS-Mesh: Nach der Migration meshen die Knoten per 802.11s. Zu Nachbarn,
  die noch nicht migriert sind, geht das WLAN-Mesh verloren, bis sie
  nachziehen.
- x86 mit Herkunft vor 2022.1: Die Rekonstruktion setzt voraus, dass dieselben
  Karten drinstecken wie unter der alten Firmware. Wurde eine Karte getauscht
  (anderer Treiber), stimmt die alte Reihenfolge nicht; fehlt eine, greift der
  Widerspruch.
- Ein manuelles `gluon-reconfigure` im laufenden Betrieb sieht die echten MACs
  nicht (Gluon hat sie überschrieben); haben sich dann auch die PCI-Plätze
  geändert, meldet `020a` "bound cards not found, keeping" und lässt alles,
  wie es ist. Beim Reconfigure nach einem Update sind die MACs echt.
- **Echtes sysupgrade von Gluon bis 2021.1 auf die heutigen x86-Images
  verliert die ganze Konfiguration**: OpenWrt bis 19.07 mountet Partition 1
  fest als ext4, die Images sind seit der EFI-Umstellung `-squashfs-combined-efi`
  mit FAT (Gluon #2967). Dieses Paket greift dort erst mit einem Image mit
  ext4-Boot; die Entscheidung darüber liegt bei Buildsystem/adorfer.
- Der Fall, dass Gluons `019` auf x86 selbst tauscht, ließ sich in QEMU nicht
  erzeugen (igb lädt als Boot-Modul).

Tests
-----

Emulation (QEMU malta-be, Gluon-Rootfs mit RAM-Overlay, Aufbau Buildsystem),
26100423bro WDR3600, Sicherungen echter Altknoten (05.10.2026):

- 2014.4 (ffsb, 1043 v1, kein `gluon_version`, LAN `eth0.1` in `client.ifname`):
  `gluon_version` v2014.4 erkannt, Hostname bleibt, LAN `client` und in der
  Client-Bridge; vorher Hostname auf Vorgabe und LAN `mesh`.
- 2017.1.7 (ffac) und 2020.2.2 (12_dusuk): Rollen wie mit Version 1.


QEMU x86-64, Ziel 26100423bro, echte Sicherung eines 2014.4-Knotens
(v2014.4-57-g8f853aa, `primary_mac` fehlt; alt eth0 e1000 WAN, eth1 igb
Mesh-LAN, eth2 pcnet in der Client-Bridge), Übergabe per `sysupgrade.tgz` auf
der Boot-Partition, neue Skripte im Archiv (05.10.2026):

- 3 Karten (neu: igb eth0, e1000 eth1, pcnet eth2): WAN e1000, LAN igb mesh,
  `iface_extra_eth2` pcnet client in br-client, `primary_mac` = pcnet aus
  `client.macaddr` (alte node_id 024e46140401); `gluon-reconfigure` danach
  unverändert.
- 2 Karten (pcnet, e1000; alte Konfiguration ohne eth2): WAN e1000, LAN pcnet
  mesh. Vorher landete WAN auf der alten Mesh-Karte.
- Konfiguration mit 3 Karten auf 2 Karten: Widerspruch "old config uses eth2,
  only 2 cards now", nichts gebunden.
- sysupgrade mit danach umgesteckten Karten (andere PCI-Plätze): LAN, WAN und
  die dritte Karte per MAC wiedergefunden, PCI-Pfade nachgetragen.

Offen: Ende-zu-Ende auf x86 mit echtem sysupgrade aus Barrier Breaker auf das
MBR-Image und danach auf das EFI-Image (Buildsystem, nach dem nächsten Lauf);
ein Sprung auf echter Router-Hardware.

Frühere Tests, QEMU x86-64, Ziel 26100312bro, Altkonfigurationen echter Knoten
(x86-Bindung damals noch mit `primary_mac` als Anker):

- 2017.1.8: Rollen, `band`, VPN/Limit, `preserve_channels`, Zonen,
  `sysctl.conf`, Autoupdater; x86-Bindung bei gedrehter Kartenreihenfolge
  (WAN bleibt an der Karte), zweites Update mit erneut gedrehter Reihenfolge
  und veralteten PCI-Pfaden (MAC gewinnt).
- 2015.1.2: Mesh auf WAN, LAN client (eth0 in br-client), IBSS → mesh,
  `simple-tc` umbenannt mit Limit 8000/500, VPN, Koordinaten, Zonen,
  Autoupdater.
- 2023.2.6 Feldstand (igb + e1000, VPN mit Limit, WAN uplink+mesh, LAN mesh):
  mit und ohne Paket dasselbe Ergebnis; kein Legacy-Vermerk, nur die
  Bindungsdateien kommen dazu.

Verwaiste Konfigurationen (`990-neanderfunk-orphan-configs`)
-----------------------------------------------------------

Läuft bei jedem Upgrade auf jedem Knoten. Löscht `/etc/config/alfred`,
`luci`, `ucitrack`, `socat` und `keep_settings`, wenn das zugehörige Programm
nicht im Image ist (`/usr/sbin/alfred`, luci-base, `/usr/bin/socat`;
`keep_settings` ist ein Fremdpaket alter Communities). Solche Dateien schleppt
ein sysupgrade aus alten Firmwares mit, oder aus einem Image, das das Paket
noch hatte (Sackgasse: socat seit 04.10.2026 raus). Bewusst nicht:
`/etc/config/fastd` mit dem alten Schlüssel (adorfer 05.10.2026) und
`dhcp.local_client` (legt Gluon selbst an). Getestet in der Emulation mit einer
2014.4-Sicherung: alfred, luci, ucitrack gelöscht, fastd bleibt.

Manifeste für alte Knoten
-------------------------

Das Paket übernimmt die Konfiguration beim Sprung. Damit ein Altknoten den
Sprung überhaupt angeboten bekommt, muss er das Manifest lesen können und
darin seinen Modellnamen finden. Dafür liegen in `contrib/` die Werkzeuge
(siehe `contrib/README.md`). Dieser Zweig ist das Ziel für alle Geräte, die Gluon 2025.1 unterstützt; 4/32-Geräte gehen in die Sackgasse (Zweig `v2021.1.x`), ein zusammengeführtes Manifest bietet jedem Modell die passende Linie an.

Welche Zeilen ein Knoten liest:

| Firmware des Knotens | liest im Manifest |
|---|---|
| Gluon bis 2016.2.3 | `<modell> <version> <sha512> <datei>` (4 Felder), die letzte passende Zeile |
| Gluon 2016.2.4 bis 2017.1 | `<modell> <version> <sha256> <datei>` (4 Felder, 64 Zeichen Prüfsumme) |
| Gluon 2018.1 bis heute | `<modell> <version> <sha256> <größe> <datei>` (5 Felder); Gluon ab 2021.1 erzeugt nur noch diese |

Die Unterschriften decken alles vor `---` ab, egal welches Format.
`manifest-altformat.sh` bzw. `manifeste-zusammenfuehren.sh` schreiben zu
jeder 5-Feld-Zeile die beiden 4-Feld-Zeilen, und für alte Modellnamen (z. B.
`tp-link-tl-wr1043n-nd-v2` aus der ar71xx-Zeit, `x86-kvm`, `x86-virtualbox`)
dieselben Zeilen mit dem alten Namen. Die Zuordnung alt -> neu steht als
Tabelle in den Skripten, eigene Ergänzungen per `-a`.

Ubiquiti AirMax XW: Gluon hat die Aliase der alten ar71xx-Namen beim
AirMax-Ausbau entfernt (Gefahr eines schreibgeschützten Flash) und nicht
zurückgeholt. Die Werkzeuge führen sie wieder (`ubiquiti-loco-m-xw`,
`ubiquiti-nanostation-loco-m2/m5-xw` -> `ubiquiti-nanostation-loco-m-xw`,
`ubiquiti-nanostation-m2/m5-xw` -> `ubiquiti-nanostation-m-xw`): Ein Knoten,
der schon Gluon fährt, hat beschreibbaren Flash, und eine NanoStation XW in
RDV ist per handgemachtem Manifest aus der Sackgasse nach 2023.1.5 gesprungen und
ohne Eingriff wieder online gekommen (Entscheidung adorfer, 05.10.2026).

Ohne Weg per Autoupdater (bewusst nicht im Manifest, von Hand umstellen):

- **CPE210/220/510/520 v1:** Das sysupgrade von Gluon 2016.2 lehnt das
  ath79-Image ab, nachdem der Autoupdater das Netz schon gestoppt hat; der
  Knoten bliebe bis zum Stromreset offline. Nur die 5-Feld-Zeile.
- **x86 mit Gluon 2014.x:** `get_image_name()` liefert dort auf x86 `nil`, der
  Autoupdater bricht ab ("doesn't support this hardware model").
- **Xen-Gäste (`x86-xen`, bis Gluon 2016.2):** Das Ziel gibt es seit 2017.1
  nicht mehr; ein heutiges x86-Image bootet dort vermutlich nicht
  (paravirtualisiert gegen GRUB). Ungetestet, daher kein Alias.
- **Netgear WNDR3700 v4:** Upgrade-Pfad nie gegangen (Kernelpartition
  gewachsen, Gluon e1437781).
- **x86 mit Gluon bis 2021.1 braucht das MBR-Image.** Die heutigen x86-Images
  (EFI, Bootpartition FAT) verlieren beim sysupgrade aus OpenWrt bis 19.07
  die ganze Konfiguration (Gluon #2967). Die Werkzeuge lenken die alten
  Zeilen auf `...-mbr-sysupgrade.img.gz`, wenn es im Image-Verzeichnis liegt
  (`-x`).

Offen: ob der Autoupdater sehr alter Firmwares (ecdsautils 0.3.x) heutige
Signaturen annimmt, ist noch nicht im Labor geprüft.

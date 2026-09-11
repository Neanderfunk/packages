neanderfunk-respondd
====================

respondd-Modul (`/usr/lib/respondd/neanderfunk-respondd.so`) für die Werte,
die die Neanderfunk-Statusseite und `nodestatus` zusätzlich zu Gluons eigenem
respondd zeigen. Alles unter dem Schlüssel `neanderfunk`, damit es an einer
Stelle steht und auch für Karte, Yanic und Meshviewer abfragbar ist (Yanic
ignoriert unbekannte Schlüssel).

In C, weil die Statusseite `statistics` alle 3 s abfragt, solange sie offen
ist, dazu kommen Karte und Yanic: nur sysfs, `/proc`, nl80211 über libiwinfo
und ein ioctl je Ethernet-Port, kein Prozessstart, kein ubus.

**Nicht hier hinein:** Adressen aus dem Uplink-/WAN-Netz des Aufstellers
(etwa das IPv4-Gateway). respondd ist meshweit abfragbar und landet auf
öffentlichen Karten.

Klassen
-------

Wo ein Wert steht und wie oft das Modul ihn wirklich neu liest, hängt davon
ab, wie schnell er sich ändert:

| Klasse | Werte | respondd | im Modul |
| --- | --- | --- | --- |
| statisch nach dem Boot | CPU-Modell, BIOS, Flash-Größe; intern die Port-Liste aus `board.json` | `nodeinfo` | einmal gelesen, danach gehalten (der respondd-Prozess lebt so lange wie der Boot) |
| Konfiguration | `preserve_channels` | `nodeinfo` | bei jeder nodeinfo-Abfrage (die kommt selten) |
| mittel | je Radio Kanal, HT-Modus, SSID, TX-Leistung, Land, Mesh | `statistics` | 10 s gecacht; ändert sich durch ACS, ssid-changer, Eingriffe |
| schnell | je Ethernet-Port Link, Geschwindigkeit, Duplex; ssid-changer-Zähler | `statistics` | bei jeder Abfrage aus sysfs bzw. `/tmp`; das ioctl für `possible` nur, wenn sich die Geschwindigkeit des Ports geändert hat |

Datenvertrag
------------

In `statistics` sind **alle Felder immer vorhanden**, notfalls `0`, `false`
oder `""` - die Statusseite schreibt Werte per `data-statistics`
unverändert ins Element, ein fehlender Schlüssel käme dort als `undefined`
an. Einzige Ausnahme: `ssid_changer` fehlt ganz, wenn eine seiner Dateien
fehlt (Paket nicht installiert).

### nodeinfo

```json
"neanderfunk": {
  "hardware": {
    "cpu_model": "MIPS 1004Kc V2.15",
    "flash": 16777216,
    "bios": { "vendor": "", "version": "" }
  },
  "wireless": { "preserve_channels": false }
}
```

- `cpu_model`: `/proc/cpuinfo` „model name“ (x86, manche ARM), sonst
  „cpu model“ (MIPS). Die aarch64-Targets (MT7981 u. a.) haben keines von
  beiden: `""`.
- `flash` in Bytes - die **Hardware im Gerät**, nicht was das OS davon
  nutzt (Entscheidungsgrundlage, wie „capable“ ein Gerät ist):
  1. die Größe der Flash-Chips laut Probe-Meldung des Treibers
     (`spi-nor … (16384 Kbytes)`, `spi-nand … 128 MiB`, `nand: 128 MiB`),
     einmal beim Laden des Moduls aus dem Kernel-Puffer gelesen und in
     `/tmp/neanderfunk-respondd-flash` gemerkt - startet respondd Tage
     später neu, kann die Meldung aus dem Puffer verschwunden sein. Sysfs kennt
     die Chipgröße nicht, und die Partitionen decken den Chip nicht immer ab:
     der Cudy WR3000S hat 128 MiB, partitioniert sind knapp 70;
  2. sonst MTD: das größte Partitionsende (`offset + size`), nicht die Summe
     - Verkettungen wie „ubi“ enthalten bereits gezählte Bereiche;
  3. ohne MTD (x86, eMMC) die Platte, von der gebootet wurde (das Blockgerät
     hinter `/rom`, bei einer Partition deren Platte); Rückfall das größte
     Blockgerät aus `/proc/partitions` außer `loop*`/`ram*`.
  Unbekannt: `0`.
  Auf x86 ist das die Größe der Platte bzw. virtuellen Disk, **nicht des
  Images**: eine 1-GiB-Disk mit 126-MB-Image ergibt 1 GiB. `nodestatus`
  zeigt unter „Flash“ dagegen belegt/gesamt des Overlays - ein anderer Wert.
- `bios`: DMI, nur x86; sonst leere Strings.

### statistics

```json
"neanderfunk": {
  "wireless": {
    "radio0": { "channel": 5, "htmode": "HE20", "ssid": "Freifunk",
                "txpower": 20, "country": "DE", "mesh": true }
  },
  "ssid_changer": { "offline": 0, "switches": 0, "gateway_losses": 0 },
  "ethernet": {
    "internet": { "carrier": true,  "speed": 1000, "duplex": "full", "possible": 0 },
    "ethernet": { "carrier": false, "speed": 0,    "duplex": "",     "possible": 0 }
  }
}
```

**wireless** - was tatsächlich läuft, nicht die Konfiguration. Gluon benennt
die Interfaces nach dem Radio: `client<N>` und `mesh<N>` gehören zu
`radio<N>`. Ein Radio erscheint, sobald eines der beiden existiert.
- `channel`, `htmode` (`HT20`, `VHT80`, `HE80` …), `txpower` (dBm),
  `country`: vom Client-AP, sonst vom Mesh-Interface.
- `ssid`: die gerade ausgestrahlte Client-SSID - während der Offline-Phase
  also die Offline-SSID. Ohne Client-AP (etwa vom ap-timer abgeschaltet):
  `""`.
- `mesh`: das Mesh-Interface ist oben. Bei 5 GHz `channel=auto` indoor ist
  es gewollt aus.

**ssid_changer** - die Buchführung von `neanderfunk-ssid-changer` in `/tmp`:
`offline` (0/1, galt der Knoten am letzten Fensterwechsel als offline),
`switches` (wie oft die Offline-SSID seit dem Boot geschaltet wurde),
`gateway_losses` (Gateway-Verluste seit dem Boot, entprellt).

**ethernet** - je Port, an den man ein Kabel steckt, auch ohne Link (dann
hat die Statusseite eine feste Zeile je Port). Aufgenommen wird ein
Interface, das
1. einen `device`-Link hat (keine VLANs wie `eth0.1`, Bridges, veth
   `local-node`/`local-port`),
2. kein WLAN ist (`phy80211/` bzw. `wireless/`),
3. kein DSA-Conduit ist (`dsa/` - eth0 mit 2500 MBit/s auf MT7981, `dsa`
   auf dem ERX),
4. kein swconfig-CPU-Port ist (`board.json` → `switch.*.ports[].device`),
5. in `board.json` unter `network` steht oder administrativ oben ist - das
   lässt eine unbenutzte GMAC ohne Buchse weg (`eth1` auf der COVR-X1860).

Felder:
- `carrier`: Link.
- `speed` in MBit/s, `0` ohne Link oder wenn der Treiber keine meldet
  (virtio).
- `duplex`: `full`, `half` oder `""`. `half` gilt als Fehler.
- `possible`: die höchste Rate, die **beide** Seiten angeboten haben
  (`advertising` ∩ `lp_advertising` aus `ETHTOOL_GLINKSETTINGS`), aber nur,
  wenn sie über der ausgehandelten liegt, sonst `0`. Der Fingerabdruck eines
  beschädigten Kabels. Ein echtes 100-MBit-Gerät an einem Gigabit-Port
  bietet kein Gigabit an und ergibt `0`.

Auf **swconfig-Geräten** (TL-WDR3600, Archer C7 …) bleibt `ethernet` leer,
die echten Ports kennt nur der Switch. Eine zweite Stufe per libsw wäre
möglich (so wie `nodestatus` `swconfig dev switch0 port N get link` fragt).

Geprüft
-------

Am 11.09.2026 mit einem zweiten respondd auf Port 1101, Modul aus `/tmp`,
Produktiv-respondd unberührt:

| Knoten | Befund |
| --- | --- |
| dias-xiaomi4Agiga-test (MT7621, mipsel) | `wan` 1000, `lan2` 100 an einem 100-MBit-Gerät (`possible` 0), `lan1` ohne Link |
| dias-COVRx1860 (MT7621, mipsel) | `internet`, `ethernet`; Flash 128 MiB trotz ubi-Verkettung; `eth1` ausgeblendet |
| grw-cudyWR3000Sv1 (MT7981, aarch64) | `wan`, `lan1`–`lan4`; Conduit `eth0` (2500) ausgeblendet; `cpu_model` leer |
| dias-WR3600-test (ath79, mips, swconfig) | `ethernet` leer |
| dias-x86-64-test (QEMU) | `eth0`/`eth1` ohne Geschwindigkeit (virtio), BIOS SeaBIOS |
| dias-futrotest (FUTRO S550, echte x86-Hardware) | `flash` 1018773504 = die ~1-GB-Flash-Disk `sda`, nicht das 126-MB-Image; CPU „Mobile AMD Sempron 2100+“, BIOS Phoenix 6.00; `eth1` (r8169) 1000/full, `eth0` (tg3) ohne Link; ioctl liefert echte Masken |

10 statistics-Abfragen samt `gluon-neighbour-info`-Prozessstart brauchten auf
den MIPS-Knoten zusammen unter 0,1 s.

Abfragen:

```sh
gluon-neighbour-info -d ::1 -p 1001 -r statistics | jsonfilter -e '@.neanderfunk'
gluon-neighbour-info -d ::1 -p 1001 -r nodeinfo | jsonfilter -e '@.neanderfunk'
```

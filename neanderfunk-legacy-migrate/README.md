neanderfunk-legacy-migrate
==========================

Upgrade-Skripte für große Sprünge auf Gluon 2025.1, etwa wenn wir die Knoten
einer Community übernehmen, die noch auf 2015.1, 2016.2 oder 2017.1 steht.
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

Die Skripte laufen zwischen Gluons eigenen Upgrade-Skripten:

| Skript | wann | was |
|---|---|---|
| `018z-neanderfunk-ifbind-anchor` | x86, einmal | alte LAN/WAN-Zuordnung an die Karte binden, nur bei Herkunft vor 2022.1 |
| `019-migrate-interface-order` | Gluon | tauscht LAN/WAN nach alter Treiber-Ladereihenfolge (ab 2022.1) |
| `020-interfaces` | Gluon | setzt `lan_ifname`/`wan_ifname` neu (x86: eth0/eth1) |
| `020a-neanderfunk-ifbind` | x86, **jedes Mal** | `lan_ifname`/`wan_ifname` auf die gebundenen Karten |
| `020z-neanderfunk-legacy-migrate` | einmal, nur alte Herkunft | Konfiguration migrieren (unten) |
| `021-interface-roles` | Gluon | legt fehlende `gluon.iface_*` mit Site-Vorgaben an |

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
   Site-Vorgaben. `mesh_lan` aus heißt bis 2021.1 immer: LAN steckt in der
   Client-Bridge, also Rolle `client`. Die Bridge selbst ist zu diesem
   Zeitpunkt nicht mehr lesbar: `11_network-migrate-bridges` (OpenWrt
   uci-defaults, läuft vor `zzz-gluon-upgrade`) hat `client.ifname` schon nach
   `device`/`ports` verschoben und dabei verfälscht.
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

- **Herkunft vor 2022.1:** `018z` nimmt `primary_mac` als Anker. Das ist die
  MAC der Karte, die bei der Erstinstallation eth0 war; ihr wird die alte
  Rolle von eth0 zugeordnet. Nur bei genau zwei Karten und alten Namen
  eth0/eth1. `019` wird dann übersprungen, damit nicht doppelt getauscht wird.
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
Zuordnung, die Gluon gerade gewählt hat.

Grenzen
-------

- CPE210/510 v1 und EdgeRouter X scheitern schon vorher am alten sysupgrade
  bzw. am Flash-Layout. Das gehört in die Manifest-Auswahl, nicht in dieses
  Paket.
- IBSS-Mesh: Nach der Migration meshen die Knoten per 802.11s. Zu Nachbarn,
  die noch nicht migriert sind, geht das WLAN-Mesh verloren, bis sie
  nachziehen.
- x86 mit Herkunft vor 2022.1: Wurden LAN/WAN früher schon einmal getauscht
  und danach umgesteckt, liegt der Anker `primary_mac` falsch. Dann von Hand
  korrigieren (oben).
- Der Fall, dass Gluons `019` auf x86 selbst tauscht, ließ sich in QEMU nicht
  erzeugen (igb lädt als Boot-Modul).

Tests
-----

QEMU x86-64, Ziel 26100312bro, Altkonfigurationen echter Knoten:

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

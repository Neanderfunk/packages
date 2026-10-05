neanderfunk-legacy-migrate (2021.1)
===================================

Backport des gleichnamigen Pakets aus `v2025.1.x` für Gluon 2021.1. Zweck:
alte Knoten (2015.1, 2016.x) einer übernommenen Community auf 2021.1
heranholen, als Zwischenstufe oder für 4/32-Geräte als Endstation.

Hintergrund: router-werkstatt `docs/gluon-migrationspfade.md`
(Abschnitte „Migrationsskript statt Zwischenstufen“ und „Zusätzliche Aufgaben
für das Migrationsskript“, Spalte „Ziel 2021.1“).

Was `020z-neanderfunk-legacy-migrate` tut
-----------------------------------------

Läuft nur, wenn `gluon_version` eine Version vor 2021 nennt, eine
`/etc/config/gluon-simple-tc` da ist, `/lib/gluon/version/core` existiert
(2014.x-Releases ohne `gluon_version`) oder `firewall.client` existiert. Danach
steht `/lib/gluon/core/sysconfig/neanderfunk_legacy_migrated` (alte Version),
und das Skript läuft nicht noch einmal.

1. `gluon-simple-tc` → `simple-tc` (seit 2016.1 umbenannt; die Migration hat
   Gluon mit `fc7c8cb0` in v2019.1 entfernt). Danach übernimmt Gluons
   `500-mesh-vpn` das Bandbreitenlimit nach `gluon.mesh_vpn`.
1a. LAN in der Client-Bridge ohne `network.mesh_lan` (Gluon 2014.x):
   `mesh_lan` mit `auto='0'` anlegen. Sonst legt `220-interface-lan` die
   Sektion mit der Site-Vorgabe an, und seine Prüfung, ob LAN schon in
   `client.ifname` steht, scheitert am alten String `'eth0.1 bat0'` (`get_list`
   liefert ein einziges Element). LAN läge dann zugleich in br-client und im
   aktiven mesh_lan. Mit `auto='0'` setzt 220 `disabled=1`, und LAN bleibt in
   der Client-Bridge.
2. Alte Zonen `firewall.client`, `firewall.local_node`, `dhcp.client` löschen,
   `sysctl.conf` mit `ip_forward=1` auf Vorgabe zurück (entfernt mit
   `ab2f82ca` in v2021.1).
3. Autoupdater: Ein fremder `settings.branch` wird auf unseren Default gesetzt
   (`/lib/gluon/autoupdater/default_branch`, sonst `site.autoupdater.branch`,
   sonst der alphabetisch erste). Das ist nötig, weil `500-autoupdater` in
   2021.1 `settings.branch` nicht anfasst, sobald `settings` existiert; der
   Knoten hinge sonst an einem Zweig ohne Sektion. Branch-Sektionen, die unsere
   Site nicht kennt, werden gelöscht. Sektionen mit unseren Namen schreibt
   `500-autoupdater` ohnehin neu. Das vorhandene
   `910-eulenfunk-migrate-updatebranch` biegt danach unsere alten Namen auf
   `sackgasse` um.

Was 2021.1 selbst erledigt
--------------------------

Mesh auf WAN/LAN (`mesh_wan`/`mesh_lan`, `210/220`), VPN-Schalter und Limit
(`500-mesh-vpn`), `preserve_channels`, IBSS-Sektionen (`delete_ibss`) und
Koordinaten mit Leerzeichen (`520-node-info-whitespace-fix`).

Bewusst nicht
-------------

- IBSS-Nachbarn: 2021.1 meshet per 802.11s, zu nicht migrierten Nachbarn
  geht das WLAN-Mesh verloren.
- batman-adv-Kompatibilität: 2015.1 spricht compat 14, 2021.1 compat 15.
- x86-Bindung LAN/WAN: `020-interfaces` behält in 2021.1 die vorhandenen
  Namen aus sysconfig, da springt nichts.

Getestet
--------

Zuerst nur die Logik, auf einer 2025.1-VM (gleiche Lua-Schnittstellen) mit
der echten Konfiguration eines 2015.1.2-Knotens: Umbenennung samt Limit
8000/500, Zonen, `sysctl.conf`, eigener Branch bleibt (fremde Sektionen weg),
fremder Branch wird zum Default, zweiter Lauf ohne Wirkung. Ein Knoten mit
`v2021.1.2` bleibt unberührt.

Danach echte Sprünge in der Emulation (QEMU malta-be, Gluon-Rootfs mit
RAM-Overlay, Aufbau Buildsystem, router-werkstatt
`docs/emulation-alte-gluon-images.md`), Ziel 24100427bro WR841N v9, Sicherungen
echter Altknoten, 05.10.2026:

- 2015.1.1 (ffems, IBSS, fastd), 2016.1 und 2018.2.2 (ffdus): IBSS wird
  802.11s, VPN-Schalter und Limits kommen an, Mesh auf LAN richtig, keine
  Fehler im Upgrade-Log (Buildsystem).
- 2014.4 (ffsb, LAN `eth0` in `client.ifname`, kein mesh_lan): vorher eth0
  zugleich in br-client und mesh_lan aktiv; mit Schritt 1a `mesh_lan`
  disabled, `client.ifname` = `eth0 bat0 local-port`. Dazu `alfred`, `luci`,
  `ucitrack` gelöscht, `fastd` bleibt.

Offen: ein Sprung auf echter Hardware (841 mit Altfirmware).

Verwaiste Konfigurationen (`990-neanderfunk-orphan-configs`)
-----------------------------------------------------------

Läuft bei jedem Upgrade auf jedem Knoten. Löscht `/etc/config/alfred`,
`luci`, `ucitrack`, `socat` und `keep_settings`, wenn das zugehörige Programm
nicht im Image ist (`/usr/sbin/alfred`, luci-base, `/usr/bin/socat`;
`keep_settings` ist ein Fremdpaket alter Communities). Solche Dateien schleppt
ein sysupgrade aus alten Firmwares mit, oder aus einem Image, das das Paket
noch hatte (Sackgasse: socat seit 04.10.2026 raus). Bewusst nicht:
`/etc/config/fastd` mit dem alten Schlüssel (adorfer 05.10.2026) und
`dhcp.local_client` (legt Gluon selbst an). Getestet in der Emulation (oben).

Manifeste für alte Knoten
-------------------------

Das Paket übernimmt die Konfiguration beim Sprung. Damit ein Altknoten den
Sprung überhaupt angeboten bekommt, muss er das Manifest lesen können und
darin seinen Modellnamen finden. Dafür liegen in `contrib/` die Werkzeuge
(siehe `contrib/README.md`). Dieser Zweig ist die Sackgasse für 4/32-Geräte (letztes Gluon dafür: 2021.1); alle anderen Geräte gehen nach 2025.1 (Zweig `v2025.1.x`), ein zusammengeführtes Manifest bietet jedem Modell die passende Linie an.

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
- x86: Ziel ist 2025.1 (Zweig `v2025.1.x`), dort steht, was x86 braucht.

Offen: ob der Autoupdater sehr alter Firmwares (ecdsautils 0.3.x) heutige
Signaturen annimmt, ist noch nicht im Labor geprüft.

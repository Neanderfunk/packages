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

Nur die Logik, auf einer 2025.1-VM (gleiche Lua-Schnittstellen) mit der
echten Konfiguration eines 2015.1.2-Knotens: Umbenennung samt Limit 8000/500,
Zonen, `sysctl.conf`, eigener Branch bleibt (fremde Sektionen weg), fremder
Branch wird zum Default, zweiter Lauf ohne Wirkung. Ein Knoten mit
`v2021.1.2` bleibt unberührt. Ein echter Sprung 2015.1.2 → 2021.1 steht aus
(braucht ein 2021.1-Image mit dem Paket).

Emulation (QEMU malta-be, Aufbau Buildsystem), 24100427bro WR841N v9, Sicherung
eines 2014.4-Knotens (ffsb, LAN `eth0` in `client.ifname`, kein mesh_lan),
05.10.2026: `mesh_lan` disabled, `client.ifname` = `eth0 bat0 local-port`;
vorher eth0 zugleich in br-client und mesh_lan aktiv.

neanderfunk-port-roles
======================

Eine Rolle **je Netzwerk-Port** statt je Portgruppe, und die Wahl, wie
LAN-Ports mit der Rolle „Mesh" verbunden werden. Geschrieben für **Gluon
2025.1**.

Hintergrund
-----------

Gluon baut das kabelgebundene Netz bei jedem `gluon-reconfigure` aus
`/etc/config/gluon` neu; `/etc/config/network` ist ein Wegwerfprodukt (siehe
`docs/gluon-reconfigure.md`). Jede Sektion `gluon.iface_*` hat eine Portliste
(`name`) und Rollen (`uplink`, `mesh`, `client`). Ab Werk gibt es nur
`iface_lan` (alle LAN-Ports), `iface_wan` und `iface_single` - wer LAN-Ports
unterschiedlich nutzen wollte, hat früher Bridges in `network` gebaut, und die
waren beim nächsten Update weg.

Außerdem legt `210-interface-mesh` alle Mesh-Ports, die nicht Uplink sind, in
**eine** Bridge `mesh_other` mit `isolate` an jedem Port. Ob `isolate` wirkt,
hängt am Switch-Treiber: Kernel 5.15 (Gluon 2023.2) reicht das Flag gar nicht
an den Switch weiter, ein Switch mit Hardware-Bridging leitet zwischen den Ports
dann einfach weiter. Kernel 6.6 in Gluon 2025.1 tut es, und OpenWrt hat die
Umsetzung für `mt7530`/`mt7531` und `qca8k` (auch den IPQ4019-Switch)
nachgerüstet (`790-56-…mt7530…bridge-port-isolation`, `793-03-…qca8k…`).

Eine Rolle je Port
------------------

Die Seite „Ports" zeigt je einzeln verwendbarem Port (DSA-Port, eigene
Netzwerkkarte) eine Zeile, auch wenn er wie ab Werk in einer Gruppe steckt
(`gluon.iface_lan` mit `name='/lan'`). **Eingegriffen wird nur, wenn sich etwas
ändert** - derselbe Weg wie beim Befehl `portrole` (neanderfunk-banner):

* Ein Port mit der Rolle seiner Gruppe bleibt in der Gruppe.
* Bekommt ein Port eine andere Rolle, wird er herausgelöst: die Gruppe behält
  die Liste der übrigen Ports (`name='lan1 lan3'`), der Port bekommt eine
  eigene Sektion `gluon.iface_<port>` (`.` wird `_`; ist der Name belegt,
  `iface_port_<port>`). Die Hop-Penalty der Gruppe wandert mit.
* Wollen alle Ports einer Gruppe dieselbe neue Rolle, bekommt die Gruppe diese
  Rolle, statt zerlegt zu werden.
* Bekommt ein herausgelöster Port wieder die Rolle seiner Board-Gruppe, wandert
  er zurück, seine Sektion entfällt; ist die Gruppe wieder vollständig, steht
  dort wieder `/lan`.
* Sektionen, die nicht nur für den einen Port angelegt wurden (Gluons
  `iface_wan`, `iface_extra_*` von neanderfunk-legacy-migrate), bleiben stehen
  und bekommen nur die Rolle.

Ein Knoten, an dem niemand die Seite benutzt, behält Gluons Aufbau. Bis
Version 1 zerlegte das Paket bei jedem `gluon-reconfigure` alle Gruppen
(`025-neanderfunk-port-roles`, `iface_port_*`); das ist entfallen, die Version
war in keinem Image.

**Hinter swconfig** (ältere ath79) hängen alle LAN-Ports an einem `eth0.1`; die
Seite zeigt dann eine Zeile je Gruppe („LAN (eth0.1)") und einen Hinweis.

Gluon baut aus den Sektionen wie immer `br-client`, `br-wan` und das Mesh. Ein
Port ohne Rolle wird nicht verwendet.

Von Hand, ohne Oberfläche: `portrole lan2 client` (zurück: `portrole lan2 lan`),
danach `reconf`.

Mesh-Modus
----------

`gluon.port_roles.mesh_mode`, umgesetzt von `230-neanderfunk-port-roles` nach
`210-interface-mesh` und vor `300-firewall-rules`:

| Modus | Ergebnis |
| --- | --- |
| `isolate` (Vorgabe) | Gluons eigener Weg: eine Bridge `mesh_other`, `isolate` an jedem Port |
| `auto` | `isolate`, wenn es auf allen Mesh-Ports wirkt, sonst `separate` |
| `separate` | je Port eine Bridge `mesh_<port>` mit eigenem `gluon_wired`, also ein eigenes batman-adv-Interface - wirkt wie Isolation, ohne dass der Switch sie können muss |
| `bridge` | eine gemeinsame Bridge ohne Isolation |

`auto` hält `isolate` für wirksam bei eigenen Netzwerkkarten (der Kernel bridged
in Software) und bei Switch-Ports mit den Treibern `mt753*` oder `qca8k*` ab
Kernel 6.6; sonst getrennte Bridges.

Bei getrennten Bridges braucht jede eine eigene MAC: alle DSA-Ports teilen sich
die des CPU-Ports, und ohne VXLAN sitzt batman-adv direkt auf der Bridge. Gluons
`generate_mac()` hat nur 8 Plätze, und die sind vergeben. Das Paket leitet die
MAC deshalb aus einem Hash über primäre MAC und Portnamen ab (lokal verwaltet,
stabil über Reboots und Updates). Mit VXLAN bekommt das VXLAN-Device vom Kernel
eine zufällige MAC; `func`/`index` für Gluons Ableitung werden bewusst nicht
gesetzt, sonst hätten alle Bridges dieselbe.

Die Firewall braucht keinen Eingriff: `300-firewall-rules` nimmt jedes
`gluon_wired`-Interface außer `mesh_uplink` in die Zone `wired_mesh`.

Oberfläche
----------

Seite **„Ports"** in den Erweiterten Einstellungen (hinter „Netzwerk"): je Port
die Rollen (umgesetzt wie oben beschrieben, `portroles.apply()`; nur Zeilen, die
auf dieser Seite geändert wurden, alles gesammelt in `f:write` auf einem frisch
geladenen Cursor - siehe „Sammelseite“ unten), dazu der Mesh-Modus und für die aktuellen Mesh-Ports, ob der Switch
in Hardware isoliert und was `auto` gerade bedeutet. Gespeichert wird wie auf
Gluons Seite „Netzwerk" nur per `commit`; wirksam wird es mit dem Reconfigure
beim „Speichern & Neustarten" im Wizard.

Sammelseite (neanderfunk-setup-mode)
------------------------------------

Im Setup-Mode stehen Gluons Seite „Netzwerk" und „Ports" auf einer Seite und
werden gemeinsam gespeichert: erst alle geänderten Admin-Formulare (commit wird
dort zu save), „Netzwerk" vor „Ports", zuletzt der Wizard mit
`gluon-reconfigure` und Neustart. Beide schreiben `gluon.iface_*.role`. Damit
eine Änderung auf „Netzwerk" nicht von unberührten Zeilen dieser Seite
zurückgenommen wird, zählt hier nur, was gegenüber der Anzeige geändert wurde,
und geschrieben wird auf einem frisch geladenen Cursor, der die schon
gespeicherten Deltas von „Netzwerk" sieht. Bei echtem Widerspruch (dieselbe
Rolle auf beiden Seiten verschieden geändert) gewinnt „Ports".

VLANs je Port
-------------

Auf einem einzeln verwendbaren Port (DSA-Port oder eigene Netzwerkkarte) lassen
sich getaggte VLANs anlegen. Jedes VLAN ist eine eigene Sektion
`gluon.iface_<port>_<vid>` mit `name='<port>.<vid>'` und eigenen Rollen;
netifd legt das VLAN-Unterinterface an, sobald es in einer Bridge oder einem
Interface auftaucht. Auf der Seite „Ports" gibt es dafür je Port eine Liste von
VLAN-IDs; ein neues VLAN erscheint nach dem Speichern als eigene Zeile unter
„Rollen".

**Dieselbe VLAN-ID kann auf verschiedenen Ports verschiedene Rollen haben** -
`lan3.5` und `lan4.5` sind zwei getrennte Netdevs. VLAN-Unterinterfaces bridged
der Kernel in Software; für reine VLAN-Mesh-Ports wählt `auto` deshalb
`isolate`.

Von Hand:

```
uci set gluon.iface_lan3_5=interface
uci set gluon.iface_lan3_5.name='lan3.5'
uci add_list gluon.iface_lan3_5.role='mesh'
uci commit gluon
```

Einschränkungen
---------------

* **Nur DSA-Ports und eigene Netzwerkkarten.** Bei Geräten mit **swconfig**
  (ältere ath79) hängen die LAN-Ports hinter einem VLAN-Unterinterface wie
  `eth0.1` und erscheinen als eine Schnittstelle. Rollen gelten dort für alle
  gemeinsam, einzelne Ports und VLANs je Port lassen sich nicht einstellen - die
  Seite sagt das auf solchen Geräten ausdrücklich. Grund: bei swconfig gilt ein
  VLAN für den ganzen Switch; dieselbe VLAN-ID mit verschiedenen Rollen auf
  verschiedenen Ports wäre dort gar nicht abbildbar, und alles andere hieße, die
  Switch-VLANs selbst zu verwalten.
  Welche Feldgeräte das betrifft (rund die Hälfte, und 2025.1 ändert daran
  nichts): `docs/feldgeraete-dsa-swconfig.md` im Feed.
* **Noch nicht am Gerät geprüft:** ob ein VLAN-Unterinterface auf einem
  DSA-Port, der zugleich (ungetaggt) in einer Bridge steckt, bei
  `mt7530`/`qca8k` sauber durchgereicht wird; `qca8k` (IPQ4019) überhaupt;
  die Modi `separate`/`bridge` unter 6.6.
* **Ein Port ohne Rolle** wird nicht verwendet; ein VLAN ohne Rolle ebenso.

Geprüft
-------

**06.10.2026, Gluon 2025.1 (26100604bro, Kernel 6.6.151)**, Xiaomi 4A Gigabit
`33f1` (mt7530), lan1 am ERX, lan2 am WDR3600, beide Mesh:

* `isolate` wirkt in Hardware: Der WDR3600 sieht über sein Kabel nur den 33f1,
  nicht den ERX. Gegenprobe: `isolated` an beiden Ports zur Laufzeit 40 s aus -
  der ERX erscheint sofort als Kabel-Nachbar des WDR3600, danach wieder weg.
* Rollen je Port über `portroles.apply()` und echtes `gluon-reconfigure` mit
  Neustart: lan1 Mesh, lan2 Client. `lan2` steckt in `br-client` (MAC des
  WDR3600 dort gelernt), `lan1` direkt am batman-adv, Gateway über lan1; beim
  WDR3600 laufen die Kabel-Nachbarn aus, über den Client-Port kommt kein Mesh.
  Rückweg (lan2 wieder Mesh): `iface_lan2` entfällt, `iface_lan` wieder `/lan`,
  nach dem Neustart Ausgangszustand.
* Seite per Config-Mode-CGI im Normalbetrieb (Dateien per bind-mount aus
  `/tmp`): GET zeigt je Port eine Zeile, die Rollen und „mt7530-mdio, isoliert in
  Hardware"; POST lan2 Client und zurück schreibt dasselbe wie oben.
* WDR3600 (swconfig): GET zeigt „eth0.1"/„eth0.2" je Gruppe und den Hinweis,
  keine VLANs.

`gluon-reconfigure` meldete dabei rc=1: in 26100604bro sind `009`/`015` von
neanderfunk-legacy-migrate nicht ausführbar (behoben im Feed 9986c08), nicht
dieses Paket.

**07.10.2026, Sammelseite am 33f1** (Dateien per bind-mount, POST auf
`/wizard` mit allen Feldern der Seite): auf „Netzwerk" LAN von Mesh auf Mesh +
Uplink, auf „Ports" nur lan2 auf Client. Nach dem einen Reconfigure des Wizards
stand schon vor dem Neustart `iface_lan` = `lan1` (mesh, uplink) und
`iface_lan2` = `lan2` (client) in `/etc/config/gluon`; nach dem Neustart lan1 in
`br-wan` (Mesh zum ERX darüber), lan2 in `br-client`. Danach zurück auf den
Ausgangsstand. Im Normalbetrieb braucht der Test `mkdir -p
/var/gluon/setup-mode`, sonst wartet wizard-save-lock 50 s und zeigt die
Neustart-Seite, ohne zu speichern.

Host-Test der Logik: `lua5.1 tests/apply_test.lua` (vierzehn Fälle: unverändert,
herauslösen, zurückholen, alle gleich, gemischt, portrole- und
legacy-migrate-Sektionen, swconfig, verwaister Port, VLAN, Hop-Penalty, Rolle
als String, nur geänderte Zeile, VLANs setzen).

Ältere Prüfungen (Version 1, mit automatischem Zerlegen):

Am 2026-09-10 auf einem Xiaomi 4A Gigabit (mt7530, noch Gluon 2023.2, Kernel
5.15) mit Gluons echter Kette `020`, `021`, `025`, `110`, `210`, `230`,
`300-firewall-rules`, `300-gluon-client-bridge-network`, `330` als uci-Delta,
danach zurückgesetzt:

* `auto`: `iface_lan` wird in `iface_port_lan1`/`_lan2` zerlegt; weil mt7530 unter
  5.15 nicht isoliert, entstehen `mesh_lan1`/`mesh_lan2` mit eigenen MACs, beide
  in `wired_mesh`.
* `isolate`: unverändert Gluons Bridge mit `isolate`.
* `bridge`: eine Bridge, `isolate` entfernt.
* `lan2` auf `client`: `lan2` in `br-client`, `mesh_other` nur `lan1`.

Außerdem mit derselben Kette: VLAN 5 auf `lan1` als `client` landet in
`br-client`, VLAN 5 auf `lan2` als `mesh` bekommt bei `auto` eine eigene Bridge
`mesh_lan2_5` (weil `lan1`/`lan2` unter 5.15 nicht isolieren), alle Mesh-Bridges
in `wired_mesh`.

Die Seite ist per Nachbau geprüft (mt7530 unter 5.15 und 6.6, x86, WDR3600 mit
swconfig; VLANs anlegen und entfernen).

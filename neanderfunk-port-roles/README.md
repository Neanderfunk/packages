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

`025-neanderfunk-port-roles` (nach `021-interface-roles`) zerlegt Sektionen mit
mehreren Ports in eine Sektion je Port, `gluon.iface_port_<port>`, mit den
Rollen der Gruppe. Gluon baut daraus wie immer `br-client`, `br-wan` und das
Mesh. Ein Port ohne Rolle wird nicht verwendet.

Die Gruppen-Sektion bleibt stehen - sonst legte `021` sie beim nächsten Lauf mit
allen Ports neu an. Sie bekommt `name='/none'` und merkt sich, woher ihre Ports
kamen (`neanderfunk_ports_from`) und welche Rollen sie hatte
(`neanderfunk_default_role`); bringt ein Board-Update einen Port dazu, bekommt
er darüber eine eigene Sektion. Auf Gluons Seite „Netzwerk" steht sie deshalb
als leere Zeile.

Zerlegt wird nur, was sich einzeln verwenden lässt: DSA-Ports und eigene
Netzwerkkarten. **Hinter swconfig** (ältere ath79) hängen alle LAN-Ports an einem
`eth0.1`; solche Sektionen bleiben, wie sie sind. Ports, die schon eine eigene
Sektion haben (etwa von Hand angelegt), fasst das Paket nicht an.

Von Hand, ohne Oberfläche:

```
uci delete gluon.iface_port_lan2.role
uci add_list gluon.iface_port_lan2.role='client'
uci commit gluon
```

danach `gluon-reconfigure` und Reboot (per SSH von der Sitzung gelöst, siehe
`docs/gluon-reconfigure.md`).

Mesh-Modus
----------

`gluon.port_roles.mesh_mode`, umgesetzt von `230-neanderfunk-port-roles` nach
`210-interface-mesh` und vor `300-firewall-rules`:

| Modus | Ergebnis |
| --- | --- |
| `auto` (Default) | `isolate`, wenn es auf allen Mesh-Ports wirkt, sonst `separate` |
| `isolate` | Gluons eigener Weg: eine Bridge `mesh_other`, `isolate` an jedem Port |
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
die Rollen, dazu der Mesh-Modus und für die aktuellen Mesh-Ports, ob der Switch
in Hardware isoliert und was `auto` gerade bedeutet. Gespeichert wird wie auf
Gluons Seite „Netzwerk" nur per `commit`; wirksam wird es mit dem Reconfigure
beim „Speichern & Neustarten" im Wizard.

VLANs je Port
-------------

Auf einem einzeln verwendbaren Port (DSA-Port oder eigene Netzwerkkarte) lassen
sich getaggte VLANs anlegen. Jedes VLAN ist eine eigene Sektion
`gluon.iface_port_<port>_<vid>` mit `name='<port>.<vid>'` und eigenen Rollen;
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
uci set gluon.iface_port_lan3_5=interface
uci set gluon.iface_port_lan3_5.name='lan3.5'
uci add_list gluon.iface_port_lan3_5.role='mesh'
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
* **Am Gerät mit Gluon 2025.1 noch nicht geprüft**, insbesondere: ob ein
  VLAN-Unterinterface auf einem DSA-Port, der zugleich (ungetaggt) in einer
  Bridge steckt, bei `mt7530`/`qca8k` sauber durchgereicht wird, und ob
  `isolate` unter 6.6 zwischen den Ports wirklich nichts mehr weiterleitet.
* **Ein Port ohne Rolle** wird nicht verwendet; ein VLAN ohne Rolle ebenso.

Geprüft
-------

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
swconfig; VLANs anlegen und entfernen). Auf einem Gerät mit Gluon 2025.1 steht
der Test noch aus.

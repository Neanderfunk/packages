Gluon zur Laufzeit: Fallen für Shell-Pakete
==========================================

Beobachtet auf Knoten mit Gluon 2025.1 (OpenWrt 24.10), beim Bau von
neanderfunk-domainhelper 0.11 am 22.11.2026. Geprüft auf einem M60
(mediatek, DSA), einem NWA50AX Pro (ein LAN-Port) und einem TL-WR1043ND v2
(ath79, swconfig, Switch AR8327).

Werkzeuge, die im Image fehlen
------------------------------

Die busybox unserer Images ist knapp konfiguriert. Nicht da waren (M60,
22.11.2026):

| fehlt | Ersatz |
|---|---|
| `od` | `hexdump -v -e '16/1 "%02x " "\n"' <datei>` |
| `xxd` | `hexdump` wie oben |
| `bridge` (iproute2) | `brctl` (busybox): `brctl showmacs <bridge>` zeigt die Weiterleitungstabelle mit Port-Nummer |
| `pkill` | `ps w` nach Muster filtern und `kill` je PID; `pgrep` ist da |
| `nft` | `ebtables-tiny` (siehe unten) |

Vor dem Einsatz eines Werkzeugs auf dem Zielgerät mit `command -v`
nachsehen. Ein Skript, das ein fehlendes Werkzeug in einer Pipe benutzt,
läuft ohne Fehlermeldung weiter: Die Pipe liefert dann einfach nichts.

busybox `sort`
--------------

busybox `sort` kennt nur `-n -r -u -s -z`. Alles andere wird **ohne
Fehlermeldung ignoriert**:

- `-t` und `-k`: Die Ausgabe ist nicht nach dem gewünschten Feld sortiert.
  Den Sortierschlüssel deshalb vorn in die Zeile schreiben.
- `-o <datei>`: Die Ausgabe geht auf stdout, die Datei bleibt, wie sie war.
  Stattdessen

  ```sh
  sort -u "$f" > "$f.s" && mv "$f.s" "$f"
  ```

Port eines Nachbarn an einer Bridge
-----------------------------------

Bei DSA ist jeder LAN-Port ein eigenes Gerät (`lan1`, `lan2`, …) in einer
Bridge (`br-mesh_other`). Hinter welchem Port eine MAC steht:

```sh
brctl showmacs br-mesh_other
# port no	mac addr		is local?	ageing timer
#   3	a6:91:a4:5e:84:c4	no		   0.02
```

Die Port-Nummer passt zu `/sys/class/net/<bridge>/brif/<port>/port_no`
(dort hexadezimal, `0x3`). Ohne `brctl` steht dieselbe Tabelle binär in
`/sys/class/net/<bridge>/brforward`, je Eintrag 16 Byte: MAC (6), port_no
(1), is_local (1), Alterung (4), port_hi (1), Füllbyte (1), unbenutzt (2).

Port eines Nachbarn an einem swconfig-Switch
--------------------------------------------

Ohne DSA (swconfig) sind alle LAN-Ports ein einziges Gerät, etwa `eth1.1`.
Der Switch leitet zwischen den Ports in Hardware weiter. ebtables sieht
diesen Verkehr nicht, eine Port-Isolation gibt es zur Laufzeit nicht.
Manche Switches (ar8xxx, etwa AR8327) nennen aber den Port einer MAC:

```sh
swconfig dev switch0 get arl_table
# Port 2: MAC a6:f7:ba:13:fd:0c
```

Andere swconfig-Switches kennen `arl_table` nicht.

batman auf einem Kabel abschalten, ohne das Gerät abzubauen
-----------------------------------------------------------

Gluon legt für ein Kabel-Mesh ein Interface mit `proto gluon_wired` an
(etwa `mesh_other`) und dazu ein dynamisches Interface `<name>_mesh` mit
`proto gluon_mesh`, das das Gerät an batman hängt.

- `ifdown mesh_other_mesh` nimmt nur batman vom Gerät. Das Gerät bleibt
  oben und behält seine link-local-Adresse.
- **Danach gibt es `mesh_other_mesh` nicht mehr.** `ifup mesh_other_mesh`
  scheitert mit `Interface mesh_other_mesh not found`. Wieder an batman
  kommt das Gerät nur über das übergeordnete Interface:
  `ifup mesh_other`. Das legt `mesh_other_mesh` neu an.
- gluon-respondd hört nur auf Geräten von `gluon_mesh`-Interfaces, die
  oben sind. Nach dem `ifdown` antwortet der eigene respondd auf diesem
  Kabel also nicht mehr. Selbst fragen geht weiter:
  `gluon-neighbour-info -i eth1.1 -d ff02::2:1001 -p 1001 -r nodeinfo`
  bekommt die Antworten der Nachbarn.

Wer einen Totmannschalter mit `ifup <name>_mesh` baut, schaltet damit
nichts wieder ein (am TL-WR1043ND v2 war das LAN-Mesh dadurch einige
Minuten weg, bis von Hand `ifup mesh_other` kam).

batman-Frames je Port verwerfen
-------------------------------

`ebtables-tiny` kann neben `--logical-in`/`--logical-out` (die Bridge) auch
`-i`/`-o` (der Port). Nur batman (Ethertype 0x4305) an einem Port, für den
Knoten selbst und für die Weiterleitung zu den anderen Ports:

```sh
ebtables-tiny -I INPUT   -p 0x4305 -i lan3 -j DROP
ebtables-tiny -I OUTPUT  -p 0x4305 -o lan3 -j DROP
ebtables-tiny -I FORWARD -p 0x4305 -i lan3 -j DROP
ebtables-tiny -I FORWARD -p 0x4305 -o lan3 -j DROP
```

IPv6 geht weiter durch, respondd-Abfragen über diesen Port funktionieren
also auch mit verworfenem batman. Ein Neuladen der Firewall löscht die
Regeln; wer sie braucht, muss sie regelmäßig prüfen und neu setzen.

Siehe auch
----------

- [feldgeraete-dsa-swconfig.md](feldgeraete-dsa-swconfig.md): welche
  Geräte im Feld DSA haben und welche swconfig.
- [sysupgrade-aus-skripten.md](sysupgrade-aus-skripten.md): `sysupgrade`
  aus Skripten.
- [gluon-reconfigure.md](gluon-reconfigure.md): was `gluon-reconfigure`
  tut.

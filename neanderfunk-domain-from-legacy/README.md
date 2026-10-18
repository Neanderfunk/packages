neanderfunk-domain-from-legacy
==============================

Erkennt beim **ersten Upgrade von einer Single-Domain- auf eine
Multi-Domain-Firmware** die alte Domain eines Knotens und setzt
`gluon.core.domain`, bevor Gluons `005-set-domain` den Knoten in
`default_domain` steckt. Geschrieben für **Gluon 2025.1**.

Hintergrund: Künftig ein Multi-Domain-Image je Target statt einer Firmware je
Domain (Entscheidung adorfer 18.10.2026, buildsystem
`docs/multidomain-umstellung.md`). Auch Knoten, die ein oder zwei Jahre offline
waren, sollen richtig landen; deshalb die Erkennung im Image statt einer
Zwischenfirmware.

Wann es wirkt
-------------

`/lib/gluon/upgrade/004-neanderfunk-domain-from-legacy` läuft bei jedem
`gluon-reconfigure`, tut aber nur etwas, wenn

- `/lib/gluon/domains/` existiert (Multi-Domain-Image) und
- `gluon.core.domain` leer ist (Knoten kommt von Single-Domain) und
- eine alte Konfiguration da ist (bei Neuinstallation: still nichts).

Danach ist die Domain gesetzt und das Skript wirkungslos. Die alte
Konfiguration liegt zu dem Zeitpunkt in `network_gluon-old` und
`wireless_gluon-old`: Gluons `001-reset-uci` verschiebt `network` und kopiert
`wireless`, `998-commit` löscht beide erst am Ende.

Merkmale
--------

Das erste eindeutige gewinnt (Entscheidung adorfer 18.10.2026, Variante C):

1. **Mesh-ID** aus `wireless_gluon-old` (`wifi-iface` mit `mode=mesh`,
   `mesh_id`) gegen `wifi24.mesh.id`/`wifi5.mesh.id` der Domain-Dateien.
   Gluon 2023.2 legt `mesh_radioN` auch bei abgeschaltetem Mesh an, praktisch
   jeder WLAN-Knoten hat also eine. Haben die Mesh-Schnittstellen
   verschiedene IDs, müssen alle auf dieselbe Domain zeigen.
2. **next_node IPv4** aus `network_gluon-old.local_node.ipaddr` (ohne
   Präfixlänge) gegen `next_node.ip4`: für Knoten ohne WLAN (x86, ERX) und
   wenn die Mesh-ID nicht eindeutig ist.
3. Sonst nichts setzen, `005-set-domain` nimmt `default_domain`.

Zeigt die IPv4 auf eine andere Domain als die Mesh-ID, gewinnt die Mesh-ID;
eine Logzeile nennt den Widerspruch. Grund: Die IPv4 ist erst seit der
Umnummerierung 04-05/2023 je Domain eindeutig, ältere Werte überschneiden sich
mit heutigen (10.31.0.1 war bis 04/2023 31_lvrno und ist heute 17_wip).

Kein IPv6 (drei bis vier Präfix-Generationen je Domain, Überschneidungen), kein
`domain_seed` (steht nicht in uci).

Altwerte in der Domain-Datei
----------------------------

Frühere Werte stehen im Zusatzschlüssel `neanderfunk_legacy` der
Domain-Konfiguration, Gluon reicht unbekannte Schlüssel in die JSON-Datei
durch:

```lua
neanderfunk_legacy = {
	mesh_id = { 'ffnef-wlf-mesh' },
	-- next_node_ip4 = { ... },  -- nur Werte ab 05/2023
},
```

Regeln für die Liste (Simulation über alle 380 historischen Stände 2016-2026,
18.10.2026):

- Jede Mesh-ID, die die Domain **mindestens 14 Tage** trug. Eintägige
  Zwischenstände bleiben draußen, sonst werden echte alte IDs mehrdeutig (erk
  hatte am 23.09.2018 einen Tag lang `ffnef-rat-mesh`).
- **Geteilte Mesh-IDs bei allen Domains eintragen, die sie hatten**
  (`lvrmw-mesh`: 32 und heute 34, `lvrso-mesh`: 34 und heute 35). Dann passen
  sie auf mehrere Domains, zählen nicht, und die IPv4 entscheidet. Ohne den
  Eintrag landete ein 32er von 2023/24 in 34.
- `next_node_ip4` nur mit Werten ab 05/2023, ältere überschneiden sich.

Ergebnis der Simulation mit diesen Regeln: keine Fehlzuordnung eines Stands,
der länger als vier Tage galt; falsch nur Zwischenstände von einem bis vier
Tagen (April/Mai 2023, 05.03.2024); 21 Stände landen in `default_domain`, vor
allem Firmware von vor 2020 ohne Mesh-ID-Treffer.

Vorschlag für die Altwerte (aus den Merkmalstabellen von Buildsystem, ohne die
jeweils aktuelle ID):

| Domain | `neanderfunk_legacy.mesh_id` |
| --- | --- |
| 01_vel ... 11_lvr | `ffnef-<kurz>-mesh` (z. B. `ffnef-vel-mesh`) |
| 13_dusfl | `FFDUS-BATBONE` (dus ging in 13_dusfl auf, bestätigt adorfer 18.10.2026) |
| 14_bar, 15_mrh, 17_wip | `FFBAR-BATBONE`, `FFMRH-BATBONE`, `FFWIP-BATBONE` |
| 16_gmb | `FFGMB-BATBONE`, `FFMH-BATBONE` |
| 32_lvrnw | `lvrmw-mesh` |
| 34_lvrmw | `lvrso-mesh` |
| alle anderen | keine |

Log
---

Jede Entscheidung geht nach stderr (Ausgabe von `gluon-reconfigure`) und per
`logger -t neanderfunk-domain` ins Syslog, etwa
`Domain 32_lvrnw erkannt an next_node 10.51.240.1` oder
`keine Domain erkannt (Mesh-ID -, next_node 10.99.0.1), default_domain greift`.

Test
----

`test/testfaelle.sh`, nur auf einer Test-VM: legt Domain-Dateien (mit Alias-
Symlink) und alte Konfigurationen an und ruft das Skript direkt auf. Am
18.10.2026 auf 26101300bro (x86-64, QEMU) alle 12 Fälle bestanden: Mesh-ID
eindeutig, alte Mesh-ID aus `neanderfunk_legacy`, geteilte Mesh-ID mit
IPv4-Entscheid (alter 32er, heutiger 34er), 34er von vor 2023 nach
`default_domain`, 31er von vor 2023 mit heute fremder IPv4 (Mesh-ID gewinnt),
ohne WLAN, nichts passt, zwei Mesh-IDs auf zwei Domains, Neuinstallation,
Domain schon gesetzt, kein `domains`-Verzeichnis. Nicht getestet: der ganze
Ablauf `001` -> `004` -> `005` in einem echten Multi-Domain-Image.

Stand
-----

Nicht in den Bauten, adorfer evaluiert separat (Aufnahme ins Image und die
Multi-Domain-Site macht Buildsystem).

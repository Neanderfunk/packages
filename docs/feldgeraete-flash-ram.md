# Feldgeräte: Flash und RAM

Stand 2026-09-11. Wie viel Speicher die Hardware im Feld hat – als
Entscheidungsgrundlage, wie „capable“ die Flotte ist und wen der nächste
Schnitt trifft (vgl. 4/32 bei den 841ern; mit Gluon 2026 fliegt wieder
kleine Hardware raus).

Gemeint ist die **Hardware im Gerät**, nicht was das OS davon nutzt.

## Kurzfassung

* **Ein Viertel der Knoten auf 2023.2 (134 von 531)** läuft auf 8 MB Flash
  oder 64 MB RAM – die Klasse, die beim nächsten Schnitt am ehesten
  herausfällt. Gluon führt davon selbst nur den Archer C25 als `tiny`.
* **Die nächste Welle: 204 Knoten (38 %) mit 16 MB Flash und 128 MB RAM**,
  getragen von 130 Archer C7. Heute ausreichend, in ein paar
  Kernel-Generationen eng.
* Zusammen laufen **63 %** auf höchstens 16 MB Flash und 128 MB RAM.
  Wirklich zukunftsfähig (ab 64 MB Flash und 256 MB RAM) sind **20 %**.

## Klassen

Knoten mit Gluon 2023.2 laut Karte, in Klammern davon online.

| Klasse | Knoten | Anteil |
| --- | ---: | ---: |
| A: 8 MB Flash | 92 (84) | 17 % |
| B: 16 MB Flash, 64 MB RAM | 42 (39) | 8 % |
| C: 16 MB Flash, 128 MB RAM | 204 (201) | 38 % |
| D: 16 MB Flash, 256 MB RAM | 10 (9) | 2 % |
| E: 32 MB Flash oder 128 MB RAM | 45 (45) | 8 % |
| F: ab 64 MB Flash und 256 MB RAM | 105 (97) | 20 % |
| x86 / VMs | 33 (31) | 6 % |
| **gesamt** | **531 (506)** | |

### A: 8 MB Flash – 92 Knoten

| Modell | Knoten | Flash/RAM (MB) |
| --- | ---: | --- |
| TP-Link TL-WR1043ND v2 | 18 | 8/64 |
| TP-Link Archer C6 v2 | 18 | 8/128 |
| TP-Link TL-WDR3600 v1 | 12 | 8/128 |
| TP-Link TL-WR1043ND v3 | 12 | 8/64 |
| TP-Link CPE210 v1 | 8 | 8/64 |
| TP-Link TL-WDR4300 v1 | 8 | 8/128 |
| Ubiquiti UniFi AP | 8 | 8/64 |
| TP-Link Archer C20i | 3 | 8/64 |
| TP-Link CPE510 v1, CPE210 v3, Archer C50 v3, Archer C25 v1, Cudy WR1000 | je 1 | 8/64 |

### B: 16 MB Flash, 64 MB RAM – 42 Knoten

| Modell | Knoten | Flash/RAM (MB) |
| --- | ---: | --- |
| Netgear R6120 | 16 | 16/64 |
| TP-Link TL-WR1043ND v4 | 14 | 16/64 |
| TP-Link TL-WR1043N v5 | 7 | 16/64 |
| GL.iNet GL-AR150 | 4 | 16/64 |
| Ubiquiti UniFi AP Outdoor+ | 1 | 16/64 |

### C: 16 MB Flash, 128 MB RAM – 204 Knoten

| Modell | Knoten |
| --- | ---: |
| TP-Link Archer C7 v5 | 98 |
| TP-Link Archer C7 v2 | 32 |
| Ubiquiti UniFi AC Mesh | 26 |
| Xiaomi Mi Router 4A Gigabit | 17 |
| Ubiquiti UniFi AC Pro | 8 |
| Ubiquiti UniFi AC Mesh Pro | 5 |
| Ubiquiti UniFi AC LR | 4 |
| TP-Link Archer A7 v5 | 3 |
| TP-Link Archer C5 v1, Archer AX23 v1 | je 2 |
| UniFi AP Pro, UniFi AC Lite, TL-WDR4900 v1, Archer C7 v4, Netgear WNDR3800, Joy-IT JT-OR750i, D-Link DIR-860L B1 | je 1 |

### D: 16 MB Flash, 256 MB RAM – 10 Knoten

Cudy WR3000 v1 (6), TOTOLINK X5000R (4).

### E: 32 MB Flash oder 128 MB RAM – 45 Knoten

GL.iNet GL-B1300 (33, 32/256), AVM FRITZ!Box 4040 (6, 32/256),
FRITZ!Box 7412 (3, 128/128), 7362 SL (1, 128/128), 7360 V2 (1, 32/128),
7360 SL (1, 16 oder 32/128).

### F: ab 64 MB Flash und 256 MB RAM – 105 Knoten

Genexis Pulse EX400 (26, 256/256), ZyXEL NWA50AX Pro (25, 256/512),
GL.iNet GL-MT3000 (10, 256/512), Ubiquiti EdgeRouter X (9, 256/256) und
X SFP (5), Extreme Networks WS-AP3825i (4, 64/256), Cudy WR3000E v1 (4,
128/256), ZyXEL NWA55AXE (4, 128/256), ZyXEL WSM20 (3), Aruba AP-303 (3,
128/512), D-Link DAP-X1860 (2), AVM FRITZ!Box 7530 (2), je 1: ZyXEL NWA50AX,
Redmi AX6S, MERCUSYS MR90X, D-Link COVR-X1860, Cudy WR3000S v1, ASUS
TUF-AX4200, ASUS RT-AX53U, Cudy TR3000 v1.

## Wie ermittelt

* Knoten: Karte (`karte.neanderfunk.de`, alle 33 Datenquellen), Stand
  10.09.2026, nur Knoten mit Gluon 2023.2.
* Modell → OpenWrt-Profil über den DTS-`compatible` (wie in
  [feldgeraete-dsa-swconfig.md](feldgeraete-dsa-swconfig.md)).
* Flash/RAM je Profil aus der **OpenWrt Table of Hardware**
  (`toh_dump_tab_separated`), abgeglichen über die Image-URLs. Stichproben
  gegen die Specs in den OpenWrt-Commits (Archer C6 v2, C7 v5, R6120, 4A
  Gigabit) stimmen.
* Nicht in der ToH, Werte aus den OpenWrt-Commits: Genexis Pulse EX400
  (256/256), Cudy WR3000E v1 und WR3000S v1 (128/256), Cudy TR3000 v1
  (128/512).
* Grenzen: je Modell, nicht je Gerät – Varianten (FRITZ!Box 7360 SL: 16 oder
  32 MB) sind nicht unterschieden. **Gemessen ist das nicht.**

## Künftig gemessen

`neanderfunk-respondd` meldet je Knoten die tatsächliche Hardware:
`nodeinfo.neanderfunk.hardware.flash` (Chipgröße laut Kernel, auf x86 die
Boot-Platte) und Gluons `statistics.memory.total` (RAM). Nach dem Rollout
lässt sich diese Übersicht aus den Kartendaten direkt erzeugen – und Karte
oder Meshviewer könnten beim Knoten zeigen, wenn er in eine der unteren
Klassen fällt.

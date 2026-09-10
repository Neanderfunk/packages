# Feldgeräte: DSA oder swconfig

Stand 2026-09-10. Welche Geräte im Feld ihre LAN-Ports über **DSA** führen,
welche hinter **swconfig**, und ob sich daran mit Gluon 2025.1 etwas ändert.

## Kurzfassung

* Rund **die Hälfte der Knoten auf 2023.2 (263 von 531)** hängt hinter
  swconfig: ath79 (TP-Link, Ubiquiti UniFi AC Pro/Mesh Pro) und ramips
  mt76x8/mt7620.
* **Keines dieser Modelle wechselt mit Gluon 2025.1 (OpenWrt 24.10) auf DSA.**
  Alle haben im 24.10-Baum weiterhin `ucidef_add_switch`.
* Umgekehrt ist alles, was 2023.2 schon als DSA führt, auch unter 24.10 DSA.
  Die beiden Listen sind in beiden Versionen gleich.

## Wie ermittelt

* Knoten: alle 33 Datenquellen der Karte (`karte.neanderfunk.de/config.json`,
  `dataPath` → `nodes.json`), 695 Knoten, davon 531 mit Gluon 2023.2. Gezählt
  sind Knoten, nicht nur die gerade erreichbaren.
* Zuordnung Modell → Board über den DTS-`compatible`, nicht über den
  Modellnamen: den hat OpenWrt 24.10 bei einigen Geräten geändert (etwa
  „Ubiquiti EdgeRouter X KA", „Zyxel").
* Einstufung aus `target/linux/*/base-files/etc/board.d/02_network` des
  jeweiligen Boards (bzw. dem `*)`-Zweig des Subtargets): `ucidef_add_switch` =
  swconfig; Portnamen, die im DTS als Switch-Port stehen (`label` oder
  `openwrt,netdev-name`), = DSA; sonst eigene Netzwerkkarten.
* Bäume: OpenWrt 23.05 aus Gluon **v2023.2.6**, OpenWrt 24.10 aus Gluon
  **v2025.1.3**. Unterstützung in Gluon 2025.1 über die `device()`-Einträge in
  `targets/*` von v2025.1.3, abgeglichen über den OpenWrt-Profilnamen.

Die Namensheuristik allein führt in die Irre: der EdgeRouter X nennt seine
DSA-Ports `eth0`–`eth4`, unter 24.10 per `openwrt,netdev-name`; der
IPQ4019-Switch hat seine Labels in der Kernel-dtsi, nicht im OpenWrt-Baum.

## swconfig — 263 Knoten

In 23.05 und 24.10 gleich.

| Modell | Knoten | Target |
| --- | ---: | --- |
| TP-Link Archer C7 v5 | 98 | ath79 |
| TP-Link Archer C7 v2 | 32 | ath79 |
| TP-Link TL-WR1043ND v2 | 18 | ath79 |
| TP-Link Archer C6 v2 | 18 | ath79 |
| Netgear R6120 | 16 | ramips mt76x8 |
| TP-Link TL-WR1043ND v4 | 14 | ath79 |
| TP-Link TL-WDR3600 v1 | 12 | ath79 |
| TP-Link TL-WR1043ND v3 | 12 | ath79 |
| Ubiquiti UniFi AC Pro | 8 | ath79 |
| TP-Link TL-WDR4300 v1 | 8 | ath79 |
| TP-Link TL-WR1043N v5 | 7 | ath79 |
| Ubiquiti UniFi AC Mesh Pro | 5 | ath79 |
| TP-Link Archer C20i | 3 | ramips mt7620 |
| TP-Link Archer A7 v5 | 3 | ath79 |
| TP-Link Archer C5 v1 | 2 | ath79 |
| TP-Link Archer C7 v4 | 1 | ath79 |
| TP-Link Archer C25 v1 | 1 | ath79 |
| Netgear WNDR3800 | 1 | ath79 |
| Joy-IT JT-OR750i | 1 | ath79 |
| Ubiquiti UniFi AP Pro | 1 | ath79 |
| TP-Link Archer C50 v3 | 1 | ramips mt76x8 |
| Cudy WR1000 | 1 | ramips mt76x8 |

Der **Archer C25 v1** ist in Gluon 2025.1 als `broken` markiert, ohne
`BROKEN`-Build gibt es für ihn kein Image.

## DSA — 138 Knoten

In 23.05 und 24.10 gleich.

| Target | Modelle (Knoten) |
| --- | --- |
| ramips mt7621 | Genexis Pulse EX400 (26), Xiaomi Mi Router 4A Gigabit (17), Ubiquiti EdgeRouter X (9), EdgeRouter X SFP (5), TOTOLINK X5000R (4), ZyXEL NWA55AXE (4), ZyXEL WSM20 (3), TP-Link Archer AX23 v1 (2), D-Link DAP-X1860 A1 (2), D-Link COVR-X1860 A1 (1), ASUS RT-AX53U (1), D-Link DIR-860L B1 (1), ZyXEL NWA50AX (1, ein Port) |
| ipq40xx | GL.iNet GL-B1300 (33), AVM FRITZ!Box 4040 (6), FRITZ!Box 7530 (2) |
| mediatek filogic | Cudy WR3000 v1 (6), Cudy WR3000E v1 (4), Cudy WR3000S v1 (1), ASUS TUF-AX4200 (1), MERCUSYS MR90X v1 (1), Xiaomi Redmi Router AX6S (1) |
| lantiq xrx200 | AVM FRITZ!Box 7412 (3), 7362 SL (1), 7360 V2 (1), 7360 SL (1) |
| mpc85xx | TP-Link TL-WDR4900 v1 (1) |

Der **ZyXEL NWA55AXE** ist in Gluon 2025.1 als `broken` markiert.

## Ohne Switch — 130 Knoten

| Art | Modelle (Knoten) |
| --- | --- |
| ein Port | Ubiquiti UniFi AC Mesh (26), ZyXEL NWA50AX Pro (25), Ubiquiti UniFi AP (8), UniFi AC LR (4), Aruba AP-303 (3), UniFi AC Lite (1), TP-Link CPE210 v3 (1) |
| LAN und WAN je auf eigener Karte | GL.iNet GL-MT3000 (10), TP-Link CPE210 v1 (8), GL.iNet GL-AR150 (4), Extreme Networks WS-AP3825i (4), UniFi AP Outdoor+ (1), Cudy TR3000 v1 (1), TP-Link CPE510 v1 (1) |
| x86 und VMs | QEMU (27), FUTRO S550 und andere FUTRO (4), VMware (2): eigene Netzwerkkarten |

## Was das für `neanderfunk-port-roles` heißt

Das Paket gibt es nur für Gluon 2025.1 (Branch `v2025.1.x`).

| Art | Rolle je Port | VLANs je Port | Mesh-Modus |
| --- | --- | --- | --- |
| DSA | ja | ja | `isolate` in Hardware bei mt7530/mt7531 und qca8k (mt7621, filogic, ipq40xx), sonst `auto` → `separate` (etwa lantiq `gswip`) |
| eigene Karten | ja | ja | `isolate` wirkt immer (Software-Bridge) |
| swconfig | nein, eine Rolle für alle LAN-Ports wie bei Gluon | nein | ohne Wirkung zwischen den LAN-Ports: der Switch bridged sie in Hardware in VLAN 1, der Kernel sieht nur `eth0.1` |

Auf swconfig-Geräten leistet das Paket also nichts über Gluons eigene Seite
„Netzwerk" hinaus; die Seite „Ports" sagt das dort ausdrücklich.

**Denkbar, nicht gebaut:** Rollen je Port auch hinter swconfig, indem das Paket
jedem LAN-Port ein eigenes Switch-VLAN gibt (`eth0.1`, `eth0.3`, `eth0.4` …).
Dann hätte jeder Port ein eigenes Netdev, und die Isolation zwischen Mesh-Ports
fände in der Software-Bridge statt, auf 2023.2 wie auf 2025.1. Der Preis: das
Paket müsste die `switch_vlan`-Sektionen nach jedem `config_generate` selbst neu
schreiben, die Portnummern je Board aus `board.json` holen, und getaggte VLANs
wären nur mit switchweit eindeutigen IDs möglich.

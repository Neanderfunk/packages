Platzbedarf der Pakete: Flash und RAM
=====================================

Was jedes Paket dieses Feeds im Image und zur Laufzeit etwa kostet, als
Entscheidungsgrundlage für die Paketauswahl, gerade auf Geräten mit 8 MB
Flash oder 64 MB RAM. **Alles Schätzungen**, gemessen am 22.11.2026 am Bau
26112210bro (Feed `b99b4e6`). Die Zahlen stehen auch im README jedes
Pakets, Abschnitt „Platzbedarf“.

Übersicht
---------

| Paket | Flash (xz) | RAM dauerhaft | RAM kurzzeitig |
|---|---|---|---|
| [neanderfunk-ap-timer](../neanderfunk-ap-timer/README.md) | 2 KB | – | je Minute `uci get`, eingeschaltet Lua ≈ 0,4 MB *(geschätzt)* |
| [neanderfunk-banner](../neanderfunk-banner/README.md) | 31 KB | – | Login: `nodestatus` 0,6 MB (2,1 MB mit Lua) |
| [neanderfunk-button-bind](../neanderfunk-button-bind/README.md) | 2 bis 3 KB | – | Start, Knopfdruck |
| [neanderfunk-common](../neanderfunk-common/README.md) | 2 KB | – | im Prozess des Aufrufers |
| [neanderfunk-config-mode-theme](../neanderfunk-config-mode-theme/README.md) | 10 KB | – | nur Config-Mode |
| [neanderfunk-ddhcpd](../neanderfunk-ddhcpd/README.md) | 24 bis 26 KB | `ddhcpd` 0,13 bis 0,16 MB | – |
| [neanderfunk-default-hostname](../neanderfunk-default-hostname/README.md) | 2 KB | – | Upgrade-Skript |
| [neanderfunk-domain-from-legacy](../neanderfunk-domain-from-legacy/README.md) | 1 KB | – | Upgrade-Skript |
| [neanderfunk-domainhelper](../neanderfunk-domainhelper/README.md) | 13 KB | ≈ 0,1 MB + 20 bis 40 KB `/tmp` | alle 91 s bis 0,14 MB |
| [neanderfunk-hotfix](../neanderfunk-hotfix/README.md) | 8 KB | `watchdog.sh` ≈ 0,2 MB | alle 7 min 0,1 MB |
| [neanderfunk-legacy-migrate](../neanderfunk-legacy-migrate/README.md) | 3,5 KB | – | Upgrade-Skript |
| [neanderfunk-linkcheck](../neanderfunk-linkcheck/README.md) | 5 KB | 50 bis 100 KB `/tmp` | alle 5 bzw. 8 min 0,1 MB |
| [neanderfunk-migrate-updatebranch](../neanderfunk-migrate-updatebranch/README.md) | unter 1 KB | – | Upgrade-Skript |
| [neanderfunk-node-whisperer](../neanderfunk-node-whisperer/README.md) | 8 KB | 0,16 MB (nicht auf 64-MB-Geräten) | – |
| [neanderfunk-nodeplacer](../neanderfunk-nodeplacer/README.md) | 12 KB | – | stündlich 0,4 MB |
| [neanderfunk-port-roles](../neanderfunk-port-roles/README.md) | 6 KB | – | Upgrade-Skript, Config-Mode |
| [neanderfunk-preserve-wifichannel](../neanderfunk-preserve-wifichannel/README.md) | 1,5 KB | – | Upgrade-Skript |
| [neanderfunk-respondd](../neanderfunk-respondd/README.md) | 11 bis 12 KB | ≈ 15 KB im respondd | je Abfrage |
| [neanderfunk-setup-mode](../neanderfunk-setup-mode/README.md) | 12 KB | – | nur Config-Mode |
| [neanderfunk-setup-wifi](../neanderfunk-setup-wifi/README.md) | 2,5 KB | – | Setup-Mode, Knopfdruck |
| [neanderfunk-ssid-changer](../neanderfunk-ssid-changer/README.md) | 3 KB | 20 KB `/tmp` | je Minute Lua ≈ 0,4 MB *(geschätzt)* |
| [neanderfunk-status-page](../neanderfunk-status-page/README.md) | 2,5 KB | je Gateway 4 KB `/tmp` | je Aufruf der Statusseite |
| [neanderfunk-txpowerfix](../neanderfunk-txpowerfix/README.md) | 1 KB | – | Upgrade-Skript |
| [neanderfunk-weeklyreboot](../neanderfunk-weeklyreboot/README.md) | 1 KB | – | wöchentlich |
| [neanderfunk-wifi-blackout](../neanderfunk-wifi-blackout/README.md) | 2,5 KB | 8 KB `/tmp` | alle 10 min Lua ≈ 0,4 MB *(geschätzt)* |

Alle 25 Pakete zusammen: **etwa 165 KB Flash** (ath79 164 KB von
4,3 MB squashfs, arm64 168 KB von 5,4 MB), also knapp 4 % des Systems.
Dauerhaft im RAM liegen zusammen etwa 0,6 bis 0,8 MB: die Prozesse von
ddhcpd, domainhelper, hotfix (und node-whisperer, wo es dabei ist), der
Anteil im respondd und gut 0,2 MB Zustand unter `/tmp`.

Wie gemessen
------------

**Flash.** Aus dem fertigen Sysupgrade-Image (imageslive) das squashfs
ausgeschnitten und entpackt: TP-Link TL-WDR3600 v1 (ath79, MIPS, hat alle
Pakete) und D-Link M60 (mediatek-filogic, arm64). Dann je Paket dessen
Dateien (laut `opkg files`, dazu die opkg-Metadaten unter
`/usr/lib/opkg/info/`) herausgenommen und mit dem `mksquashfs4` und den
Optionen von OpenWrt neu gepackt (`-comp xz -Xpreset 9 -Xe -Xlc 0 -Xlp 2
-Xpb 2 -b 256k`). Der Unterschied ist der Anteil des Pakets. Der Nachbau
des ganzen Images trifft das Original auf 1 KB genau. Bei kleinen Paketen
streut die Messung um etwa 1 KB, weil sich beim Herausnehmen die
256-KB-Blöcke verschieben; zur Kontrolle wurde jedes Paket zusätzlich
einzeln gepackt. Shell- und Lua-Dateien sind auf allen Targets gleich,
C-Programme (ddhcpd, respondd, node-whisperer, nodeplacer) unterscheiden
sich je Architektur um 1 bis 3 KB.

Unentpackt sind die Pakete etwa viermal so groß. Kommentare sind beim Bau
schon entfernt (Shell: `NfStripShell`, Lua unter `luasrc/`: luasrcdiet);
ohne das wären es auf dem TL-WR1043ND v2 rund 64 KB mehr (48 KB Shell,
12 KB Lua von banner und node-whisperer, Messung 22.11.2026).

Die Abhängigkeiten der Pakete (`libnl-tiny`, `libbatadv`, `libgluonutil`,
`micrond`, `jsonfilter`, `iw` …) sind nicht mitgezählt: Gluon bringt sie
ohnehin mit.

Auf Geräten mit fester Partition verkleinert jedes KB im squashfs das
beschreibbare Overlay um dasselbe, gerundet auf den Löschblock (meist
64 KB).

**RAM.** Am D-Link M60 (512 MB) und am TL-WR1043ND v2 (64 MB):

- *dauerhaft*: eigener Speicher (`RssAnon` aus `/proc/<pid>/status`) der
  Prozesse, die ständig laufen, und Dateien unter `/tmp` (tmpfs, liegt im
  RAM, gezählt in 4-KB-Seiten). Die Seiten der Programmdatei selbst
  (`RssFile`) sind nicht mitgezählt: Sie werden von allen Shells geteilt
  (busybox) oder lassen sich unter Speicherdruck verdrängen und neu vom
  Flash lesen.
- *kurzzeitig*: Spitzenwert (`VmHWM` bzw. `RssAnon`) der Cron-Jobs und
  Hilfsskripte, am 1043v2 zwölf Minuten lang jede Sekunde mitgelesen,
  ohne selbst etwas zu starten (die Prüfskripte von hotfix und linkcheck
  lösen echte Aktionen aus). Nicht in diesen zwölf Minuten Laufendes ist
  nach Art des Skripts geschätzt und so gekennzeichnet.
- Webseiten im Config-Mode und Upgrade-Skripte kosten im Betrieb nichts:
  Sie laufen nur im Config-Mode bzw. einmal beim Start nach einem Update.
- respondd-Module laufen im Prozess `respondd`; gezählt ist ihr
  `.bss` (fester eigener Speicher) und ihr Code.

# Tests

## Host-Tests

`tests/run.sh` (braucht lua5.1). Prueft `manifest.lua` (Parser, strikte
key=wert-Validierung, Datumsparser) und `state.lua` (rollendes
Versuchsfenster, Replay-Schutz, Datei-Roundtrip).

## Testknoten

x86-64-VM (qemu), Gluon v2023.2.5+, Site `nef-21_dias`, Single-Domain,
Node-ID `aa76ee420370`, 235 MB RAM. Zugriff ueber `scripts/node-ssh.sh`
(Schluessel `keys/`, gitignored; aus WSL2 ohne IPv6 ueber den
Windows-OpenSSH-Client).

Vorhanden auf dem Knoten: libecdsautil, libuclient, libuci, libubox, lua
5.1, luaposix, simple-uci, gluon-switch-domain, uclient-fetch. Nicht
vorhanden: `ecdsautil`-CLI (wie erwartet), Toolchain.

### Aufbau

* `scripts/node-push.sh` kopiert `luasrc/` an die echten Pfade und fuehrt
  `510-nodeplacer` aus.
* `scripts/node-fetch-stub.lua` ersetzt `nodeplacer-fetch`, solange der
  C-Helfer nicht gebaut ist: laedt per uclient-fetch, gibt den Teil vor
  `---` **ohne Signaturpruefung** aus.
* Manifest lokal unter `/lib/gluon/status-page/www/nodeplacer/` (uhttpd-
  Home), Mirror `http://[::1]/nodeplacer`, UCI nur per `uci set` ohne Commit.

### Protokoll 2026-09-04 (Lua-Policy mit Stub)

| Fall | Ergebnis |
|---|---|
| Trockenlauf `firmware`, Ziel `10_wlf` stable | ok: autoupdater -n holt `stable.manifest` von firmware.ffnef.de, prueft 3 Signaturen mit den vorhandenen Pubkeys, laedt 20,6 MiB, Hash und `sysupgrade --test` ok, Abbruch wegen Simulation. Laufzeit 2,5 s. |
| Nicht adressiert | still, Exit 0 |
| `domain` auf Single-Domain-Firmware | abgelehnt, Log "firmware has no domains" |
| Ungueltige Zeilen (doppelter branch, unbekannter Key, positional target) | je eine Logzeile, keine Aktion |
| 3 Versuche im Fenster | "waiting", keine Aktion |
| Manifest aelter als zuletzt angewandt | ignoriert |
| `disable=1` | still, Exit 0 |
| Branch unbekannt, keine Pubkeys | abgelehnt |
| Branch unbekannt, Pubkeys im Manifest | Branch-Section nur im UCI-Delta (`uci changes`), `/etc/config/autoupdater` unveraendert; autoupdater liest das Delta |
| Zweite Instanz | "another instance is running" |
| `autoupdater` bzw. `sysupgrade` laeuft (Prozess-Scan) | "autoupdater is running, not touching anything" bzw. sysupgrade, Exit 0 |
| `-n` raeumt `/tmp/firmware.bin` auf, kein Zustand geschrieben | ok, "no-action run finished, autoupdater exit 0" |

Hinweis: Die Meldungen "error downloading manifest: Connection failed"
des regulaeren Autoupdaters im Log sind Normalzustand; meist ist nur einer
der vier konfigurierten Mirrors erreichbar (adorfer).

Hinweis zum Prozess-Scan-Test: `cp /bin/sleep /tmp/autoupdater` taugt
nicht, weil `sleep` ein busybox-Applet ist und die Kopie mit dem Namen
`autoupdater` sofort mit "applet not found" endet. Stattdessen `/usr/bin/lua`
kopieren und damit schlafen.

### Noch nicht getestet

* `domain`-Pfad: zurueckgestellt bis nach dem ersten finalen Release
  (D-026), braucht Multidomain-Image.
* Echter Flash in eine andere Domain (ohne `-n`). Der Trockenlauf zeigt,
  dass alles bis unmittelbar vor `sysupgrade` funktioniert.
* C-Helfer `nodeplacer-fetch` (Signaturpruefung, Kopfpruefung, Exit-Codes):
  braucht den Gluon-Build.
* respondd-Provider.
* check_site.lua und 510 mit echtem `nodeplacer`-Block in site.conf.

## Build-Umgebung fuer den C-Helfer und ein Testimage

* Gluon v2023.2.6 unter `~/build/nodeplacer-gluon`, `make update` gelaufen.
* `site/` = `https://firmware.ffnef.de/stable/21_dias.key/site` (site.conf,
  site.mk, modules, i18n, image-customization.lua) plus:
  * `modules`: Feed `nodeplacer` = `file:///home/adorfer/projekte/freifunk/packages/neanderfunk-nodeplacer`
    (Commit in `PACKAGES_NODEPLACER_COMMIT`, nach Aenderungen am Paket
    nachziehen und `make update` bzw. `git -C packages/nodeplacer pull`;
    der Feed-Alias heisst `nodeplacer`, das Paket darin
    `neanderfunk-nodeplacer`).
  * `image-customization.lua`: `'neanderfunk-nodeplacer'` in der Paketliste.
  * `site.conf`: Block `nodeplacer = { mirrors = {...}, good_signatures = 3 }`.
* Build im Gluon-Container (`contrib/docker`), Skript
  `scripts/build-x86-container.sh`. Grund: Ubuntu 26.04 auf dem Host liefert
  `install`, `ls`, `sort`, `date`, `stat` aus uutils, `find` ist bfs und
  `grep` ist ugrep; der OpenWrt-Prereq-Check lehnt schon `install` ab.
  Ausserdem fehlen libncurses-dev, zlib1g-dev, libssl-dev, libelf-dev,
  gettext, qemu-utils, ecdsautils (sudo).
* Docker-Gruppe wurde nachtraeglich gesetzt; bestehende Shells sehen sie
  nicht (`sg`/`newgrp` gibt es auf 26.04 nicht). Eine frische Sitzung ueber
  `wsl.exe -u adorfer -- bash -lc '...'` hat die Gruppe.
* Der Container-Build braucht `--build-arg TARGETOS=linux --build-arg
  TARGETARCH=amd64`, sonst 404 beim editorconfig-checker-Download.

### Protokoll 2026-09-04, zweiter Teil: C-Helfer und respondd auf dem Knoten

Paket `nodeplacer_0.1-1_x86_64.ipk` (13 KB, damals noch ohne
Community-Praefix) aus dem Container-Build per
`opkg install` eingespielt. Postinst meldet Status 1, weil `check_site.lua`
gegen die site.json des Knotens laeuft, die noch keinen `nodeplacer`-Block
hat; im Imagebuild laeuft der Check zur Bauzeit. Dateien sind vollstaendig
installiert.

Signaturtests mit drei Testschluesseln (`keys/test-sign-*`), Pubkeys per
`uci add_list nodeplacer.settings.pubkey` (Delta, kein Commit), Manifeste
mit `scripts/sign-test-manifest.sh` signiert:

| Fall | Ergebnis |
|---|---|
| 3 von 3 Signaturen gueltig | Body auf stdout, Exit 0 |
| `good_signatures=4` bei 3 Schluesseln | "only 3 valid public keys, but 4 signatures required", Exit 1 |
| Pubkey-Fallback auf Autoupdater-Branch (falsche Schluessel) | "0 valid signatures, 3 are required", Exit 3 |
| Mirror liefert 404 | "no manifest found on any mirror", Exit 2 |
| Mirrors auf der Kommandozeile, erster 404 | zweiter Mirror wird genommen, Exit 0 |
| `EXPIRES` in der Vergangenheit | "expired", Exit 3 |
| `FORMAT=2` | "unsupported FORMAT", Exit 3 |
| `EXPIRES` fehlt | "missing DATE or EXPIRES", Exit 3 |
| Ein Byte im Body nach dem Signieren geaendert | 0 gueltige Signaturen, Exit 3 |
| `DATE` in der Zukunft (Uhr des Knotens) | Warnung "clock seems to be incorrect", bei Uptime > 600 s weiter (wie Autoupdater) |
| Kompletter Trockenlauf `nodeplacer -n` mit echtem Helfer, signiertem Manifest, Ziel 10_wlf | Autoupdater laedt und prueft das 10_wlf-Image, Abbruch wegen Simulation, Image aufgeraeumt, kein Zustand geschrieben |
| respondd | `nodeinfo.software.nodeplacer` = `{"enabled":true}` bzw. mit `target`, `attempts`, `last_manifest_date` aus `/tmp/nodeplacer.state` |

Damit sind alle Bausteine einzeln und im Zusammenspiel auf dem Knoten
verifiziert. Offen bleibt der echte Flash (ohne `-n`) und der
`domain`-Pfad (Multidomain-Image).

### Protokoll 2026-09-04, dritter Teil: Imagebuild und lokaler End-to-End-Flash in qemu

* Imagebuild x86-64 im Container: `gluon-nef-21_dias-26090405npt-x86-64`
  (factory .img.gz/.vdi/.vmdk, sysupgrade .img.gz, `stable.manifest`).
  Hinweis im Log "recursive dependency detected ... babeld" stammt aus
  dem OpenWrt-Feed und ist unabhaengig von nodeplacer.
* Factory-Image lokal in qemu (KVM, 256 MB, zwei virtio-NICs im
  Usermode-Netz, serielle Konsole per Telnet-Socket, `console.py` im
  Scratchpad). Achtung: die VM waehlt sich ueber Tunneldigger real ins Mesh
  der Domain ein; nach dem Test herunterfahren.
* Nach dem ersten Boot: `510-nodeplacer` hat `mirror` (beide Eintraege aus
  site.conf), `good_signatures=3`, `disable=0` geschrieben und
  `/usr/lib/micron.d/nodeplacer` mit Zufallsminute angelegt. WAN ist eth1.
* Lokaler Manifest- und Firmware-Server: `python3 -m http.server 8080` auf
  dem Host, aus dem Gast als 10.0.2.2 erreichbar. Serviert
  `nodeplacer.manifest` (Testschluessel, Eintrag fuer Node-ID 525400123456,
  `branch=nptest`, `pubkey=` x3) und `fw/nptest.manifest` (Kopie des
  gebauten `stable.manifest` mit `BRANCH=nptest`, mit Testschluesseln
  signiert) plus das Sysupgrade-Image.
* Trockenlauf `nodeplacer -n`: Branch `nptest` unbekannt, Section mit den
  Manifest-Pubkeys nur im UCI-Delta, Autoupdater holt `nptest.manifest`
  vom Host, prueft 3 Signaturen, laedt und prueft das Image, Abbruch.
* **Echter Lauf `nodeplacer`**: Autoupdater flasht, Gast bootet neu.
  Danach: gleiche Release (gleiches Image, gewollt), `authorized_keys`
  erhalten (Konfiguration ueberlebt sysupgrade), keine `nptest`-Section
  mehr, kein `/tmp/nodeplacer.state`, `nodeplacer.settings` wieder aus
  site.conf (Testschluessel und lokaler Mirror aus dem Delta sind weg),
  Cronjob neu angelegt.

Damit ist der Firmware-Pfad vollstaendig nachgewiesen, ohne den
Testknoten von adorfer anzufassen. Ein echter Domainwechsel des
Testknotens (21_dias nach 10_wlf ueber firmware.ffnef.de) ist mit
Testschluesseln im UCI-Delta jederzeit moeglich, braucht aber das Go.

### Protokoll 2026-09-04, vierter Teil: echter Domainwechsel des Testknotens

Zweiter Testknoten (x86_64-VM im LAN von adorfer, Gluon v2023.2.5, Release
25122513sta, Site `nef-21_dias`, Node-ID bc241158f1c6, Hostname
`dias-x64-upgradetest-f1c6`, mit Backup).

* `nodeplacer_0.1-1_x86_64.ipk` per opkg installiert (Postinst-Status 1
  wegen fehlendem site.conf-Block, wie dokumentiert).
* Einstellungen nur im UCI-Delta: Testschluessel als `pubkey`,
  `good_signatures=3`, Mirror `http://[::1]/nodeplacer`. Signiertes
  Manifest lokal auf uhttpd:
  `bc241158f1c6 firmware branch=stable mirror=http://firmware.ffnef.de/firmware/stable/10_wlf/sysupgrade mirror=http://[fd66:...:640a::733]/...`
* Trockenlauf `nodeplacer -n`: ok, Branch `stable` existiert lokal, daher
  keine Autoupdater-Aenderung; das 10_wlf-Manifest wurde mit den echten
  Community-Schluesseln des Knotens geprueft.
* **Echter Lauf `nodeplacer`**: Autoupdater flasht das 10_wlf-Image,
  Knoten bootet neu (SSH-Sitzung bricht wie erwartet ab, Rueckkehr nach
  etwa zwei Minuten).
* Danach: Site-Code `nef-10_wlf`, Release 25122513sta, Hostname
  unveraendert, SSH-Schluessel erhalten, Autoupdater-Mirrors jetzt die
  von 10_wlf (aus der neuen site.conf), nodeplacer nicht mehr installiert
  (nicht Teil der 10_wlf-Firmware), kein Zustand, keine UCI-Delta-Reste.

Ergebnis: erster echter, serverseitig gesteuerter Domainwechsel eines
Knotens innerhalb der Community. Rueckweg nach 21_dias funktioniert
identisch (Manifest mit 21_dias-Mirror).

### Lint

* luacheck 1.1.0 im Container: 0 Warnungen nach zwei Korrekturen
  (Variablen-Shadowing, leerer if-Zweig).
* shellcheck 0.9.0: nur Info-Hinweise (SC2012/2013/2016/2295) in den
  Hilfsskripten, keine Fehler.

### Backport-Check v2021.1.x (nur Quelltextvergleich, kein Build)

Vorhanden in v2021.1.2: `gluon.util` `glob`, `get_uptime`, `node_id`,
`readfile`, `log`, `contains`; `gluon-switch-domain`; micron.d-Cron;
`simple-uci` `get_bool`; `gluon.mk` mit `BuildPackageGluon` und
`GluonCheckSite`; respondd-Provider-API; Autoupdater-Optionen `-f`,
`--force-version`, `-b`, Mirrors als Argumente; `uclient.c` fast identisch.
Zu pruefen beim Backport: `alternatives()` in check_site (in 2021.1 evtl.
nicht vorhanden, dann `disable` nur als Zahl pruefen), OpenWrt 19.07
libuclient/CMake-Version fuer den C-Helfer.

### Nachtrag 2026-09-04: Umbenennung auf neanderfunk-nodeplacer

Paketname mit Community-Praefix (D-029). Geprueft nach der Umbenennung:

* `make update` und Paketbau im Container erfolgreich,
  `neanderfunk-nodeplacer_0.1-1_x86_64.ipk`. Wichtig: der Paket-Modus
  braucht vorher Gluons `config`-Target, sonst wird zwar kompiliert und
  nach staging installiert, aber kein ipk erzeugt (die alte
  `openwrt/.config` kannte den neuen Paketnamen noch nicht).
* Installation des umbenannten ipk auf dem Testknoten: alle Dateien am
  richtigen Platz. Einzige Aenderung an den Laufzeitpfaden: der
  respondd-Provider heisst jetzt
  `/usr/lib/respondd/neanderfunk-nodeplacer.so`, weil `gluon.mk` ihn nach
  `PKG_NAME` benennt. Inhalt und Feldname (`nodeinfo.software.nodeplacer`)
  bleiben gleich; respondd laedt alle Module des Verzeichnisses.
  Danach wieder deinstalliert, der Knoten ist unveraendert.

### Rueckweg 2026-09-04: 10_wlf zurueck nach 21_dias mit dem umbenannten Paket

Gleicher Ablauf wie der Hinweg, diesmal mit
`neanderfunk-nodeplacer_0.1-1_x86_64.ipk` und einem Manifest, das auf die
21_dias-Mirrors zeigt. Ergebnis: Site-Code wieder `nef-21_dias`, Hostname
und SSH-Schluessel erhalten, Autoupdater-Mirrors wieder die von 21_dias,
Gateway der Domain 21 im Mesh, keine UCI-Reste, kein Zustand in `/tmp`.
Der Knoten laesst sich also in beide Richtungen verschieben.

Betriebshinweise vom Knoten: busybox dort kennt weder `setsid` noch
`nohup`; um `nodeplacer` ueber das Ende der SSH-Sitzung hinaus laufen zu
lassen, genuegt `(nodeplacer > /tmp/np-run.log 2>&1 &)`. Der Reboot nach
dem Flash dauert rund zehn Sekunden (adorfer), die VM ist also sehr schnell
wieder da.

### Protokoll 2026-09-04: Zielschluessel und Zielschwelle (D-030)

Auf dem Testknoten in `nef-21_dias` (lokal: Branch `stable`, fuenf
Community-Schluessel, Schwelle 3), alle Laeufe mit `-n`, also ohne Flash.
Manifest lokal per uhttpd, mit den drei Testschluesseln signiert.

| Fall | Manifest-Eintrag | Ergebnis |
|---|---|---|
| T1 | nur `mirror=` | kein Delta, 5 Schluessel / 3 Signaturen, Autoupdater prueft und laedt das echte 21_dias-Image |
| T2 | `good_signatures=2` | Delta nur `good_signatures='2'`, Schluessel bleiben lokal, Lauf erfolgreich |
| T3 | `good_signatures=99` | Abbruch vor dem Autoupdater, **kein Delta** |
| T4 | ein fremder `pubkey=` | Abbruch (1 Schluessel, Schwelle 3), **kein Delta** |
| T5 | drei Testschluessel, `good_signatures=3` | Delta ersetzt die Schluesselliste, Autoupdater lehnt das echte Manifest mit "0 valid signatures, 3 are required" ab |
| T6 | drei Testschluessel, `good_signatures=1` | Delta setzt Schluessel und Schwelle, Autoupdater lehnt ab ("0 valid signatures, 1 are required") |

T5 und T6 sind der eigentliche Nachweis: der Autoupdater prueft mit den
Schluesseln aus dem Manifest, nicht mehr mit denen des Knotens. Frueher
wurden mitgelieferte Schluessel bei bekanntem Branch ignoriert, das echte
Manifest waere durchgegangen.

`/etc/config/autoupdater` blieb in allen Laeufen unveraendert (Schwelle
dort weiterhin 3). Wichtig war die Reihenfolge im Code: erst pruefen, dann
ins Delta schreiben. In einer Zwischenfassung wurde zuerst geschrieben,
dadurch blieb nach T3 und T4 ein halb angewendetes Delta liegen, das bis
zum naechsten Reboot auch den regulaeren Autoupdater des Knotens haette
scheitern lassen.

Nach dem Test: Paket deinstalliert, UCI zurueckgesetzt, Manifeste und
Firmware-Datei entfernt, Knoten unveraendert in `nef-21_dias`.

### Protokoll 2026-09-04: Vertrauensanker aktiver Autoupdater-Branch (D-031)

Auf dem Testknoten in `nef-21_dias`. Lokal: aktiver Branch `stable` mit
Schwelle 3, Branch `broken` mit Schwelle 1, je fuenf Community-Schluessel.
Als Schluessel fuer die Steuerdatei die drei Testschluessel per UCI-Delta,
zwei Manifeste, eines mit drei und eines mit einer Signatur. Geprueft mit
`nodeplacer-fetch`, also ohne jeden Flash.

| Fall | Konfiguration | Manifest | Erwartet | Ergebnis |
|---|---|---|---|---|
| A | nichts in site.conf, Branch `stable` | 3 Signaturen | angenommen | exit 0 |
| A | dito | 1 Signatur | abgelehnt | exit 3, "only carried 1 valid signature" |
| B | Branch im Delta auf `broken` (Schwelle 1) | 1 Signatur | angenommen | exit 0 |
| C | Override `good_signatures=1`, Branch `stable` | 1 Signatur | angenommen | exit 0 |
| C | ohne Override, Branch `stable` | 1 Signatur | abgelehnt | exit 3 |
| D | weder Schluessel noch Schwelle gesetzt | 3 Testsignaturen | abgelehnt | exit 3, "0 valid signatures" (es gelten die Community-Schluessel) |
| E | aktiver Branch existiert nicht | beliebig | Konfigurationsfehler | exit 1, "no autoupdater branch configured to take the keys and the signature threshold from" |

B ist der Nachweis fuer die Regel: derselbe Knoten, dasselbe Manifest,
nur der aktive Branch anders, und die Schwelle folgt. C zeigt, dass das
Override gewinnt, wenn es gesetzt ist. E zeigt das Verhalten fail closed.

Danach Paket deinstalliert, UCI zurueckgesetzt, Knoten unveraendert.

### Protokoll 2026-09-04: Zielschwelle folgt eigenem Vertrauensniveau (D-032/D-033)

Anlass: auf 192.168.158.101 (aktiver Branch `broken`, dort Schwelle 1;
`nodeplacer.good_signatures=2` als Override) wurde ein realer Umzug nach
`02_met` (Zielbranch `stable`, lokal mit fuenf Schluesseln und Schwelle 3
konfiguriert, aber gerade nicht aktiv) faelschlich abgelehnt: der Autoupdater
verlangte 3 Signaturen fuer das Zielmanifest, obwohl die Steuerdatei selbst
schon mit 2 als ausreichend akzeptiert worden war.

Nach dem Fix, alles mit `nodeplacer -n`:

| Test | Aufbau | Ergebnis |
|---|---|---|
| Erfolg | echtes, live signiertes `nodeplacer.manifest`, Ziel `02_met` stable | `branch stable: 5 pubkeys, 2 signatures required` (statt 3), Autoupdater akzeptiert das nur zweifach signierte `stable.manifest` von 02_met, laedt und prueft das Image |
| Nach dem Erfolg | `uci get autoupdater.stable.good_signatures` | `3` (Flash-Wert, sauber restauriert), `uci changes autoupdater` ohne `stable.*` |
| Echter Fehlschlag | Testschluessel als Override, Ziel-Mirror `http://[::1]/nichts-hier` (404) | Steuerdatei akzeptiert (2/2 Testsignaturen), Autoupdater scheitert ("no usable mirror found", exit 1) |
| Nach dem Fehlschlag | `uci get autoupdater.stable.good_signatures` | `3`, `uci changes autoupdater` ohne `stable.*` |

Nebenbefund beim Testen: `opkg remove` erzeugt auf diesem Image erneut
Whiteouts (D-Fund vom selben Tag, andere Ursache: hier bewusst zum
Deinstallieren am Testende, nicht durch ein Buildscript). Manuell entfernt,
Knoten am Ende wieder ohne jede nodeplacer-Spur, `nef-21_dias`, 0 offene
UCI-Aenderungen.

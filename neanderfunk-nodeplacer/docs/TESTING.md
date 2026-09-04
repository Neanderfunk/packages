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

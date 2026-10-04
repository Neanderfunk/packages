# Recherche: Was Gluon 2023.2.x bereits mitbringt

Stand: 2026-09-04. Fundstellen beziehen sich auf den lokalen Checkout
`~/projekte/freifunk/firmware/gluon` (Branch v2023.2.x, Tag v2023.2.6) und
den Gluon-packages-Feed (https://github.com/freifunk-gluon/packages).

## 1. Autoupdater: Aufbau und Manifest-Pruefung

Zwei Pakete, die leicht verwechselt werden:

| Paket | Ort | Aufgabe |
|---|---|---|
| `gluon-autoupdater` | `gluon/package/gluon-autoupdater` | Glue: schreibt UCI aus site.conf, Cronjob, respondd-Provider, download.d/abort.d-Hooks |
| `autoupdater` | packages-Feed `admin/autoupdater` (C) | Das eigentliche Programm: Manifest laden, Signaturen pruefen, Image laden, sysupgrade |

### 1.1 UCI-Konfiguration (`/etc/config/autoupdater`)

Wird von `gluon-autoupdater/luasrc/lib/gluon/upgrade/500-autoupdater` bei
jedem `gluon-reconfigure`/Upgrade **komplett aus site.conf neu geschrieben**
(jede Branch-Section wird geloescht und neu angelegt):

```
config autoupdater 'settings'
    option enabled '1'
    option branch 'stable'
    option version_file '/lib/gluon/release'

config branch 'stable'
    option name 'stable'
    list mirror 'http://...'
    option good_signatures '3'
    list pubkey '<hex>'
```

Folgen fuer uns:

* `settings.branch` und `settings.enabled` ueberleben ein Upgrade, die
  Branch-Sections (mirror, pubkey, good_signatures) **nicht**. Nach einem
  Domainwechsel per Firmware gelten also automatisch die Mirrors der neuen
  site.conf. Das ist genau das gewuenschte Verhalten.
* Existiert `settings.branch` in der neuen site.conf nicht, faellt Gluon auf
  den Default-Branch zurueck (Build-Variable `GLUON_AUTOUPDATER_BRANCH`,
  sonst alphabetisch erster Branch).
* Cronjob: `/usr/lib/micron.d/autoupdater`, zufaellige Minute, 04:xx Uhr
  regulaer, jede andere Stunde `--fallback`.

### 1.2 Kommandozeile des Autoupdaters (`admin/autoupdater/src/autoupdater.c`)

```
Usage: autoupdater [options] [<mirror> ...]
  -b, --branch BRANCH  Override the branch given in the configuration.
  -f, --force          Always upgrade to a new version, ignoring its priority
                       and whether the autoupdater even is enabled.
  -n, --no-action      Download and validate the manifest as usual, then only
                       download but do not flash a new firmware if one is
                       available.
  --fallback           Upgrade if and only if the upgrade timespan of the new
                       version has passed for at least 24 hours.
  --force-version      Skip version check to allow downgrades.
  <mirror> ...         Override the mirror URLs given in the configuration. If
                       specified, these are not shuffled.
```

Alle Optionen sind **identisch im Branch v2021.1.x** des packages-Feeds
vorhanden (verglichen per diff). Das ist fuer den Backport wichtig.

Wesentliche Details aus dem Code:

* Manifest-URL: `<mirror>/<branch>.manifest`, Image-URL: `<mirror>/<filename>`.
* `-b` ueberschreibt nur den Branch-Namen; die Branch-Section (`mirror`,
  `pubkey`, `good_signatures`) **muss in UCI existieren**, sonst
  `unable to load branch configuration` und Exit 1.
* Mirrors auf der Kommandozeile ersetzen die UCI-Mirrorliste vollstaendig.
  Pubkeys und good_signatures kommen weiterhin aus der UCI-Branch-Section.
* `-f` uebergeht `enabled=0` und die Wahrscheinlichkeitsrechnung.
* `--force-version` uebergeht `newer_than(manifest.version, /lib/gluon/release)`.
  Ohne diese Option scheitert ein Domainwechsel auf gleiche oder aeltere
  Versionsnummer mit "No new firmware available".
* Vor dem Flashen: `sysupgrade --test --ignore-minor-compat-version`.
  Ein Major-Compat-Sprung (z. B. sehr alte Firmware auf neue mit anderem
  Wired-Mesh-Format) wird damit **nicht** uebergangen.
* Lockfile `/var/lock/autoupdater.lock` (flock). Bei erfolgreichem Lauf wird
  dessen mtime aktualisiert.
* Hooks: `/usr/lib/autoupdater/download.d`, `abort.d`, `upgrade.d`
  (gluon-autoupdater stoppt darin cron, micrond, sysntpd, urngd).
* `-n` laesst das geprueft heruntergeladene Image in `/tmp/firmware.bin`
  liegen (nutzt `ffac-scheduled-sysupgrade` fuer zeitversetztes Flashen).

### 1.3 Manifest-Format (`admin/autoupdater/src/manifest.c`)

```
BRANCH=stable
DATE=2020-10-07 00:00:00+02:00
PRIORITY=7
<model> <version> <sha256> <size> <filename>
...
---
<signature hex>
<signature hex>
```

* Alles **vor** `---` wird zeilenweise (jeweils mit `\n`) in einen SHA256
  gehasht. Zeilen nach `---` sind Hex-Signaturen; unparsbare Zeilen dort
  werden mit Warnung ignoriert.
* Signaturpruefung: `ecdsa_verify_prepare_legacy` + `ecdsa_verify_list_legacy`
  aus **libecdsautil** (Ed25519-artige Kurve von libuecc, "legacy"-Format).
  Es zaehlt die Anzahl (pubkey, signatur)-Paare, die passen; gefordert sind
  mindestens `good_signatures`.
* Zeilenlaengenlimit 512 Zeichen (nur fuer den C-Parser relevant).
* Signieren: `gluon/contrib/sign.sh <secret> <manifest>` teilt die Datei an
  `---`, signiert den oberen Teil mit `ecdsasign` und haengt die Signatur
  unten an. Das Skript ist **formatagnostisch**: es funktioniert mit jeder
  Textdatei, die eine `---`-Zeile enthaelt.

### 1.4 Was auf dem Knoten fuer eine eigene Manifest-Pruefung fehlt

`autoupdater` haengt nur von `libecdsautil` (Bibliothek) ab. Das
Kommandozeilenwerkzeug `ecdsautil` / `ecdsaverify` steckt im separaten
OpenWrt-Paket `ecdsautils` (openwrt/packages `utils/ecdsautils`, Version
0.4.2 in 23.05) und ist auf Gluon-Knoten **nicht** standardmaessig installiert.

Aufruf des Werkzeugs (`src/cli/verify.c`, getopt `s:p:n:`):

```
ecdsaverify [-s signature ...] [-p pubkey ...] [-n num] file
# Exit 0 = mindestens num passende Paare, sonst 1
```

Optionen fuer unser Package:

1. `DEPENDS:=+ecdsautils` (ein kleines Binary plus Symlinks `ecdsasign`,
   `ecdsaverify`; libecdsautil und libuecc sind wegen autoupdater ohnehin da).
2. Eigener kleiner C-Helper im Package (`src/`), der wie autoupdater gegen
   libecdsautil linkt und nur "Datei pruefen, n-of-m" kann.
3. Pruefung in Lua nachbauen: nein (Krypto in Lua 5.1 ohne Bignum-Lib ist
   unrealistisch und fehleranfaellig).

Empfehlung: Option 1 (siehe DECISIONS.md).

## 2. Domainwechsel in Multidomain-Firmware

### 2.1 `gluon-switch-domain` (gluon-core, `luasrc/usr/bin/gluon-switch-domain`)

```
gluon-switch-domain [--no-reboot] <domain>
```

* Prueft `/lib/gluon/domains/<domain>.json` (Existenz, damit auch Aliase).
* Setzt `gluon.core.switch_domain=<domain>` und `gluon.core.reconfigure=1`,
  `uci:save`.
* Ohne `--no-reboot`: `uci:commit('gluon')` und `reboot`. Beim Boot wendet
  `005-set-domain` (gluon-core upgrade) `switch_domain` an und loescht den Key.
* Mit `--no-reboot`: `gluon-reload` (nutzt hoodselector). Fuer uns ist der
  Reboot-Weg robuster und einfacher zu begruenden.
* Der Code ist **identisch in v2021.1.2 und v2023.2.6** (diff leer), in
  v2025.1.3 ebenfalls unveraendert.

Damit ist der im Sketch angedachte Weg "`uci set gluon.core.domain` +
`gluon-reconfigure` + reboot" nicht noetig; `gluon-switch-domain <ziel>` ist
der offizielle Mechanismus und erledigt alles.

### 2.2 Domain-Informationen auf dem Knoten

* `/lib/gluon/site.json`, `/lib/gluon/domains/*.json` (nur Multidomain).
* `uci get gluon.core.domain` = aktuelle Domain-Code.
* nodeinfo: `system.site_code` (aus site.json), `system.domain_code`
  (aus `gluon.core.domain`), `system.primary_domain_code`
  (`gluon-respondd/src/respondd-nodeinfo.c`, `libgluonutil`).
* Lua: `require('gluon.site')` ist ein C-Modul (`gluon-core/src/site.c`)
  ueber site.json + Domain-JSON. Beliebige Keys sind abfragbar:
  `site.nodeplacer.mirrors()` liefert die Liste oder `nil`;
  `site.nodeplacer.good_signatures(2)` liefert Default 2.

### 2.3 Konkurrierende Pakete

* `gluon-hoodselector` (Multidomain, `@GLUON_MULTIDOMAIN`): laeuft alle
  2 Minuten per micron.d und setzt die Domain per Geokoordinaten oder
  Default-Domain. Es wuerde jeden serverseitigen Wechsel **sofort
  zurueckdrehen**. `CONFLICTS:=+gluon-config-mode-domain-select`.
* `gluon-scheduled-domain-switch` (Core): domainweit, aus der Domain-Config,
  kein Konflikt aber Ueberschneidung.

## 3. Identitaet des Knotens

* `gluon.util.node_id()` = `sysconfig.primary_mac` ohne Doppelpunkte
  (`gluon-core/luasrc/usr/lib/lua/gluon/util.lua:106`). Das ist die Node-ID
  aus nodeinfo und auf der Karte.
* `sysconfig` liest `/lib/gluon/core/sysconfig/primary_mac`.
* `network.bat0.macaddr` (aus dem Sketch) ist in Gluon dieselbe Adresse, aber
  `util.node_id()` ist die kanonische und protokollunabhaengige Quelle (auch
  bei Babel/Layer-3 ohne bat0). Empfehlung: `util.node_id()`.

## 4. Package-Infrastruktur

* `gluon/package/gluon.mk`: `BuildPackageGluon` setzt SECTION/CATEGORY
  `gluon`, installiert `files/`, minifiziert `luasrc/` (bei
  `GLUON_MINIFY`), baut `src/respondd.c` zu einem respondd-Provider und
  fuehrt `check_site.lua` als postinst-Check gegen site.conf aus.
* Community-Packages binden es mit `include $(TOPDIR)/../package/gluon.mk`
  ein und benutzen `PKG_NAME`, `PKG_VERSION`, `PKG_LICENSE`, `DEPENDS`.
* `check_site.lua`-API (`gluon-core/luasrc/lib/gluon/check-site.lua`):
  `need_string`, `need_number`, `need_boolean`, `need_string_array_match`,
  `need_table`, `need_one_of`, `need_domain_name`, `in_site`, `in_domain`,
  `alternatives`, `obsolete`. Beispiel fuer Mirror-Pruefung:
  `gluon-autoupdater/check_site.lua`.
* In v2021.1.x liegt die Check-Bibliothek noch unter `scripts/check_site_lib.lua`;
  die Funktionsnamen sind dieselben.
* v2025.1: Mirrors duerfen `https://` (nur mit `tls`-Feature) oder `//`
  (Schema wird zur Laufzeit ergaenzt). Unser check_site sollte dieselben
  Alternativen erlauben, sobald 2025.1 Ziel ist.
* Cron: Datei in `/usr/lib/micron.d/<name>` (micrond liest das
  Verzeichnis). Zufallsminute wie in `500-autoupdater` erzeugen.
* Lock: hoodselector nutzt `posix.fcntl` mit `F_SETLK` auf
  `/var/lock/hoodselector.lock`; autoupdater nutzt flock.
* Lua-Libs, die gluon-core garantiert: `luaposix`, `lua-simple-uci`,
  `lua-jsonc`, `lua-bit32`, `lua-hash`, `lua-platform-info`.
* Download aus Lua/Shell: OpenWrt-Basis liefert `uclient-fetch`; im
  Gluon-Tree wird es nirgends direkt aufgerufen. **Auf einem echten Knoten
  verifizieren** (`which uclient-fetch wget`). Alternative: den Download
  vom `autoupdater`-Binary erledigen lassen, wo moeglich.
* respondd-Provider-Beispiel: `gluon-autoupdater/src/respondd.c`
  (liest UCI, liefert `software.autoupdater.{branch,enabled}` in nodeinfo).

## 5. Beobachtungen aus der Neanderfunk-Firmware

* `sites.nefall.sta`: eine Zeile pro Domain und Template-Variante
  (`21_dias`, `21_dias-key`, `10_wlf`, ...), Spalten u. a. `RELBRANCH`,
  `SITE_CODE`, `DOMAIN_NR`, `FWWEBSITE_HOST`, `KEY_FILE_SIGN`.
* Template `templates/05_mon/site.conf`: `site_code = 'METAPREFIX-DOMAINNR_SITESMALL'`
  (z. B. `nef-10_wlf`), Branches `stable` (good_signatures 3) und `broken`
  (good_signatures 1), vier Mirrors je Branch mit Muster
  `http://<host>/firmware/<branch>/<DOMAINNR_SITESMALL>/sysupgrade`.
* Das gleiche Signaturschluessel-Set (`ffnef.signkeys`) wird in allen
  Domains verwendet. Damit kann ein Knoten das Manifest der Zieldomain mit
  seinen bereits konfigurierten Pubkeys pruefen.
* `modules` der Site: Feeds `eulenfunk community ffac ffffm`. Ein neues
  Package kann im eulenfunk-Feed (Branch v2023.2.x) landen.
* Eigene Vorarbeit `eulenfunk-migrate-updatebranch`: Shell-Upgrade-Skript
  `910-...`, das beim Upgrade Branches umsetzt. Zeigt die Shell-Variante mit
  `gluonShellDiet.sh`.

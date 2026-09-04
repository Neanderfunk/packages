# Design: nodeplacer

Stand: 2026-09-04. Entscheidungen mit Begruendung stehen in
[DECISIONS.md](DECISIONS.md); dieses Dokument beschreibt den Zielzustand.

## 1. Problem

Ein Knoten laeuft in einer Layer-2-Domain, in die er nicht gehoert: falsche
Firmware geflasht, Umzug des Besitzers, Neuzuschnitt von Domains, Besitzer
nicht erreichbar. Die Community moechte ihn **gezielt und einzeln** in die
richtige Domain bringen, ohne physischen Zugriff und ohne den Besitzer zu
brauchen.

Bestehende Mittel greifen nicht:

* hoodselector braucht Geokoordinaten und Multidomain und entscheidet
  dezentral; er laesst sich nicht fuer einen einzelnen Knoten uebersteuern.
* scheduled-domain-switch verschiebt ganze Domains, nicht einzelne Knoten.
* Der Autoupdater kennt nur "gleiche Domain, neuere Version".

## 2. Grundidee

Der Knoten holt regelmaessig eine **signierte Steuerdatei** (Manifest) von
einem Server der eigenen Community, prueft die Signaturen mit den bereits
vorhandenen Autoupdater-Schluesseln und schaut, ob er selbst darin
adressiert ist. Wenn ja, fuehrt er den beschriebenen Wechsel aus.

Die Steuerdatei uebernimmt bewusst das Autoupdater-Manifest-Format
(Kopfzeilen, Nutzdaten, `---`, Signaturen), damit Signierwerkzeuge
(`contrib/sign.sh`, `ecdsasign`), Schluessel und Denkweise der Maintainer
unveraendert weiterverwendet werden koennen.

## 3. Betriebsmodi

Die Firmware kann Single-Domain oder Multidomain sein; das Manifest kann pro
Knoten eine von zwei Methoden anweisen.

### 3.1 Methode `domain` (nur Multidomain-Firmware, zurueckgestellt, D-026)

Ziel ist eine Domain, die in der installierten Firmware enthalten ist.

1. Pruefen: `/lib/gluon/domains/<ziel>.json` existiert, `<ziel>` ungleich
   `gluon.core.domain`.
2. `gluon-switch-domain <ziel>` aufrufen. Das setzt `switch_domain`,
   committet und rebootet; beim Boot wendet gluon-core den Wechsel an.
3. Kein eigenes Herumschreiben an `gluon.core.domain`, kein eigenes
   `gluon-reconfigure`.

Ist die Zieldomain nicht in der Firmware enthalten, ist dieser Weg
unmoeglich; das Manifest muss dann Methode `firmware` verwenden. Der Knoten
lehnt eine unpassende Anweisung mit Logmeldung ab.

### 3.2 Methode `firmware` (Single-Domain, auch Multidomain moeglich)

Ziel ist eine andere Firmware derselben Community, deren Image auf dem
Autoupdate-Server der Zieldomain liegt.

1. Mirrors der Zieldomain kommen aus dem Manifest.
2. Branch: aus dem Manifest, sonst der aktuelle `autoupdater.settings.branch`.
3. Aufruf des regulaeren Autoupdaters mit Kommandozeilen-Overrides, ohne
   UCI-Aenderungen:

   ```
   autoupdater -f --force-version -b <branch> <mirror1> [<mirror2> ...]
   ```

   * `-f` ignoriert `enabled=0` und die Update-Wahrscheinlichkeit.
   * `--force-version` erlaubt gleiche oder aeltere Versionsnummer.
   * Mirrors auf der Kommandozeile ersetzen die konfigurierten.
   * Pubkeys und `good_signatures` kommen aus der lokalen UCI-Branch-Section
     `<branch>`. Sie muss existieren; bei gleicher Community ist das der
     Normalfall.
4. Der Autoupdater prueft das Firmware-Manifest der Zieldomain, laedt das
   Image, prueft Hash und `sysupgrade --test`, flasht und rebootet.
5. Nach dem Boot schreibt die neue Firmware ihre eigenen Mirrors und
   Pubkeys aus ihrer site.conf nach UCI. `settings.branch` bleibt erhalten.

Sonderfaelle:

* Branch existiert lokal nicht: Manifest kann Pubkeys mitliefern; dann wird
  vor dem Aufruf eine Branch-Section **nur im UCI-Delta** (`uci set` ohne
  `commit`) angelegt. libuci wendet das Delta beim Laden an, der Autoupdater
  sieht die Section also. Nach Reboot ist sie weg. Das ist der Weg aus dem
  Sketch; er ist nur fuer diesen Sonderfall noetig.
* Wechsel auf eine Firmware mit anderem Major-Compat (sehr alte Knoten):
  `sysupgrade --test` scheitert, der Autoupdater bricht ab. Solche Knoten
  brauchen einen Zwischenschritt (erst Update in der alten Domain).

### 3.3 Verhalten je Firmware-Typ

| Firmware | `domain` | `firmware` |
|---|---|---|
| Single-Domain | abgelehnt (keine Domains) | ja |
| Multidomain, Ziel enthalten | ja (bevorzugt, kein Flash) | moeglich, aber unnoetig |
| Multidomain, Ziel nicht enthalten | abgelehnt | ja |

## 4. Steuerkanal

### 4.1 Abruf

* Liste von Basis-URLs in site.conf: `nodeplacer.mirrors`.
* Dateiname: `<basis>/nodeplacer.manifest`, eine zentrale Datei fuer die
  ganze Community, bei Neanderfunk fuer alle 40+ Domains (D-010). Sie
  enthaelt nur die Ausnahmefaelle und hat nie mehr als 100 Zeilen (D-021). Sie wird von Hand gepflegt und signiert (D-017);
  eine Datei pro Quell-Domain waere fuer Menschen mehr Arbeit ohne
  Nutzen bei einer Handvoll Eintraegen.
* Mirrors werden zufaellig durchprobiert; erster erfolgreicher Download
  mit gueltigen Signaturen gewinnt. Mirror ohne Datei (404) ist kein Fehler,
  sondern "nichts zu tun".
* Rhythmus: stuendlich zu einer zufaelligen Minute (wie Autoupdater-Fallback),
  Cron-Datei `/usr/lib/micron.d/nodeplacer`, erzeugt vom Upgrade-Skript.

### 4.2 Signaturpruefung

* Verfahren wie im Autoupdater: alles vor `---` zeilenweise hashen,
  Zeilen danach sind Signaturen, n-of-m gegen Pubkeys.
* Pubkeys: standardmaessig die des aktuell konfigurierten Autoupdater-
  Branches (`autoupdater.<branch>.pubkey`). Optional eigener Satz in
  site.conf (`nodeplacer.pubkeys`), falls die Community die
  Umzugs-Befugnis enger fassen will als die Firmware-Signatur.
* Mindestanzahl: `nodeplacer.good_signatures` aus site.conf (Pflicht).
* Implementierung ueber **libecdsautil**, das wegen des Autoupdaters auf
  jedem Knoten liegt. Download, Hashen und Pruefung erledigt ein kleiner
  C-Helfer `nodeplacer-fetch`, der aus der Autoupdater-Codebasis
  abgeleitet ist (D-015). Er gibt nur verifizierte Nutzdaten an das
  Lua-Hauptprogramm weiter.
* Bei zu wenigen gueltigen Signaturen: Abbruch mit Logmeldung, keine
  Aktion, naechster Mirror wird **nicht** probiert (ein manipulierter Mirror
  darf nicht durch Wiederholung "gewinnen"; ein defekter Mirror wird
  ohnehin beim naechsten Lauf durch die Zufallsauswahl umgangen).

### 4.3 Manifest-Inhalt

Siehe [MANIFEST-FORMAT.md](MANIFEST-FORMAT.md). Kurzfassung:

```
FORMAT=1
DATE=2026-09-04 12:00:00+02:00
EXPIRES=2026-10-04 12:00:00+02:00
80afcacfc55c domain target=ffnef21dias
80afcacfc55d firmware branch=stable mirror=http://firmware.ffnef.de/firmware/stable/10_wlf/sysupgrade mirror=http://[fd66:666e:6566:640a::733]/firmware/stable/10_wlf/sysupgrade
---
<signatur>
<signatur>
```

## 5. Ablauf auf dem Knoten (ein Lauf)

Zweiteilung (D-015): C-Helfer holt und verifiziert, Lua entscheidet.

```
[Lua: /usr/sbin/nodeplacer]
lock holen (sonst exit)
disable-Schalter pruefen (uci nodeplacer.settings.disable) -> exit
autoupdater oder sysupgrade laeuft (/proc-Scan)? -> exit (D-024)
setup-mode aktiv? -> exit
nodeplacer-fetch aufrufen, stdout einsammeln

    [C: nodeplacer-fetch, aus autoupdater.c/uclient.c/manifest.c]
    UCI lesen: nodeplacer.settings.mirror, good_signatures, pubkey
      (pubkey-Fallback: autoupdater.<settings.branch>.pubkey)
    mirrors mischen
    fuer mirror in mirrors:
        <mirror>/nodeplacer.manifest laden (404/fehler -> naechster mirror)
        zeilen bis --- hashen, signaturen danach sammeln
        n-of-m pruefen (zu wenig -> exit 3, kein weiterer mirror)
        kopf pruefen (FORMAT, DATE, EXPIRES)
        verifizierten nutzdatenteil auf stdout, exit 0
    exit 2 (kein manifest gefunden)

kopf und zeilen parsen (manifest.lua)
eintrag fuer eigene node_id suchen (keiner -> exit 0, "nicht adressiert")
plausibilitaet: ziel != aktuell, methode passt zur firmware
zustand pruefen: nicht bereits N Versuche fuer dieses ziel, cooldown, DATE neuer als zuletzt
versuch protokollieren (uci nodeplacer.state.*, commit)
aktion ausfuehren (gluon-switch-domain | autoupdater ...)
```

Warum der C-Helfer auch den Kopf prueft: `DATE`/`EXPIRES` liegen im
signierten Teil; die Pruefung ist im C-Code (parse_rfc3339) vorhanden.
Lua bekommt nur Manifeste, die formal gueltig und nicht abgelaufen sind.

## 6. Sicherheit

* Schutz vor fremder Steuerung: ausschliesslich signierte Manifeste,
  Mindestsignaturen aus der Firmware (nicht aus dem Manifest). Ein Angreifer
  mit Kontrolle ueber einen Mirror kann nur alte, echte Manifeste ausliefern.
* Replay: `EXPIRES` (Pflicht, empfohlen Wochen, nicht Monate) begrenzt, wie
  lange ein altes Manifest wirkt. Zusaetzlich merkt sich der Knoten das
  `DATE` des zuletzt angewandten Manifests und wendet aeltere nicht an.
* Rueckweg: Methode `firmware` kann nur auf Images zeigen, die vom
  Autoupdater mit den lokalen Pubkeys akzeptiert werden. Das Manifest
  allein kann keine fremde Firmware einschleusen.
* Pubkeys im Manifest (Sonderfall 3.2) sind der einzige Punkt, an dem das
  Manifest Vertrauen ausweitet. Deshalb nur im RAM und nur fuer diesen
  einen Autoupdater-Lauf.
* `disable`-Schalter fuer den Besitzer (UCI, optional spaeter Config-Mode).
  Der Knoten liegt in der Verantwortung seines Besitzers; die Community
  darf ihn verschieben, aber der Besitzer soll es unterbinden koennen.

## 7. Robustheit

* **Ping-Pong** zwischen Domains: Nach einem Wechsel laedt der Knoten das
  Manifest seiner **neuen** Domain. Solange dort kein Eintrag fuer ihn
  steht, passiert nichts. Wird er dort zurueckadressiert, greift der
  Zustandsspeicher: pro Ziel maximal N Versuche in Zeitraum T, danach
  Stillstand mit Logmeldung (nodeinfo zeigt das an).
* **Fehlgeschlagener Firmware-Wechsel** (Mirror down, Image fehlt, sysupgrade
  --test scheitert): autoupdater bricht ab, abort.d-Hooks starten Dienste
  neu, der Knoten bleibt in der alten Domain und versucht es beim naechsten
  Lauf erneut, bis das Versuchslimit greift.
* **Stromausfall waehrend Reboot** bei `domain`: gluon-core wendet
  `switch_domain` beim naechsten Boot an (committed). Kein eigener Zustand
  noetig.
* **Zeitfenster**: Erste Version ohne Zeitfenster; der Zeitpunkt wird vom
  Betreiber ueber das Veroeffentlichen des Manifests gesteuert. Ein
  optionales `WINDOW=`-Kopffeld ist als Erweiterung vorgesehen.
* **Nicht gleichzeitig mit Autoupdater**: vor jeder Aktion wird `/proc`
  nach Prozessen `autoupdater` und `sysupgrade` durchsucht; laeuft einer,
  bricht nodeplacer still ab (D-024). Zusaetzlich stoppt gluon-autoupdater
  micrond in download.d.
* **hoodselector**: out of scope (D-011). Nur `CONFLICTS` im Makefile,
  damit der Build ein Zusammenbauen verhindert.

## 8. Konfiguration in site.conf

```lua
-- identisch in allen Site-Templates: zentraler Pfad, nicht das
-- domainspezifische Firmware-Verzeichnis (D-010)
nodeplacer = {
  mirrors = {
    'http://firmware.ffnef.de/nodeplacer',
    'http://[fd66:666e:6566:640a::733]/nodeplacer',
  },
  good_signatures = 2,
  -- optional, sonst Pubkeys des Autoupdater-Branches:
  -- pubkeys = { '<hex>', '<hex>' },
  -- optional, Default 0:
  -- disable = 0,
},
```

`check_site.lua` prueft: `mirrors` Array von `^http://` (spaeter auch
`https://`/`//` wie 2025.1), `good_signatures` Zahl und, falls `pubkeys`
gesetzt, `<= #pubkeys`. Alles `in_site`, nicht in Domains (Multidomain:
gleiche Mirrors fuer alle Domains einer Firmware).

## 9. UCI und Zustand auf dem Knoten

`/etc/config/nodeplacer` (Flash, nur vom Upgrade-Skript und vom Besitzer
geschrieben):

```
config nodeplacer 'settings'
    option disable '0'          # aus site.conf beim Upgrade gesetzt, falls nicht vorhanden
    list mirror 'http://...'    # aus site.conf, wird bei jedem Upgrade neu geschrieben
    option good_signatures '2'
    list pubkey '<hex>'         # optional
```

`settings.disable` ist die einzige Option, die der Besitzer aendert und die
ueber Upgrades hinweg erhalten bleibt (Upgrade-Skript setzt sie nur, wenn
sie fehlt, analog zu `autoupdater.settings.enabled`).

Zustand eines Wechselversuchs liegt **ausschliesslich im RAM** (D-012):

* UCI-Delta unter `/tmp/.uci` (uci set/save ohne commit) fuer
  Autoupdater-Branch-Section, Mirrors, Pubkeys, falls die Kommandozeile
  nicht reicht.
* `/tmp/nodeplacer.state` (JSON): `last_manifest_date`, `target`,
  `attempts`, `first_attempt_uptime`. Versuchslimit 3 in 7 Tagen als
  rollendes Fenster; Reboot setzt zurueck.

## 10. Sichtbarkeit (respondd/nodeinfo)

Optionaler respondd-Provider (wie `gluon-autoupdater/src/respondd.c`) liefert
in `nodeinfo.software.nodeplacer`: `enabled`, `last_target`, `attempts`,
`last_manifest_date`. Damit sieht man auf der Karte, welche Knoten
haengengeblieben sind. Erste Version: ja, weil klein und fuer den Betrieb
sehr nuetzlich.

## 11. Paket-Layout (umgesetzt)

Das Projekt-Repo ist zugleich ein OpenWrt/Gluon-Feed; das Paket liegt im
Unterverzeichnis `nodeplacer/` (D-022).

```
nodeplacer/                        # Paket
  Makefile                         # BuildPackageGluon + cmake.mk, DEPENDS, CONFLICTS hoodselector
  README.md
  check_site.lua
  files/etc/config/nodeplacer      # leere settings-Section
  luasrc/
    lib/gluon/upgrade/510-nodeplacer      # UCI aus site.conf, Cron-Datei mit Zufallsminute
    usr/sbin/nodeplacer                   # Hauptprogramm (Lua): Lock, Fetch, Parse, Zustand, Aktion
    usr/lib/lua/nodeplacer/manifest.lua   # Parser + Datum (rein, hosttestbar)
    usr/lib/lua/nodeplacer/state.lua      # Versuchszaehler in /tmp/nodeplacer.state
  src/
    CMakeLists.txt
    fetch.c                               # main: UCI, Mirrors, Download, Verify, Ausgabe
    manifest.c/.h                         # aus autoupdater, angepasst: FORMAT/DATE/EXPIRES, Body-Puffer
    uclient.c/.h, hexutil.c/.h, util.c/.h # aus autoupdater (util.c gekuerzt)
    respondd.c                            # nodeinfo.software.nodeplacer
tests/
  test_manifest.lua, run.sh        # Host-Tests (lua5.1)
docs/, sketches/                   # Planung
```

Sortierung des Upgrade-Skripts: nach `500-autoupdater` (wir lesen dessen
UCI-Branch-Sections fuer die Pubkeys), daher `510`.

## 12. Serverseite (bewusst nicht Teil des Projekts, D-017)

* Eine Datei `nodeplacer.manifest` je Mirror, von Hand editiert, von Hand
  mit `gluon/contrib/sign.sh` signiert (gleiche Schluessel wie Firmware).
* Keine Automatisierung im Projekt. Ablauf fuer Menschen steht in
  MANIFEST-FORMAT.md.

## 13. Backport v2021.1.x und Vorwaerts v2025.1

* v2021.1.x: `gluon-switch-domain` identisch, Autoupdater-Optionen
  identisch, check_site-API gleich (anderer Pfad der Bibliothek, fuer das
  Package unerheblich), Lua 5.1, micrond vorhanden. Erwartete Anpassungen:
  keine im Lua-Code; ggf. OpenWrt-19.07-Eigenheiten beim Bauen eines
  C-Helpers.
* v2025.1: Mirror-Schemata `https://` und `//` in check_site nachziehen;
  `gluon.mk`-Aenderung ist marginal. Sonst keine bekannten Bruchstellen.

## 14. Offene Fragen

1. Endgueltiger Name (siehe DECISIONS.md, Vorschlaege dort).
2. (entschieden, D-015) C-Helfer aus der Autoupdater-Codebasis.
3. Soll `firmware` bei Multidomain-Firmware erlaubt sein, wenn `domain`
   moeglich waere? Vorschlag: ja, aber Warnung im Log; der Betreiber weiss,
   was er tut.
4. (entschieden, D-019/D-020) Registrierung und Fremd-Community: siehe
   Abschnitt 15.
5. Sollen Besitzer per Config-Mode (gluon-web) den Schalter sehen?
   Erste Version: nein, nur UCI.
6. (entschieden, D-012) 3 Versuche in 7 Tagen, rollend, im RAM.
7. (erledigt durch D-015) Download uebernimmt der C-Helfer mit libuclient.
8. (entschieden, D-021) C-Helfer gibt den ganzen Nutzdatenteil aus, Lua
   filtert. Datei hat nie mehr als 100, meist unter 10 Zeilen.

## 15. Grenzen: Registrierung und Fremd-Domains

Begriff: "Fremd-Domain" heisst hier eine Domain einer **anderen Community
in einer anderen Region**, nicht eine andere Domain derselben Community.
Umzuege zwischen den eigenen Domains (z. B. `10_wlf` nach `21_dias`) sind
der Normalfall von nodeplacer.

nodeplacer ist fuer Umzuege **innerhalb einer Community** gebaut (gleiche
Signaturschluessel, gleicher Firmware-Server, gleiche site.conf-Familie).
Neanderfunk hat keine fastd-Schluessel- oder Knotenregistrierung (D-019).

Fuer alles darueber hinaus gilt:

* **Registrierung in der Zieldomain.** Hat die Zieldomain eine
  Peer-Registrierung (fastd-Schluessel, WireGuard-Whitelist, Zertifikate),
  muss der Knoten dort **vor** dem Umzug eingetragen sein. nodeplacer
  prueft das nicht; der Knoten kaeme sonst ohne VPN an.
* **Fremde Firmware und alte Konfiguration.** Sysupgrade behaelt UCI. Nach
  dem Flash einer fremden Firmware bleiben Hostname-Praefix, Branch-Namen,
  Einstellungen von Zusatzpaketen und alles, was Upgrade-Skripte nicht
  ueberschreiben, aus der alten site.conf erhalten. Die Zielfirmware muss
  damit umgehen; in vielen Faellen wird die Ziel-Community eine
  Migrations-Firmware bauen muessen (D-020).
* **Abgestimmtes Verfahren.** Ein Umzug in eine fremde Domain ist nur mit
  einem zwischen beiden Communities vereinbarten Ablauf zulaessig:
  Schluessel, Zielfirmware, Zeitpunkt, Ansprechpartner. Knoten "kalt" in
  eine fremde Domain zu schieben soll nicht nur technisch scheitern,
  sondern ist off limits. nodeplacer erzwingt das nicht (die Signaturen
  der eigenen Maintainer entscheiden), die Doku und das README muessen es
  aber unmissverstaendlich sagen.

# Entscheidungs-Log

Laufendes Protokoll der Ueberlegungen und Entscheidungen. Neueste Eintraege
unten anhaengen, bestehende nicht umschreiben (nur Status aendern).
Status: **offen** / **entschieden** / **verworfen**.

## D-001 Projektname

* Status: **entschieden** (adorfer, 2026-09-04)
* Name: **nodeplacer**. Paket `nodeplacer`, UCI-Config
  `/etc/config/nodeplacer`, site.conf-Block `nodeplacer`, Manifest
  `nodeplacer.manifest`, C-Helfer `nodeplacer-fetch`, Hauptprogramm
  `/usr/sbin/nodeplacer`. Projektordner umbenannt nach
  `~/projekte/freifunk/packages/nodeplacer`.
* Historie: Arbeitstitel war "domainswitch"; verworfen wegen Kollision mit
  `gluon-scheduled-domain-switch` und `gluon-switch-domain`. Anforderung
  war: keine negativen, z. B. xenophoben Konnotationen wie "forced
  migration". "nodeplacer" (der Knoten wird platziert) erfuellt das.
* Fuer ein Upstreaming in community-packages waere ein Community-Praefix
  (`nef-nodeplacer`, `eulenfunk-nodeplacer`) ueblich; entscheiden wir dann.

## D-002 Primaere Zielversion

* Status: **entschieden** (adorfer, 2026-09-04)
* Gluon **v2023.2.x** zuerst. Perspektive v2025.1. Backport v2021.1.x
  (es gibt kein Gluon 2021.2; gemeint ist die Reihe v2021.1.x, die die
  Firmware frueher benutzt hat).

## D-003 Steuerkanal ueber signiertes Manifest im Autoupdater-Stil

* Status: **entschieden** (Vorgabe adorfer, bestaetigt durch Recherche)
* Gleiches Rahmenformat wie das Autoupdater-Manifest (Kopf, Nutzdaten,
  `---`, Signaturen), damit `contrib/sign.sh`, `ecdsasign` und die
  vorhandenen Schluessel unveraendert funktionieren.
* Mindestsignaturen und Mirrors kommen aus site.conf, nicht aus dem
  Manifest.

## D-004 Signaturpruefung mit libecdsautil

* Status: **entschieden** (adorfer: "libecdsautil ist perfekt", 2026-09-04)
* Begruendung: liegt wegen des Autoupdaters auf jedem Knoten; gleiche
  Krypto, gleiche Schluesselformate, gleiche Semantik (n-of-m, legacy).
* Umsetzungsform noch **offen**:
  * (a) Paket `ecdsautils` als Abhaengigkeit, Aufruf von `ecdsaverify -s ... -p ... -n N <datei>`
    aus Lua. Vorher muss Lua die Datei an `---` teilen und den oberen Teil
    in eine Temp-Datei schreiben. Kein eigener C-Code, aber ein zusaetzliches
    Feed-Paket im Image.
  * (b) Kleiner C-Helper im Package (`src/verify.c`, CMake wie
    `autoupdater/src`), der die Manifest-Semantik des Autoupdaters
    (`manifest.c`: hashen bis `---`, Signaturen danach) 1:1 uebernimmt und
    nur "gueltig ja/nein plus Anzahl" zurueckgibt. Code ist BSD-2-Clause und
    kann uebernommen werden.
  * Tendenz: (b), weil es ohne Temp-Dateien auskommt, keine Feed-Abhaengigkeit
    einfuehrt und exakt das Verhalten des Autoupdaters hat. Nachteil:
    Build-Komplexitaet und Backport-Test auf OpenWrt 19.07.

## D-005 Multidomain-Wechsel ueber `gluon-switch-domain`

* Status: **entschieden** (aus Recherche)
* Statt `uci set gluon.core.domain` + `gluon-reconfigure` + `reboot` (Sketch)
  wird das Core-Kommando `gluon-switch-domain <domain>` benutzt. Es setzt
  `switch_domain`, committet und rebootet; gluon-core wendet den Wechsel
  beim Boot an. Identisch in v2021.1, v2023.2, v2025.1.

## D-006 Single-Domain-Wechsel ueber Autoupdater-Kommandozeile

* Status: **entschieden** (aus Recherche)
* `autoupdater -f --force-version -b <branch> <mirror...>`. Mirrors per
  Kommandozeile statt UCI-Umschreiben; Pubkeys aus der lokalen
  Branch-Section. UCI-Delta ohne Commit nur im Sonderfall "Branch lokal
  unbekannt".
* `--force-version` ist Pflicht (gleiche Versionsnummer in Zieldomain).
* Beide Optionen sind auch in v2021.1.x vorhanden (diff gegen packages-Feed
  v2021.1.x).

## D-007 Node-Identitaet

* Status: **entschieden** (aus Recherche)
* `gluon.util.node_id()` (Primary-MAC ohne Doppelpunkte). Entspricht
  nodeinfo `node_id` und ist protokollunabhaengig. `network.bat0.macaddr`
  aus dem Sketch ist in Gluon dieselbe Adresse, aber nicht bei Layer-3-Mesh.

## D-008 Implementierungssprache

* Status: **entschieden** (adorfer, 2026-09-04)
* Moeglichst viel in **Lua**, nicht in Shell. Begruendung: Gluon-Konvention
  (luasrc, Minify), bessere Testbarkeit auf dem Host, `simple-uci`,
  `posix`, `jsonc` verfuegbar. Shell nur, wo unvermeidbar. C nur fuer
  Signaturpruefung (D-004) und respondd-Provider.

## D-009 Schalter zum Abschalten

* Status: **entschieden** (Vorgabe adorfer)
* `nodeplacer.disable` mit Default `0` (bewusst doppelte Verneinung,
  analog zu Schaltern wie `vpn-disable`).
* Hinweis aus der Recherche: Gluon-Core-Pakete verwenden `enabled`
  (`autoupdater.settings.enabled`, `mesh_vpn.enabled`). Falls das Package
  in community-packages upstream gehen soll, koennte ein Reviewer
  `enabled` verlangen. Kein Blocker, nur festgehalten.

## D-010 Dateiname und Aufteilung des Manifests

* Status: **entschieden**, revidiert 2026-09-04
* Erster Vorschlag war eine Datei pro Quell-Domain
  (`<site_code>.manifest`). Verworfen, weil die Manifeste **von Hand
  gepflegt und von Hand signiert** werden (adorfer): eine Datei pro Domain
  hiesse mehrere Dateien editieren und mehrfach signieren.
* Jetzt: genau **eine Datei `nodeplacer.manifest`** pro Mirror
  (`<mirror>/nodeplacer.manifest`). Alle Knoten der Community laden
  dieselbe Datei; sie ist bei manueller Pflege klein (Handvoll Zeilen).
* Bestaetigt 2026-09-04 (adorfer): **eine zentrale Datei fuer alle 40+
  Domains** von Neanderfunk, damit der Maintenance-Aufwand der Admins klein
  bleibt. Folge: `nodeplacer.mirrors` in allen Site-Templates zeigt auf
  denselben zentralen Pfad (z. B. `http://firmware.ffnef.de/nodeplacer`),
  nicht auf die domainspezifischen Firmware-Verzeichnisse.
* Aufteilung pro Domain bleibt als spaetere Optimierung moeglich (Knoten
  probiert erst `<site_code>.manifest`, dann `nodeplacer.manifest`),
  wird in FORMAT=1 aber nicht umgesetzt.

## D-011 hoodselector

* Status: **entschieden** (adorfer, 2026-09-04: out of scope)
* Kompatibilitaet mit `gluon-hoodselector` ist nicht gefordert; er wird
  nicht eingesetzt. Im Makefile trotzdem `CONFLICTS:=+gluon-hoodselector`
  eintragen, damit ein versehentliches Zusammenbauen beim Build scheitert
  statt im Betrieb (hoodselector wuerde jeden Wechsel binnen 2 Minuten
  zurueckdrehen). Kein Override, keine weitere Beruecksichtigung.

## D-012 Alles im RAM, Versuchslimit als rollendes Fenster

* Status: **entschieden** (adorfer, 2026-09-04)
* Der Knoten schreibt fuer einen Wechselversuch **nichts ins Flash**:
  * UCI-Aenderungen fuer den Autoupdater-Lauf (Branch-Section, Mirrors,
    Pubkeys) nur per `uci set`/`uci:save` ins Delta unter `/tmp/.uci`,
    **kein `uci commit`**. libuci wendet das Delta beim Laden an, der
    Autoupdater sieht die Werte. Nach Reboot ist alles weg.
  * Wo die Kommandozeile reicht (`-b`, Mirrors als Argumente), ist auch
    das Delta unnoetig (D-006). Beides ist RAM-only.
  * Versuchszaehler und "zuletzt angewandtes DATE" liegen in `/tmp`
    (uptime-basiert), nicht in UCI.
  * Einzige Ausnahme: `gluon-switch-domain` committet `gluon` selbst; das
    ist Core-Verhalten und noetig, damit der Wechsel den Reboot ueberlebt.
* Versuchslimit: **3 Versuche in 7 Tagen**, als rollendes Fenster, also
  nicht endgueltig aufgeben: nach Ablauf des Fensters wieder 3 Versuche,
  ggf. "ewig". Der Betreiber beendet das durch Entfernen der Zeile oder
  ueber `EXPIRES`.
* Folge: ein Reboot (Stromausfall) setzt den Zaehler zurueck. Akzeptiert,
  weil der Zaehler nur Flapping und Dauerlast auf dem Mirror begrenzen
  soll, nicht Sicherheit herstellt. Sicherheit kommt aus Signatur und
  `EXPIRES`.
* Ersetzt die UCI-Section `state` aus dem ersten Entwurf.

## D-013 respondd-Provider

* Status: **entschieden** (Vorschlag Claude, offen fuer Einspruch)
* Kleiner Provider fuer `nodeinfo.software.nodeplacer`, damit auf der
  Karte sichtbar ist, welche Knoten adressiert wurden und haengen.

## D-014 Projektort und Repository

* Status: **entschieden**
* Entwicklung in `~/projekte/freifunk/packages/nodeplacer` (eigenes
  Git-Repo). Auslieferung spaeter ueber den eulenfunk-Feed
  (https://github.com/eulenfunk/packages, Branch v2023.2.x) oder
  community-packages.

## D-015 Kern aus der Autoupdater-Codebasis ableiten

* Status: **entschieden** (adorfer, 2026-09-04: "faktisch die gleiche
  Codebasis wie der Gluon-Autoupdater")
* Der Autoupdater (`packages`-Feed, `admin/autoupdater/src`, BSD-2-Clause)
  enthaelt bereits alles, was der Steuerkanal braucht:
  * `uclient.c`: HTTP-Download ueber libuclient (IPv6, Redirects,
    Timeouts, Groessenlimit)
  * `manifest.c`: zeilenweises Hashen bis `---`, Signaturen danach
  * `autoupdater.c`: Signaturpruefung n-of-m mit libecdsautil, Mirror-
    Zufallsauswahl, Lockfile, Ausgabe/Fehlerbehandlung
  * `settings.c`: UCI-Listen (mirror, pubkey, good_signatures) laden
  * `hexutil.c`, `util.c`: Hex-Parsing, safe_malloc, run_dir
* Daraus wird ein C-Programm `nodeplacer-fetch` (Arbeitsname): laedt das
  Nodeplacer-Manifest von den konfigurierten Mirrors, prueft Signaturen
  und Kopf, gibt bei Erfolg die Nutzdatenzeile(n) fuer die eigene Node-ID
  (oder den ganzen verifizierten Nutzdatenteil) auf stdout aus; Exit-Code
  unterscheidet "nicht adressiert", "kein Manifest", "Signatur ungueltig",
  "Fehler".
* Die **Policy** (Plausibilitaet, Zustand/Versuchslimit, Auswahl und Aufruf
  von `gluon-switch-domain` bzw. `autoupdater`) bleibt in **Lua**
  (`/usr/sbin/nodeplacer`), passend zu D-008. Damit ist der C-Teil ein
  duenner, gut abgegrenzter Fork ohne Geschaeftslogik, und der Lua-Teil ist
  auf dem Host testbar.
* Ersetzt die Umsetzungsfrage in D-004: (b) mit erweitertem Umfang
  (Download + Verify statt nur Verify). Kein `uclient-fetch` aus Lua noetig
  (schliesst offene Frage 7 in DESIGN.md).
* Lizenz: BSD-2-Clause beibehalten, SPDX-Header mit Herkunftshinweis.

## D-016 Manifest-Format: zeilenbasiert wie das Autoupdater-Manifest

* Status: **entschieden** (Formatwahl an Claude delegiert, 2026-09-04)
* Kein JSON, kein CSV. Gruende:
  * Die Signatur deckt den Text vor `---` byteweise ab. JSON muesste
    kanonisiert werden; jede Neuformatierung durch einen Editor braeche die
    Signatur. Zeilen mit Whitespace-Trennung sind robust gegen Editoren.
  * `contrib/sign.sh` und `ecdsasign` funktionieren unveraendert, weil sie
    nur die `---`-Zeile kennen muessen.
  * Menschen editieren die Datei von Hand; Kopf `KEY=VALUE`, eine Zeile
    pro Knoten, `#`-Kommentare. Sieht aus wie das bekannte
    Firmware-Manifest.
  * Der C-Helfer (D-015) kann den Parser des Autoupdaters fast unveraendert
    benutzen; Lua parst die Nutzdaten mit `string.match`.
  * CSV haette keine Vorteile gegenueber Whitespace-Trennung, aber
    Quoting-Fragen bei URLs.
* Details in MANIFEST-FORMAT.md.

## D-017 Serverseite

* Status: **entschieden** (adorfer, 2026-09-04)
* Keine Automatisierung, keine Server-Skripte im Projekt. Die Datei
  `nodeplacer.manifest` wird manuell editiert und manuell signiert, mit
  denselben Werkzeugen und Schluesseln wie die Firmware-Manifeste.
* Folge fuer das Format: Eintraege muessen ohne Werkzeug tippbar und
  pruefbar sein (Node-ID, Methode, Ziel); `EXPIRES` ist Pflicht, damit
  vergessene Eintraege nicht ewig wirken.

## D-018 Listen in einer Manifestzeile: wiederholbare `key=wert`-Token

* Status: **entschieden** (Frage adorfer, Entscheidung Claude, 2026-09-04)
* Nutzdatenzeile: `<node_id> <methode> key=wert [key=wert ...]`.
  Mirror-Listen als `mirror=URL mirror=URL ...`, Reihenfolge der Token
  beliebig, Wiederholung bildet die Liste.
* Verworfen: Positionsfelder (brechen bei optionalem `branch` vor der
  Liste) und Kommalisten (Komma ist in URLs zulaessig, Zeile wird
  unleserlich).
* Strenge Validierung: unbekannter Key oder fehlender Pflicht-Key macht die
  Zeile ungueltig (Log, keine Aktion). Bei Handpflege soll ein Tippfehler
  zu "nichts" fuehren.
* Zeilenlimit im C-Helfer von 512 auf 2048 Zeichen anheben (vier
  Neanderfunk-Mirrors sind etwa 450 Zeichen).

## D-019 Keine Knotenregistrierung bei Neanderfunk, aber Doku-Pflicht

* Status: **entschieden** (adorfer, 2026-09-04)
* Neanderfunk hat keine fastd-Schluessel- oder sonstige Knotenregistrierung;
  fuer die eigene Community ist das kein Thema.
* In der Doku muss stehen: Hat die **Zieldomain** solche Mechanismen
  (Peer-Registrierung, Whitelist, Zertifikate), muss der Knoten dort vor
  dem Umzug bekannt gemacht werden, sonst kommt er ohne VPN an. Das
  betrifft vor allem Umzuege in Domains fremder Communities.

## D-020 Umzug in Fremd-Domains: abgestimmtes Verfahren, sonst off limits

* Status: **entschieden** (adorfer, 2026-09-04)
* Begriff (adorfer): "Fremd-Domain" = Domain einer anderen Community in
  einer anderen Region. Andere Domains der eigenen Community sind keine
  Fremd-Domains, sondern der Normalfall.
* Technisch: Sysupgrade behaelt die UCI-Konfiguration. Nach dem Flash einer
  fremden Firmware bleiben Keys aus der alten site.conf (Hostname-Praefix,
  Branch-Namen, Zusatzpakete, Preserved-Settings) bestehen. Die
  **Zielfirmware** muss damit umgehen koennen; in vielen Faellen wird die
  Ziel-Community eine eigene Migrations-Firmware bauen muessen (Vorbild:
  Migrationspakete wie `ffac-change-autoupdater`,
  `eulenfunk-migrate-updatebranch`).
* Organisatorisch: Ein Umzug in eine fremde Domain verlangt ein zwischen
  den Communities abgestimmtes Verfahren (Schluessel, Firmware, Zeitpunkt,
  Ansprechpartner). Knoten "kalt" in eine fremde Domain zu schieben soll
  nicht nur technisch scheitern, sondern ist **off limits**.
* nodeplacer selbst bleibt auf "gleiche Community" ausgelegt (Minimum-
  Feature). Es verhindert Fremd-Umzuege nicht aktiv (die Signaturen der
  eigenen Maintainer entscheiden), aber die Doku macht die Grenze klar.

## D-021 C-Helfer gibt den ganzen Nutzdatenteil aus; Groessenannahmen

* Status: **entschieden** (adorfer, 2026-09-04)
* `nodeplacer-fetch` gibt den kompletten verifizierten Teil vor `---` aus,
  Lua filtert die eigene Node-ID heraus. Der C-Teil bleibt frei von
  Node-ID-Logik; Gruppenadressierung ist spaeter moeglich.
* Inhalt der Datei sind nur die **Ausnahmefaelle**: Knoten, die
  umplatziert werden sollen. Nach dem Umzug entfernen die Admins die Zeile
  von Hand wieder.
* Groessenannahme fuer die Implementierung: **nie mehr als 100 Knoten,
  in der Regel unter 10.** Bei 500 Bytes pro Zeile sind das maximal etwa
  50 KB. Die Datei wird komplett im RAM gehalten (C-Puffer und Lua-String),
  kein Streaming, keine Obergrenzen-Optimierung. Als Schutz gegen
  fehlerhafte Server begrenzt der Helfer den Download hart (Vorschlag
  256 KB) und bricht darueber ab.

## D-022 Repo-Layout: Projekt-Repo ist der Feed

* Status: **entschieden** (Claude, 2026-09-04)
* Das Paket liegt unter `nodeplacer/` im Projekt-Repo. OpenWrt-Feeds
  suchen rekursiv nach `Makefile`s, das Repo kann also direkt als
  `GLUON_SITE_FEEDS`-Feed eingebunden werden. Docs, Skizzen und Tests
  bleiben ausserhalb des Paketverzeichnisses.
* Alternative (Paket in eulenfunk/packages einpflegen) bleibt fuer die
  Auslieferung offen; fuer die Entwicklung ist ein eigenes Repo einfacher.

## D-023 Aufruf des C-Helfers per os.execute mit Ausgabedatei

* Status: **entschieden** (Claude, 2026-09-04)
* `gluon.util.subprocess.popen` gibt es erst ab Gluon 2023.x, nicht in
  v2021.1.x. Fuer den Backport ruft das Lua-Hauptprogramm den Helfer
  deshalb per `os.execute('nodeplacer-fetch > /tmp/nodeplacer.body')` auf
  und dekodiert den Wait-Status (Lua 5.1 liefert `exit << 8`).
* stderr des Helfers geht durch (micrond-Log), stdout nur in die Datei.

## D-024 Abbruch bei laufendem Autoupdater

* Status: **entschieden** (adorfer, 2026-09-04; ersetzt den ersten Vorschlag
  "keine Pruefung")
* Der Autoupdater lockt per `flock(2)` und haelt den Lock ueber den exec
  von sysupgrade hinweg. luaposix kann flock-Locks nicht testen (nur
  fcntl-Locks, die davon unabhaengig sind).
* Umsetzung: das Lua-Hauptprogramm liest `/proc/[0-9]*/comm` und bricht
  still ab, wenn ein Prozess `autoupdater` oder `sysupgrade` heisst.
  Damit sind beide Phasen abgedeckt (Download/Pruefung und das eigentliche
  Flashen).
* Zusaetzlich stoppt `gluon-autoupdater` micrond in `download.d`, sodass
  nodeplacer waehrend eines Updates ohnehin nicht mehr gestartet wird.

## D-025 Autoupdater-Quellen aus dem zu Gluon passenden Feed-Stand

* Status: **entschieden** (Claude, 2026-09-04, nach Build-Fehler)
* Die zuerst uebernommene `uclient.c` aus dem `main`-Branch des
  packages-Feeds benutzt `uclient_new_ssl_context()` (HTTPS-Support),
  das in libuclient von OpenWrt 23.05 (2023-04-13) nicht existiert:
  Linker-Fehler beim Bau fuer Gluon 2023.2.x.
* Uebernommen wird deshalb der Stand des Feeds, den Gluon v2023.2.x pinnt
  (`PACKAGES_GLUON_COMMIT` d75722c, `admin/autoupdater/src`). Die Dateien
  `uclient.c`/`uclient.h` sind dort ohne SSL; `hexutil.c`, `manifest.c`,
  `util.c` sind zwischen 2023.2 und main identisch.
* Fuer v2025.1 (neuere libuclient, HTTPS-Mirrors) kann spaeter wieder die
  SSL-faehige Variante verwendet werden; nodeplacer-Mirrors sind bis dahin
  `http://` (check_site erzwingt das).

## D-026 Multidomain deutlich zurueckgestellt

* Status: **entschieden** (adorfer, 2026-09-04)
* Bis zum ersten finalen Release wird nur mit Single-Domain-Firmware
  gearbeitet und getestet (Methode `firmware`). Multidomain-Firmware und
  damit die Methode `domain` kommen erst danach; dafuer sind mehrere
  externe Dinge zu klaeren, unter anderem "nodeplacer funktioniert in der
  Praxis".
* Der `domain`-Codepfad bleibt im Paket (klein, an `gluon-switch-domain`
  delegiert), gilt aber als **ungetestet** und wird im README so
  gekennzeichnet. Kein Multidomain-Testimage, kein qemu-Test dafuer.

## D-027 Release wartet auf Aenderungen im Buildsystem

* Status: **entschieden** (adorfer, 2026-09-04)
* Kein Release, keine Feed-Einbindung und keine Aenderung an den
  Site-Templates, bevor die noetigen Aenderungen im Buildsystem
  (`~/projekte/freifunk/firmware`) gemacht sind. Die Release-Schritte aus
  DESIGN/TESTING bleiben als Liste stehen, werden aber nicht angegangen,
  bis adorfer das Signal gibt.

## D-028 Entwicklungs-Repo bei Adorfer, Teilmenge im Community-Feed

* Status: **entschieden** (adorfer, 2026-09-04)
* Das **gesamte** Projekt liegt in `Adorfer/nodeplacer-dev` (privat).
* In den Community-Feed `Neanderfunk/packages`, Branch `v2023.2.x`, wandert
  nur die veroeffentlichte Teilmenge, eingebettet als Verzeichnis
  `nodeplacer/`, weil OpenWrt-Feeds ein Paket je Verzeichnis erwarten:
  * `nodeplacer/` (das Paket) nach `nodeplacer/`
  * `docs/` nach `nodeplacer/docs/`
  * die Projekt-`README.md` nach `nodeplacer/docs/PROJEKT.md`, damit sie
    weder die Feed-`README.md` noch die Paket-`README.md` verdraengt.
* Synchronisation mit `scripts/sync-to-feed.sh`: ein Commit je Lauf, nur
  das Verzeichnis `nodeplacer/` wird angefasst, die Historie des Feeds wird
  nicht umgeschrieben. Kein Force-Push, kein `filter-branch` auf dem Feed.
* Verworfen: ein eigenes abgeleitetes GitHub-Repo (`Adorfer/nodeplacer`)
  mit gefilterter Historie. Es war ein Zwischenschritt und wird nicht
  weiter gepflegt.
* Wichtig: Dateien im Feed zu haben ist noch **kein** Release. Solange
  keine Site ihren `modules`-Commit hochzieht und `nodeplacer` in
  `image-customization.lua` listet, aendert sich an keinem Build etwas
  (siehe D-027).
